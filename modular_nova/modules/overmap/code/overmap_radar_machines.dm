// MODULE ID: OVERMAP
// Station radar network: dish, optional bus, processor. Linking copies tcomms
// (multitool buffer + bidirectional links + autolinkers). Reachability is a
// shared electrical powernet, not Z-distance.

GLOBAL_LIST_EMPTY(overmap_radar_machines)

/obj/machinery/overmap_radar
	name = "deep-space radar machine"
	desc = "A Flight Operations radar network machine."
	abstract_type = /obj/machinery/overmap_radar
	icon = 'icons/obj/machines/telecomms.dmi'
	icon_state = "processor"
	density = TRUE
	anchored = TRUE
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION
	circuit = null
	/// Machines this unit is linked to.
	var/list/links = list()
	/// Mapped autolink tokens. Shared tokens link on LateInitialize.
	var/list/autolinkers = list(OVERMAP_RADAR_AUTOLINK_FOC)
	/// Identification string for linking UI / examine.
	var/id = "NULL"
	/// Network name; must match to autolink or manual-link.
	var/network = OVERMAP_RADAR_NETWORK_FOC
	/// Type path used to filter relay targets.
	var/radar_type
	/// Whether the machine is meant to be on.
	var/toggled = TRUE
	/// Runtime on/off after power and EMP.
	var/on = TRUE
	/// Test hook: skip APC/cable resolution when set.
	var/datum/powernet/forced_powernet

/obj/machinery/overmap_radar/Initialize(mapload)
	. = ..()
	radar_type ||= type
	register_context()
	GLOB.overmap_radar_machines += src
	if(mapload && length(autolinkers))
		return INITIALIZE_HINT_LATELOAD

/obj/machinery/overmap_radar/LateInitialize()
	. = ..()
	for(var/obj/machinery/overmap_radar/other as anything in GLOB.overmap_radar_machines)
		if(other == src || other.network != network)
			continue
		if(!length(other.autolinkers & autolinkers))
			continue
		add_radar_link(other)
	for(var/obj/machinery/computer/overmap_radar/console as anything in GLOB.overmap_radar_consoles)
		if(console.network != network)
			continue
		if(!length(console.autolinkers & autolinkers))
			continue
		console.add_radar_link(src)

/obj/machinery/overmap_radar/Destroy()
	GLOB.overmap_radar_machines -= src
	for(var/obj/machinery/other as anything in links)
		if(istype(other, /obj/machinery/overmap_radar))
			remove_radar_link(other)
		else if(istype(other, /obj/machinery/computer/overmap_radar))
			var/obj/machinery/computer/overmap_radar/console = other
			console.radar_links -= src
	links = list()
	return ..()

/obj/machinery/overmap_radar/process()
	update_radar_power()

/obj/machinery/overmap_radar/emp_act(severity)
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	if(prob(100 / severity) && !(machine_stat & EMPED))
		set_machine_stat(machine_stat | EMPED)
		addtimer(CALLBACK(src, PROC_REF(clear_radar_emp)), (30 SECONDS) / severity)

/obj/machinery/overmap_radar/proc/clear_radar_emp()
	set_machine_stat(machine_stat & ~EMPED)
	update_radar_power()

/obj/machinery/overmap_radar/proc/update_radar_power()
	var/old_on = on
	if(toggled)
		on = !(machine_stat & (BROKEN | NOPOWER | EMPED))
	else
		on = FALSE
	if(old_on != on)
		update_appearance()

/obj/machinery/overmap_radar/proc/get_grid_powernet()
	if(forced_powernet)
		return forced_powernet
	var/area/home = get_area(src)
	return home?.apc?.terminal?.powernet

/obj/machinery/overmap_radar/proc/shares_powernet_with(obj/machinery/other)
	var/datum/powernet/mine = get_grid_powernet()
	var/datum/powernet/theirs
	if(istype(other, /obj/machinery/overmap_radar))
		var/obj/machinery/overmap_radar/radar = other
		theirs = radar.get_grid_powernet()
	else if(istype(other, /obj/machinery/computer/overmap_radar))
		var/obj/machinery/computer/overmap_radar/console = other
		theirs = console.get_grid_powernet()
	if(!mine || !theirs)
		return FALSE
	return mine == theirs

/obj/machinery/overmap_radar/proc/add_radar_link(obj/machinery/overmap_radar/other, mob/user)
	if(!istype(other) || other == src)
		return FALSE
	if((other in links) && (src in other.links))
		return FALSE
	links |= other
	other.links |= src
	if(user)
		user.log_message("linked [src] to [other].", LOG_GAME)
	return TRUE

/obj/machinery/overmap_radar/proc/remove_radar_link(obj/machinery/overmap_radar/other, mob/user)
	if(!istype(other) || other == src)
		return FALSE
	links -= other
	other.links -= src
	if(user)
		user.log_message("unlinked [src] and [other].", LOG_GAME)
	return TRUE

/obj/machinery/overmap_radar/proc/receive_radar_packet(datum/signal/overmap_radar/packet, obj/machinery/from_machine)
	return

/obj/machinery/overmap_radar/proc/relay_radar_packet(datum/signal/overmap_radar/packet, filter)
	if(!on || !packet)
		return 0
	var/sent = 0
	for(var/obj/machinery/overmap_radar/other as anything in links)
		if(!other.on)
			continue
		if(filter && !istype(other, filter))
			continue
		if(!shares_powernet_with(other))
			continue
		other.receive_radar_packet(packet, src)
		sent++
	if(!filter || ispath(filter, /obj/machinery/computer/overmap_radar))
		for(var/obj/machinery/computer/overmap_radar/console as anything in GLOB.overmap_radar_consoles)
			if(packet.dest_console && console != packet.dest_console)
				continue
			if(!console.on)
				continue
			if(!(src in console.radar_links) && !(console in links))
				continue
			if(!shares_powernet_with(console))
				continue
			console.receive_radar_packet(packet, src)
			sent++
	return sent

/obj/machinery/overmap_radar/multitool_act(mob/living/user, obj/item/tool)
	if(!istype(tool, /obj/item/multitool))
		return NONE
	if(!panel_open)
		balloon_alert(user, "hatch closed")
		return ITEM_INTERACT_BLOCKING
	var/obj/item/multitool/multitool = tool
	if(multitool.buffer == src)
		multitool.set_buffer(null)
		balloon_alert(user, "buffer cleared")
		return ITEM_INTERACT_SUCCESS
	if(istype(multitool.buffer, /obj/machinery/overmap_radar))
		var/obj/machinery/overmap_radar/other = multitool.buffer
		if(add_radar_link(other, user))
			balloon_alert(user, "linked")
		else
			balloon_alert(user, "already linked")
		return ITEM_INTERACT_SUCCESS
	if(istype(multitool.buffer, /obj/machinery/computer/overmap_radar))
		var/obj/machinery/computer/overmap_radar/console = multitool.buffer
		console.add_radar_link(src, user)
		balloon_alert(user, "linked")
		return ITEM_INTERACT_SUCCESS
	multitool.set_buffer(src)
	balloon_alert(user, "buffered")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/overmap_radar/screwdriver_act(mob/living/user, obj/item/tool)
	return default_deconstruction_screwdriver(user, tool)

/obj/machinery/overmap_radar/crowbar_act(mob/living/user, obj/item/tool)
	return default_deconstruction_crowbar(user, tool)

/obj/machinery/overmap_radar/on_set_panel_open(old_value)
	. = ..()
	update_appearance()

/obj/machinery/overmap_radar/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	. = ..()
	if(isnull(held_item))
		return
	if(held_item.tool_behaviour == TOOL_SCREWDRIVER)
		context[SCREENTIP_CONTEXT_LMB] = "[panel_open ? "Close" : "Open"] maintenance hatch"
		return CONTEXTUAL_SCREENTIP_SET
	if(held_item.tool_behaviour == TOOL_CROWBAR && panel_open)
		context[SCREENTIP_CONTEXT_LMB] = "Deconstruct"
		return CONTEXTUAL_SCREENTIP_SET
	if(held_item.tool_behaviour == TOOL_MULTITOOL && panel_open)
		context[SCREENTIP_CONTEXT_LMB] = "Buffer / link"
		return CONTEXTUAL_SCREENTIP_SET

/obj/machinery/overmap_radar/examine(mob/user)
	. = ..()
	. += span_notice("Network: [network]. ID: [id].")
	. += span_notice("A <i>screwdriver</i> [panel_open ? "closes" : "opens"] the maintenance hatch[panel_open ? "; a <i>multitool</i> buffers or links it, and a <i>crowbar</i> deconstructs it" : ""].")
	if(!get_grid_powernet())
		. += span_warning("No station powernet resolved — packets will not relay.")

/obj/machinery/overmap_radar/update_icon_state()
	icon_state = "[initial(icon_state)][panel_open ? "_o" : null][on ? null : "_off"]"
	return ..()

// --- Processor ---

/obj/machinery/overmap_radar/processor
	name = "deep-space radar processor"
	desc = "Cleans compressed radar packets so Flight Ops consoles can read contacts."
	icon_state = "processor"
	circuit = /obj/item/circuitboard/machine/overmap_radar/processor
	radar_type = /obj/machinery/overmap_radar/processor

/obj/machinery/overmap_radar/processor/receive_radar_packet(datum/signal/overmap_radar/packet, obj/machinery/from_machine)
	if(!on || !packet)
		return
	packet.compression = 0
	relay_radar_packet(packet, /obj/machinery/computer/overmap_radar)
	relay_radar_packet(packet, /obj/machinery/overmap_radar/bus)

// --- Bus ---

/obj/machinery/overmap_radar/bus
	name = "deep-space radar bus"
	desc = "A junction for Flight Ops radar machines."
	icon_state = "bus"
	circuit = /obj/item/circuitboard/machine/overmap_radar/bus
	radar_type = /obj/machinery/overmap_radar/bus

/obj/machinery/overmap_radar/bus/receive_radar_packet(datum/signal/overmap_radar/packet, obj/machinery/from_machine)
	if(!on || !packet)
		return
	relay_radar_packet(packet, /obj/machinery/overmap_radar/processor)
	relay_radar_packet(packet, /obj/machinery/computer/overmap_radar)

// --- Dish ---

/obj/machinery/overmap_radar/dish
	name = "deep-space radar array"
	desc = "A long-range radome. Sweeps deep space from the station and emits packets onto a linked processor."
	icon = 'modular_nova/modules/overmap/icons/radar_beacon.dmi'
	icon_state = "radar_beacon"
	base_icon_state = "radar_beacon"
	/// 2x3 sprite; loc is the southwest tile. One machine frame builds the whole array.
	bound_width = 64
	bound_height = 96
	use_power = NO_POWER_USE
	idle_power_usage = 0
	active_power_usage = BASE_MACHINE_ACTIVE_CONSUMPTION * 2
	circuit = /obj/item/circuitboard/machine/overmap_radar/dish
	radar_type = /obj/machinery/overmap_radar/dish
	resistance_flags = FIRE_PROOF | UNACIDABLE
	id = "Radar Array"
	/// Hidden cable node that joins the station powernet.
	var/obj/machinery/power/overmap_radar_node/power_node
	var/sweeping = FALSE

/obj/machinery/overmap_radar/dish/Initialize(mapload)
	. = ..()
	power_node = new /obj/machinery/power/overmap_radar_node(loc)
	power_node.owner = src
	update_appearance()

/obj/machinery/overmap_radar/dish/Destroy()
	if(power_node)
		power_node.owner = null
		QDEL_NULL(power_node)
	return ..()

/obj/machinery/overmap_radar/dish/on_construction(mob/user)
	. = ..()
	power_node?.connect_to_network()
	update_radar_power()
	update_appearance()

/obj/machinery/overmap_radar/dish/on_set_panel_open(old_value)
	. = ..()
	update_radar_power()

/obj/machinery/overmap_radar/dish/update_radar_power()
	var/old_on = on
	if(toggled)
		on = !(machine_stat & (BROKEN | EMPED)) && !panel_open && !!get_grid_powernet()
	else
		on = FALSE
	if(old_on != on)
		update_appearance()

/obj/machinery/overmap_radar/dish/get_grid_powernet()
	if(forced_powernet)
		return forced_powernet
	return power_node?.powernet

/obj/machinery/overmap_radar/dish/examine(mob/user)
	. = ..()
	if(panel_open)
		. += span_warning("The hatch is open. The array will not sweep.")

/obj/machinery/overmap_radar/dish/update_icon_state()
	if(machine_stat & BROKEN)
		icon_state = "[base_icon_state]-broken"
	else
		icon_state = base_icon_state
	return

/obj/machinery/overmap_radar/dish/update_overlays()
	. = ..()
	if(machine_stat & BROKEN)
		return
	if(panel_open)
		. += "[base_icon_state]-box_cover-open"
	if(on)
		. += "[base_icon_state]-box_light-on"
	if(sweeping)
		. += "[base_icon_state]-lights-active"

/obj/machinery/overmap_radar/dish/proc/sweep(bearing, arc_width, obj/machinery/computer/overmap_radar/requester)
	if(!on)
		return null
	var/obj/structure/overmap/origin = SSovermap.main
	if(!origin)
		return null
	var/width = clamp(arc_width, OVERMAP_RADAR_MIN_ARC, 360)
	var/range = overmap_radar_range_for_arc(width)
	if(power_node?.powernet)
		power_node.add_load(active_power_usage)
	sweeping = TRUE
	update_appearance()
	addtimer(CALLBACK(src, PROC_REF(finish_sweep_visual)), 1.5 SECONDS)

	var/datum/signal/overmap_radar/packet = new(src, origin)
	packet.bearing = SIMPLIFY_DEGREES(bearing)
	packet.arc_width = width
	packet.range = range
	packet.compression = OVERMAP_RADAR_DEFAULT_COMPRESSION
	packet.dest_console = requester
	for(var/obj/structure/overmap/contact as anything in origin.gather_radar_contacts(range, packet.bearing, width))
		packet.contacts += list(overmap_radar_contact_data(origin, contact))
	emit_packet(packet)
	return packet

/obj/machinery/overmap_radar/dish/proc/finish_sweep_visual()
	sweeping = FALSE
	update_appearance()

/obj/machinery/overmap_radar/dish/proc/emit_packet(datum/signal/overmap_radar/packet)
	if(!packet)
		return
	var/sent = relay_radar_packet(packet, /obj/machinery/overmap_radar/processor)
	sent += relay_radar_packet(packet, /obj/machinery/overmap_radar/bus)
	if(!sent)
		relay_radar_packet(packet, /obj/machinery/computer/overmap_radar)

/obj/machinery/power/overmap_radar_node
	name = "radar array power node"
	desc = "Internal cable tap for the radar array. You should not see this."
	icon = 'icons/obj/machines/engine/other.dmi'
	icon_state = null
	density = FALSE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	invisibility = INVISIBILITY_ABSTRACT
	use_power = NO_POWER_USE
	var/obj/machinery/overmap_radar/dish/owner

/obj/machinery/power/overmap_radar_node/Initialize(mapload)
	. = ..()
	return INITIALIZE_HINT_LATELOAD

/obj/machinery/power/overmap_radar_node/LateInitialize()
	. = ..()
	connect_to_network()

/obj/machinery/power/overmap_radar_node/should_have_node()
	return TRUE

/obj/machinery/power/overmap_radar_node/Destroy()
	owner = null
	return ..()
