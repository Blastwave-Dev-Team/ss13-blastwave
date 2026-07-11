// MODULE ID: OVERMAP
// Overmap-aware engine base. Subclasses Nova's `/obj/machinery/power/shuttle_engine`
// so we inherit the modern weld/wrench/connect-to-shuttle plumbing, while
// adding the WS-style "enabled toggle, thrust value, burn_engine -> consume
// fuel and return thrust" semantics that the helm and movement code rely on.
//
// Engines draw power from the ship's electrical grid and consume reaction mass
// from a linked fuel injector. The HNT (`/standard`) subtype adds a hall-only
// fallback that produces reduced thrust from grid power alone when no propellant
// is available.

/// A machine connector whose hidden L2 pipe port faces opposite the connected
/// machine's facing. Thrusters point `dir` toward their exhaust, so their fuel
/// intake (and the propellant manifold) sits on the back side. The stock
/// connector always faces `connected_machine.dir`, which pointed the port at the
/// exhaust tile and prevented pipes laid behind the engine from ever connecting.
/datum/gas_machine_connector/reversed

/datum/gas_machine_connector/reversed/New(location, obj/machinery/connecting_machine, direction, gas_volume, piping_layer = PIPING_LAYER_DEFAULT)
	. = ..()
	if(QDELETED(src) || isnull(gas_connector))
		return
	// Rebuild the connection facing the reversed direction. Reusing the stock
	// disconnect/reconnect pair keeps node bookkeeping symmetric.
	disconnect_connector()
	reconnect_connector()

/datum/gas_machine_connector/reversed/reconnect_connector()
	gas_connector.dir = turn(connected_machine.dir, 180)
	gas_connector.piping_layer = piping_layer
	gas_connector.set_init_directions()
	gas_connector.atmos_init()
	var/obj/machinery/atmospherics/node = gas_connector.nodes[1]
	if(node)
		node.atmos_init()
		// Immediately joining the neighbor's pipenet is only safe when the
		// neighbor is a pipe that has one. Against another bare connector, or
		// mid-shuttle-rotation, its pipeline can be null and add_member()
		// runtimes. The rebuild queued below links everything up regardless.
		if(istype(node, /obj/machinery/atmospherics/pipe))
			var/obj/machinery/atmospherics/pipe/pipe_node = node
			if(pipe_node.parent)
				pipe_node.add_member(gas_connector)
				gas_connector.update_parents()
	SSair.add_to_rebuild_queue(gas_connector)

/obj/machinery/power/shuttle_engine/overmap
	name = "astrogation thruster"
	desc = "An astrogation-rated thruster. Toggleable from a linked helm console."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap
	/// Toggleable from helm. Disabled engines neither consume fuel nor provide thrust.
	var/enabled = TRUE
	/// Base thrust output at full power with a 1.0x efficiency injector.
	var/thrust = 25
	/// Maximum power draw from the grid in watts.
	var/max_power_draw = 50000
	/// Active state used by `update_engine()`. Set by `update_engine()`.
	var/thruster_active = FALSE
	/// Whether this engine currently has a burn in progress (for fuel consumption).
	var/burning = FALSE
	/// Adjacent fuel injector weakref.
	var/datum/weakref/linked_injector
	/// Layer-2 propellant feed port toward the fuel manifold.
	var/datum/gas_machine_connector/feed_connector
	/// TRUE when linked to the injector via L2 pipenet rather than adjacency.
	var/link_via_pipe = FALSE

/obj/machinery/power/shuttle_engine/overmap/Initialize(mapload)
	. = ..()
	// Fuel enters from the intake side (behind the thrust direction), so the L2
	// feed port must face the reverse of the engine's facing.
	feed_connector = new /datum/gas_machine_connector/reversed(loc, src, dir, CELL_VOLUME * 0.5, OVERMAP_HNT_FEED_LAYER)
	// The stock connector only reorients on COMSIG_MACHINERY_DEFAULT_ROTATE_WRENCH,
	// but engines rotate through the simple_rotation element (bare setDir), so we
	// track direction changes ourselves. POST variant: DIR_CHANGE fires before
	// `dir` is written, which would make the reconnect read the stale facing.
	RegisterSignal(src, COMSIG_ATOM_POST_DIR_CHANGE, PROC_REF(on_dir_change))
	update_engine()
	update_appearance()

/obj/machinery/power/shuttle_engine/overmap/Destroy()
	UnregisterSignal(src, COMSIG_ATOM_POST_DIR_CHANGE)
	QDEL_NULL(feed_connector)
	linked_injector = null
	return ..()

/// Reorient the L2 feed port when the engine is rotated in place.
/obj/machinery/power/shuttle_engine/overmap/proc/on_dir_change(datum/source, old_dir, new_dir)
	SIGNAL_HANDLER
	if(old_dir == new_dir || isnull(feed_connector))
		return
	feed_connector.disconnect_connector()
	feed_connector.reconnect_connector()
	scan_for_injector()

/obj/machinery/power/shuttle_engine/overmap/Moved(atom/old_loc, movement_dir, forced, list/old_locs, momentum_change)
	. = ..()
	scan_for_injector()

/obj/machinery/power/shuttle_engine/overmap/proc/scan_for_injector()
	linked_injector = null
	link_via_pipe = FALSE
	var/datum/pipeline/feed_pipe = overmap_hnt_feed_pipeline(feed_connector)
	if(feed_pipe)
		var/area/shuttle_area = get_area(src)
		if(shuttle_area)
			for(var/obj/machinery/overmap/fuel_injector/injector in shuttle_area)
				if(overmap_hnt_feed_pipeline(injector.feed_connector) == feed_pipe)
					set_linked_injector(injector, TRUE)
					return
	for(var/direction in GLOB.cardinals)
		for(var/obj/machinery/overmap/fuel_injector/found in get_step(get_turf(src), direction))
			if(found.dir != dir)
				continue
			set_linked_injector(found, FALSE)
			return

/obj/machinery/power/shuttle_engine/overmap/proc/set_linked_injector(obj/machinery/overmap/fuel_injector/injector, via_pipe = FALSE)
	if(!injector)
		return
	linked_injector = WEAKREF(injector)
	link_via_pipe = via_pipe
	if(!(WEAKREF(src) in injector.linked_engines))
		injector.linked_engines += WEAKREF(src)

/obj/machinery/power/shuttle_engine/overmap/proc/clear_injector_link(obj/machinery/overmap/fuel_injector/injector)
	if(linked_injector?.resolve() == injector)
		linked_injector = null

/obj/machinery/power/shuttle_engine/overmap/proc/get_linked_injector()
	return linked_injector?.resolve()

/obj/machinery/power/shuttle_engine/overmap/proc/get_power_fraction()
	if(!powernet)
		return 0
	var/available = clamp(powernet.avail - powernet.load, 0, max_power_draw)
	return available / max(max_power_draw, 1)

/obj/machinery/power/shuttle_engine/overmap/proc/get_isp_efficiency()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector?.has_feed_propellant())
		return fuel_injector_estimate_isp(injector) || injector.base_isp
	if(injector?.has_propellant())
		return injector.base_isp
	return 0

/obj/machinery/power/shuttle_engine/overmap/proc/get_current_thrust()
	var/isp = get_isp_efficiency()
	if(!isp)
		return 0
	var/power_fraction = get_power_fraction()
	return thrust * power_fraction * isp

/// Nominal thrust capability used for the ship's est_thrust readout. Subtypes with
/// a degraded mode (e.g. HNT hall-only) override this to report their reduced output.
/obj/machinery/power/shuttle_engine/overmap/proc/get_rated_thrust()
	return thrust

/obj/machinery/power/shuttle_engine/overmap/proc/burn_engine(percentage = 100, skip_engine_update = FALSE)
	if(!enabled)
		return 0
	if(!skip_engine_update && !update_engine())
		return 0
	var/power_fraction = get_power_fraction()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector?.has_feed_propellant())
		var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(src)
		var/obj/structure/overmap/ship/simulated/ship = port?.current_ship
		if(ship?.processing_fuel_batch)
			var/isp = get_isp_efficiency()
			return thrust * power_fraction * isp * (percentage / 100)
		var/requested_moles = overmap_engine_propellant_share_moles(thrust, power_fraction, percentage)
		var/list/burn_result = injector.consume_from_feed(requested_moles, power_fraction)
		var/burn_fraction = burn_result[1]
		var/effective_isp = burn_result[2]
		if(burn_fraction <= 0)
			return 0
		var/effective_thrust = thrust * power_fraction * effective_isp * (percentage / 100) * burn_fraction
		use_energy(max_power_draw * power_fraction * (percentage / 100))
		burning = TRUE
		return effective_thrust
	return 0

/obj/machinery/power/shuttle_engine/overmap/proc/return_fuel()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector)
		return injector.return_fuel()
	return 0

/obj/machinery/power/shuttle_engine/overmap/proc/return_fuel_cap()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector)
		return injector.return_fuel_cap()
	return 0

/obj/machinery/power/shuttle_engine/overmap/proc/return_chamber_pressure()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	return injector?.return_chamber_pressure()

/obj/machinery/power/shuttle_engine/overmap/proc/return_chamber_temperature()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	return injector?.return_chamber_temperature()

/obj/machinery/power/shuttle_engine/overmap/proc/update_engine()
	thruster_active = TRUE
	if(panel_open)
		thruster_active = FALSE
		return FALSE
	if(!enabled)
		thruster_active = FALSE
		return FALSE
	scan_for_injector()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector?.has_feed_propellant() || injector?.has_propellant())
		return TRUE
	thruster_active = FALSE
	return FALSE

/obj/machinery/power/shuttle_engine/overmap/screwdriver_act(mob/living/user, obj/item/tool)
	. = default_deconstruction_screwdriver(user, tool)
	if(. == ITEM_INTERACT_SUCCESS)
		update_engine()
		update_appearance()

/obj/machinery/power/shuttle_engine/overmap/crowbar_act(mob/living/user, obj/item/tool)
	if(panel_open && anchored)
		balloon_alert(user, "unweld and unwrench first!")
		return ITEM_INTERACT_BLOCKING
	if(panel_open)
		return default_deconstruction_crowbar(user, tool)
	return ..()

/obj/machinery/power/shuttle_engine/overmap/multitool_act(mob/living/user, obj/item/tool)
	. = ..()
	enabled = !enabled
	balloon_alert(user, "engine [enabled ? "enabled" : "disabled"]")
	update_engine()
	update_appearance()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/shuttle_engine/overmap/update_overlays()
	. = ..()
	if(!panel_open)
		return
	// Borrow the nuclear-device open-hatch cavity for the exposed maintenance internals look.
	. += mutable_appearance('icons/obj/machines/nuke.dmi', "panel-removed")

/obj/machinery/power/shuttle_engine/overmap/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	. = ..()
	if(isnull(held_item))
		return
	if(held_item.tool_behaviour == TOOL_SCREWDRIVER)
		context[SCREENTIP_CONTEXT_LMB] = "[panel_open ? "Close" : "Open"] maintenance panel"
		return CONTEXTUAL_SCREENTIP_SET
	if(held_item.tool_behaviour == TOOL_MULTITOOL)
		context[SCREENTIP_CONTEXT_LMB] = "[enabled ? "Disable" : "Enable"] engine"
		return CONTEXTUAL_SCREENTIP_SET
	if(held_item.tool_behaviour == TOOL_CROWBAR)
		if(panel_open && !anchored)
			context[SCREENTIP_CONTEXT_LMB] = "Deconstruct"
			return CONTEXTUAL_SCREENTIP_SET

/obj/machinery/power/shuttle_engine/overmap/examine(mob/user)
	. = ..()
	. += span_notice("It is currently [enabled ? "enabled" : "disabled"]. Use a multitool to toggle.")
	. += span_notice("A <i>screwdriver</i> [panel_open ? "closes" : "opens"] the maintenance panel[panel_open ? "; while open and detached from the floor, a <i>crowbar</i> deconstructs it" : " (cuts thrust while open)"].")
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector)
		. += span_notice("Linked to [injector][link_via_pipe ? " via propellant manifold" : " by adjacency"].")
	else
		. += no_fuel_examine()

/// Examine line shown when no fuel injector is linked. Overridden by engines
/// that have an alternate thrust source (e.g. the HNT's hall-only fallback).
/obj/machinery/power/shuttle_engine/overmap/proc/no_fuel_examine()
	return span_warning("No fuel source. Link a fuel injector to supply propellant.")
