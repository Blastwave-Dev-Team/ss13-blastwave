// MODULE ID: OVERMAP
// Flight Ops radar console: canvas TGUI, sweep request, contact print / transcript.

GLOBAL_LIST_EMPTY(overmap_radar_consoles)

/// Orders radar contact assocs nearest first, for paying a contact list out to a console.
/proc/cmp_radar_contact_distance(list/contact_a, list/contact_b)
	return contact_a["distance"] - contact_b["distance"]

/obj/machinery/computer/overmap_radar
	name = "deep-space radar console"
	desc = "Plots contacts from a linked station radar array. Each console aims, tracks, and sweeps independently. Narrower sweeps reach farther."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	circuit = /obj/item/circuitboard/computer/overmap_radar
	light_color = LIGHT_COLOR_BLUE
	/// Linked radar machines (dish / processor / bus).
	var/list/radar_links = list()
	var/list/autolinkers = list(OVERMAP_RADAR_AUTOLINK_CONSOLE)
	var/id = "Radar Console"
	var/network = OVERMAP_RADAR_NETWORK_FOC
	var/toggled = TRUE
	var/on = TRUE
	var/datum/powernet/forced_powernet
	/// Last-seen contacts keyed by overmap ref.
	var/list/tracked_contacts = list()
	/// Track labels keyed by overmap ref. An auto T-number is held until the contact decays out.
	var/list/track_labels = list()
	/// Operator-chosen labels keyed by overmap ref. Survives contact decay and later sweeps.
	var/list/manual_tracks = list()
	/// Next default track index (T1, T2, ...). Never resets; only increments.
	var/next_track_index = 1
	/// Rolling sweep snapshots for transcript print.
	var/list/transcript_log = list()
	/// Contact ids being paid out to the interface this cycle, in the order they go.
	var/list/drain_order = list()
	/// How far through drain_order the current batch starts. Zero means the cycle has not begun.
	var/drain_cursor = 0
	/// Cycle counter. The interface uses a change here to know a fresh payout has started.
	var/drain_seq = 0
	/// Timer paying out the remaining batches, if a cycle is in flight.
	var/drain_timer
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
	if(drain_timer)
		deltimer(drain_timer)
		drain_timer = null
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

	if(prune_contacts())
		// A pruned contact has to come out of the payout order too, or the cycle would keep offering
		// an id that is gone. Restarting is how the interface is told to retire it.
		begin_drain()
	if(old_on != on)
		update_appearance()
		push_ui()

/**
 * Pushes our state to any open console window.
 *
 * The interface does not poll. It holds a server clock reading and animates the sweep and the contact
 * fades off it locally, so the only pushes are the ones something actually changed. Every caller here
 * is a real change an operator can see; adding one that is not puts the idle traffic back.
 */
/obj/machinery/computer/overmap_radar/proc/push_ui()
	SStgui.update_uis(src)

/**
 * Starts paying the contact list out to the interface from the beginning.
 *
 * Restarting mid-cycle is fine and is what a fresh sweep does: the interface stages whatever it is
 * handed against the cycle number, so an abandoned cycle is discarded rather than half-applied.
 */
/obj/machinery/computer/overmap_radar/proc/begin_drain()
	reset_drain()
	push_ui()
	arm_next_batch()

/**
 * Rebuilds the payout order and opens a new cycle, without sending anything.
 *
 * Split out because a window's own opening payload is the first batch of its cycle, so the order has
 * to exist before the window opens rather than being pushed to it afterwards.
 */
/obj/machinery/computer/overmap_radar/proc/reset_drain()
	if(drain_timer)
		deltimer(drain_timer)
		drain_timer = null
	drain_order = sorted_contact_ids()
	drain_cursor = 0
	drain_seq++

	// A contact count that needs several pushes to pay out is the leading indicator of the client
	// hitching this batching exists to prevent, so it is worth a line when it happens. Thresholded
	// rather than logged every cycle: a quiet sector should not write anything at all.
	var/pushes = CEILING(length(drain_order) / OVERMAP_RADAR_DRAIN_BATCH, 1)
	if(pushes > OVERMAP_RADAR_DRAIN_LOG_PUSHES)
		logger.Log(LOG_CATEGORY_DEBUG, "radar console at [AREACOORD(src)] is paying out [length(drain_order)] contacts across [pushes] pushes.")

/// Whether the batch under the cursor is the last one this cycle owes.
/obj/machinery/computer/overmap_radar/proc/drain_complete()
	return (drain_cursor + OVERMAP_RADAR_DRAIN_BATCH) >= length(drain_order)

/// Queues the next batch if this cycle has any left to pay out.
/obj/machinery/computer/overmap_radar/proc/arm_next_batch()
	if(drain_complete())
		return
	drain_timer = addtimer(CALLBACK(src, PROC_REF(advance_drain)), OVERMAP_RADAR_DRAIN_INTERVAL, TIMER_UNIQUE|TIMER_OVERRIDE|TIMER_STOPPABLE)

/// Moves to the next batch and pushes it.
/obj/machinery/computer/overmap_radar/proc/advance_drain()
	drain_timer = null
	if(drain_complete())
		return
	drain_cursor += OVERMAP_RADAR_DRAIN_BATCH
	push_ui()
	arm_next_batch()

/**
 * Contact ids in the order they are paid out, nearest first.
 *
 * Nearest first so that a partly painted scope is still the useful half of the picture. A contact
 * about to run us down matters more than one at the edge of the dish's reach.
 */
/obj/machinery/computer/overmap_radar/proc/sorted_contact_ids()
	var/list/entries = list()
	for(var/contact_id in tracked_contacts)
		entries += list(tracked_contacts[contact_id])
	sortTim(entries, GLOBAL_PROC_REF(cmp_radar_contact_distance))

	var/list/ids = list()
	for(var/list/contact as anything in entries)
		ids += contact["ref"]
	return ids

/// Batch of contact ids the current cursor points at, clipped to what is actually there.
/obj/machinery/computer/overmap_radar/proc/current_batch_ids()
	if(!length(drain_order))
		return list()
	var/last = min(drain_cursor + OVERMAP_RADAR_DRAIN_BATCH, length(drain_order))
	return drain_order.Copy(drain_cursor + 1, last + 1)

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

	// A track an operator is already watching keeps its number for as long as we hold the contact.
	// Re-minting it every sweep is what sent serials into the thousands over a single shift, and it
	// made the label useless for talking about a contact out loud.
	var/existing = track_labels[contact_id]
	if(existing)
		return existing

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
	begin_drain()

/// Drops contacts we have not painted inside the decay window. Returns TRUE if anything went.
/obj/machinery/computer/overmap_radar/proc/prune_contacts()
	var/cutoff = world.time - OVERMAP_SCAN_DECAY
	var/dropped = FALSE
	for(var/contact_id in tracked_contacts)
		var/list/contact = tracked_contacts[contact_id]
		if(contact["last_seen"] < cutoff)
			tracked_contacts -= contact_id
			if(!manual_tracks[contact_id])
				track_labels -= contact_id
			if(selected_ref == contact_id)
				selected_ref = null
			dropped = TRUE
	return dropped

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
		// Deliberately off. A busy sector is tens of kilobytes of contacts, and tgui_window sends a
		// payload as one blocking write to the game client, so polling it on a timer hitched the
		// client whether or not a sweep had happened. push_ui() covers the changes that matter.
		ui.set_autoupdate(FALSE)
		// A second operator opening a window restarts the cycle for both of them. The cursor belongs
		// to the console rather than to a window, and a repaint is cheaper than tracking it per user.
		reset_drain()
		ui.open()
		arm_next_batch()

/**
 * Values that cannot change while the window is open.
 *
 * These are compile-time constants. Leaving them in ui_data() meant re-sending the sector dimensions
 * and the range ratings on every single update for the lifetime of the window.
 */
/obj/machinery/computer/overmap_radar/ui_static_data(mob/user)
	return list(
		"gridSize" = OVERMAP_DIMENSIONS,
		"minArc" = OVERMAP_RADAR_MIN_ARC,
		"wideRange" = OVERMAP_RADAR_WIDE_RANGE,
		"narrowRange" = OVERMAP_RADAR_NARROW_RANGE,
		"scanCooldown" = OVERMAP_SCAN_COOLDOWN,
		"decay" = OVERMAP_SCAN_DECAY,
	)

/**
 * A contact entry carries only what the scope and the track list draw.
 *
 * Built field by field rather than copied wholesale. The stored contact also holds the affiliation and
 * the compression it was received at, which the printed brief reads straight off tracked_contacts and
 * which no client has ever drawn, so copying the whole assoc shipped them to every operator forever.
 *
 * `last_seen` goes out as the raw stamp rather than an age. An age would be different in every single
 * payload, which makes two identical sweeps serialise differently and defeats any attempt to skip a
 * push or stream one. The client holds `serverTime` from the same payload and does the subtraction.
 *
 * Returns null for an id we no longer hold. The payout order is a snapshot taken when the cycle
 * opened, so a contact can decay out from under it before its batch is reached.
 */
/obj/machinery/computer/overmap_radar/proc/contact_payload_entry(contact_id)
	var/list/contact = tracked_contacts[contact_id]
	if(!contact)
		return null
	return list(
		"id" = contact_id,
		"track" = manual_tracks[contact_id] || track_labels[contact_id] || contact["track"],
		"name" = contact["name"],
		"type" = contact["type"],
		"type_label" = contact["type_label"],
		"x" = contact["x"],
		"y" = contact["y"],
		"bearing" = contact["bearing"],
		"distance" = contact["distance"],
		"last_seen" = contact["last_seen"],
	)

/obj/machinery/computer/overmap_radar/ui_data(mob/user)
	var/obj/structure/overmap/origin = SSovermap.main

	// Only the batch the cursor is on. Deliberately a read, and pruning from here would not be one:
	// dropping a contact mid-cycle leaves its id in the payout order with nothing behind it. process()
	// owns decay, and restarts the cycle when it takes something, which is what retires it clientside.
	var/list/batch = current_batch_ids()
	var/list/contacts = list()
	for(var/contact_id in batch)
		var/list/entry = contact_payload_entry(contact_id)
		// A gap rather than a hole: a null in the contact array is a fatal exception in the interface.
		if(entry)
			contacts += list(entry)

	var/obj/machinery/overmap_radar/dish/dish = find_linked_dish()
	return list(
		"on" = on,
		"viewerX" = origin?.x,
		"viewerY" = origin?.y,
		// Payout bookkeeping. The interface stages contacts against `drainSeq` and only retires the
		// ones it did not hear about once `drainDone` says the cycle covered everything.
		"drainSeq" = drain_seq,
		"drainDone" = drain_complete(),
		"contactTotal" = length(drain_order),
		// The clock every contact stamp is measured against. One scalar per payload replaces an age on
		// every contact, and lets the client keep the fades moving between pushes instead of per push.
		"serverTime" = world.time,
		"bearing" = sweep_bearing,
		"arcWidth" = sweep_arc,
		"animBearing" = last_sweep_bearing,
		"animArc" = last_sweep_arc,
		"range" = overmap_radar_range_for_arc(sweep_arc),
		"scanReady" = !!dish && COOLDOWN_FINISHED(src, scan_cooldown),
		"sweepLeft" = COOLDOWN_TIMELEFT(src, scan_cooldown),
		"hasDish" = !!dish,
		"selectedId" = selected_ref,
		"contacts" = contacts,
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
			// Nothing polls, so the moment the dish comes free has to announce itself or the sweep
			// control stays greyed out until some unrelated change happens to push.
			addtimer(CALLBACK(src, PROC_REF(push_ui)), OVERMAP_SCAN_COOLDOWN + 1, TIMER_UNIQUE|TIMER_OVERRIDE)
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
