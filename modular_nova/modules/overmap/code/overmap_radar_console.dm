// MODULE ID: OVERMAP
// Flight Ops radar console: canvas TGUI, sweep request, contact print / transcript.

GLOBAL_LIST_EMPTY(overmap_radar_consoles)

/obj/machinery/computer/overmap_radar
	name = "deep-space radar console"
	desc = "Plots contacts from a linked station radar array. Each console aims, tracks, and sweeps independently. Narrower sweeps reach farther."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	circuit = /obj/item/circuitboard/computer/overmap_radar
	light_color = LIGHT_COLOR_BLUE
	/// Linked radar machines (dish / processor / bus).
	var/list/radar_links = list()
	var/list/autolinkers = list(OVERMAP_RADAR_AUTOLINK_FOC)
	var/id = "Radar Console"
	var/network = OVERMAP_RADAR_NETWORK_FOC
	var/toggled = TRUE
	var/on = TRUE
	var/datum/powernet/forced_powernet
	/// Last-seen contacts keyed by overmap ref.
	var/list/tracked_contacts = list()
	/// Track labels keyed by overmap ref. Auto T-numbers are reminted each sweep.
	var/list/track_labels = list()
	/// Operator-chosen labels keyed by overmap ref. Survives contact decay and later sweeps.
	var/list/manual_tracks = list()
	/// Next default track index (T1, T2, ...). Never resets; only increments.
	var/next_track_index = 1
	/// Rolling sweep snapshots for transcript print.
	var/list/transcript_log = list()
	var/sweep_bearing = 0
	var/sweep_arc = 360
	/// Aim used by the in-progress scan-line animation.
	var/last_sweep_bearing = 0
	var/last_sweep_arc = 360
	var/printing = FALSE
	var/selected_ref
	COOLDOWN_DECLARE(scan_cooldown)

/obj/machinery/computer/overmap_radar/Initialize(mapload)
	. = ..()
	GLOB.overmap_radar_consoles += src

/obj/machinery/computer/overmap_radar/post_machine_initialize()
	. = ..()
	if(!length(autolinkers))
		return
	for(var/obj/machinery/overmap_radar/machine as anything in GLOB.overmap_radar_machines)
		if(machine.network != network)
			continue
		if(!length(machine.autolinkers & autolinkers))
			continue
		add_radar_link(machine)

/obj/machinery/computer/overmap_radar/Destroy()
	GLOB.overmap_radar_consoles -= src
	for(var/obj/machinery/overmap_radar/machine as anything in radar_links)
		machine.links -= src
	radar_links = list()
	return ..()

/obj/machinery/computer/overmap_radar/process()
	var/old_on = on
	if(toggled)
		on = !(machine_stat & (BROKEN | NOPOWER | EMPED))
	else
		on = FALSE
	if(old_on != on)
		update_appearance()
	prune_contacts()

/obj/machinery/computer/overmap_radar/proc/get_grid_powernet()
	if(forced_powernet)
		return forced_powernet
	var/area/home = get_area(src)
	return home?.apc?.terminal?.powernet

/obj/machinery/computer/overmap_radar/proc/shares_powernet_with(obj/machinery/overmap_radar/other)
	if(!istype(other))
		return FALSE
	return other.shares_powernet_with(src)

/obj/machinery/computer/overmap_radar/proc/add_radar_link(obj/machinery/overmap_radar/other, mob/user)
	if(!istype(other))
		return FALSE
	radar_links |= other
	other.links |= src
	if(user)
		user.log_message("linked [src] to [other].", LOG_GAME)
	return TRUE

/obj/machinery/computer/overmap_radar/multitool_act(mob/living/user, obj/item/tool)
	if(!istype(tool, /obj/item/multitool))
		return NONE
	if(!panel_open)
		balloon_alert(user, "panel closed")
		return ITEM_INTERACT_BLOCKING
	var/obj/item/multitool/multitool = tool
	if(istype(multitool.buffer, /obj/machinery/overmap_radar))
		add_radar_link(multitool.buffer, user)
		balloon_alert(user, "linked")
		return ITEM_INTERACT_SUCCESS
	multitool.set_buffer(src)
	balloon_alert(user, "buffered")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/computer/overmap_radar/proc/assign_track(contact_id)
	if(manual_tracks[contact_id])
		track_labels[contact_id] = manual_tracks[contact_id]
		return manual_tracks[contact_id]
	var/label = next_auto_track_label(contact_id)
	track_labels[contact_id] = label
	return label

/obj/machinery/computer/overmap_radar/proc/next_auto_track_label(contact_id)
	var/label
	do
		label = "T[next_track_index++]"
	while(track_label_in_use(label, contact_id))
	return label

/obj/machinery/computer/overmap_radar/proc/track_label_in_use(label, contact_id)
	for(var/other_id in track_labels)
		if(other_id != contact_id && track_labels[other_id] == label)
			return TRUE
	for(var/other_id in manual_tracks)
		if(other_id != contact_id && manual_tracks[other_id] == label)
			return TRUE
	return FALSE

/obj/machinery/computer/overmap_radar/proc/receive_radar_packet(datum/signal/overmap_radar/packet, obj/machinery/from_machine)
	if(!on || !packet)
		return
	var/now = world.time
	var/list/display = overmap_radar_garble_contacts(packet.contacts, packet.compression)
	for(var/list/contact as anything in display)
		var/contact_id = contact["ref"]
		contact["last_seen"] = now
		contact["compression"] = packet.compression
		contact["track"] = assign_track(contact_id)
		tracked_contacts[contact_id] = contact
	var/list/snapshot = list(
		"time" = round_timestamp(),
		"bearing" = packet.bearing,
		"arc_width" = packet.arc_width,
		"range" = packet.range,
		"compression" = packet.compression,
		"contacts" = display,
	)
	transcript_log += list(snapshot)
	if(length(transcript_log) > OVERMAP_RADAR_TRANSCRIPT_SWEEPS)
		transcript_log.Cut(1, length(transcript_log) - OVERMAP_RADAR_TRANSCRIPT_SWEEPS + 1)

/obj/machinery/computer/overmap_radar/proc/prune_contacts()
	var/cutoff = world.time - OVERMAP_SCAN_DECAY
	for(var/contact_id in tracked_contacts)
		var/list/contact = tracked_contacts[contact_id]
		if(contact["last_seen"] < cutoff)
			tracked_contacts -= contact_id
			if(!manual_tracks[contact_id])
				track_labels -= contact_id
			if(selected_ref == contact_id)
				selected_ref = null

/obj/machinery/computer/overmap_radar/proc/find_linked_dish()
	for(var/obj/machinery/overmap_radar/dish/dish as anything in radar_links)
		if(istype(dish) && dish.on && shares_powernet_with(dish))
			return dish
	for(var/obj/machinery/overmap_radar/machine as anything in radar_links)
		if(!machine.on || !shares_powernet_with(machine))
			continue
		for(var/obj/machinery/overmap_radar/dish/dish as anything in machine.links)
			if(istype(dish) && dish.on && shares_powernet_with(dish))
				return dish
	return null

/obj/machinery/computer/overmap_radar/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "OvermapRadarConsole", name)
		ui.set_autoupdate(TRUE)
		ui.open()

/obj/machinery/computer/overmap_radar/ui_data(mob/user)
	prune_contacts()
	var/obj/structure/overmap/origin = SSovermap.main
	var/list/contacts = list()
	for(var/contact_id in tracked_contacts)
		var/list/contact = tracked_contacts[contact_id]
		var/list/entry = contact.Copy()
		entry["id"] = contact_id
		entry["track"] = manual_tracks[contact_id] || track_labels[contact_id] || contact["track"]
		entry["age"] = world.time - contact["last_seen"]
		contacts += list(entry)
	var/obj/machinery/overmap_radar/dish/dish = find_linked_dish()
	return list(
		"on" = on,
		"viewerX" = origin?.x,
		"viewerY" = origin?.y,
		"gridSize" = OVERMAP_DIMENSIONS,
		"bearing" = sweep_bearing,
		"arcWidth" = sweep_arc,
		"animBearing" = last_sweep_bearing,
		"animArc" = last_sweep_arc,
		"range" = overmap_radar_range_for_arc(sweep_arc),
		"minArc" = OVERMAP_RADAR_MIN_ARC,
		"wideRange" = OVERMAP_RADAR_WIDE_RANGE,
		"narrowRange" = OVERMAP_RADAR_NARROW_RANGE,
		"scanReady" = !!dish && COOLDOWN_FINISHED(src, scan_cooldown),
		"sweepLeft" = COOLDOWN_TIMELEFT(src, scan_cooldown),
		"scanCooldown" = OVERMAP_SCAN_COOLDOWN,
		"hasDish" = !!dish,
		"selectedId" = selected_ref,
		"contacts" = contacts,
		"decay" = OVERMAP_SCAN_DECAY,
	)

/obj/machinery/computer/overmap_radar/proc/ui_number(list/params, key)
	var/value = params[key]
	if(istext(value))
		value = text2num(value)
	return isnum(value) ? value : null

/obj/machinery/computer/overmap_radar/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	switch(action)
		if("set_bearing")
			var/new_bearing = ui_number(params, "bearing")
			if(isnull(new_bearing))
				return TRUE
			sweep_bearing = SIMPLIFY_DEGREES(new_bearing)
			return TRUE
		if("set_arc")
			var/new_arc = ui_number(params, "arc")
			if(isnull(new_arc))
				return TRUE
			sweep_arc = clamp(new_arc, OVERMAP_RADAR_MIN_ARC, 360)
			return TRUE
		if("select")
			selected_ref = params["id"] || params["ref"]
			return TRUE
		if("set_track")
			var/contact_id = params["id"] || params["ref"]
			if(!contact_id)
				return TRUE
			var/label = trim(copytext_char("[params["track"]]", 1, OVERMAP_RADAR_TRACK_NAME_MAX + 1))
			if(!length(label))
				return TRUE
			if(track_label_in_use(label, contact_id))
				balloon_alert(usr, "track in use")
				return TRUE
			manual_tracks[contact_id] = label
			track_labels[contact_id] = label
			if(tracked_contacts[contact_id])
				tracked_contacts[contact_id]["track"] = label
			return TRUE
		if("sweep")
			if(!on)
				return TRUE
			if(!COOLDOWN_FINISHED(src, scan_cooldown))
				return TRUE
			var/obj/machinery/overmap_radar/dish/dish = find_linked_dish()
			if(!dish)
				balloon_alert(usr, "no linked dish")
				return TRUE
			var/datum/signal/overmap_radar/packet = dish.sweep(sweep_bearing, sweep_arc, src)
			if(!packet)
				balloon_alert(usr, "sweep unavailable")
				return TRUE
			last_sweep_bearing = sweep_bearing
			last_sweep_arc = sweep_arc
			COOLDOWN_START(src, scan_cooldown, OVERMAP_SCAN_COOLDOWN)
			say("Sweep complete: [length(packet.contacts)] contact\s.")
			return TRUE
		if("print_contact")
			if(!on)
				return TRUE
			print_selected_contact(usr)
			return TRUE
		if("print_transcript")
			if(!on)
				return TRUE
			print_transcript(usr)
			return TRUE
	return FALSE

/obj/machinery/computer/overmap_radar/proc/print_selected_contact(mob/user)
	if(printing)
		balloon_alert(user, "printer busy")
		return
	var/list/contact = tracked_contacts[selected_ref]
	if(!contact)
		balloon_alert(user, "no contact selected")
		return
	var/note = tgui_input_text(user, "Operator note (optional)", "Flight brief", max_length = 200)
	var/age = round((world.time - contact["last_seen"]) / (1 SECONDS))
	var/obj/item/paper/brief = new
	brief.name = "Flight brief — [contact["track"] || "Track"] — [contact["name"]]"
	brief.add_raw_text({"<center><h2>Flight Operations Brief</h2></center>
		<b>Track:</b> [contact["track"] || "—"]<br>
		<b>Contact:</b> [contact["name"]]<br>
		<b>Type:</b> [contact["type_label"] || contact["type"]]<br>
		<b>Affiliation:</b> [contact["affiliation"]]<br>
		<b>Grid:</b> [contact["x"]], [contact["y"]]<br>
		<b>Bearing:</b> [contact["bearing"]]°<br>
		<b>Distance:</b> [contact["distance"]]<br>
		<b>Last seen:</b> [age]s ago<br>
		<b>Issued:</b> [round_timestamp()] by [user]<br>
		<b>Notes:</b> [note || "None."]
	"})
	brief.update_appearance()
	start_print(brief, user)

/obj/machinery/computer/overmap_radar/proc/print_transcript(mob/user)
	if(printing)
		balloon_alert(user, "printer busy")
		return
	if(!length(transcript_log))
		balloon_alert(user, "no sweeps logged")
		return
	var/list/lines = list("<center><h2>Radar Transcript</h2></center><b>Issued:</b> [round_timestamp()] by [user]<br>")
	for(var/list/sweep as anything in transcript_log)
		lines += "<hr><b>Sweep</b> [sweep["time"]] — bearing [sweep["bearing"]]° / arc [sweep["arc_width"]]° / range [sweep["range"]] / compression [sweep["compression"]]<br>"
		if(!length(sweep["contacts"]))
			lines += "<i>No contacts.</i><br>"
			continue
		for(var/list/contact as anything in sweep["contacts"])
			lines += "[contact["track"] || "—"] [contact["name"]] ([contact["type_label"] || contact["type"]], [contact["affiliation"]]) @ [contact["x"]],[contact["y"]] bearing [contact["bearing"]]° dist [contact["distance"]]<br>"
	var/obj/item/paper/transcript = new
	transcript.name = "Radar transcript — [round_timestamp()]"
	transcript.add_raw_text(jointext(lines, ""))
	transcript.update_appearance()
	start_print(transcript, user)

/obj/machinery/computer/overmap_radar/proc/start_print(obj/item/paper/sheet, mob/user)
	printing = TRUE
	balloon_alert(user, "printing")
	playsound(src, 'sound/machines/printer.ogg', 100, TRUE)
	addtimer(CALLBACK(src, PROC_REF(finish_print), sheet), 2 SECONDS)

/obj/machinery/computer/overmap_radar/proc/finish_print(obj/item/paper/sheet)
	printing = FALSE
	if(QDELETED(sheet))
		return
	sheet.forceMove(drop_location())
	playsound(src, 'sound/machines/terminal/terminal_eject.ogg', 100, TRUE)
