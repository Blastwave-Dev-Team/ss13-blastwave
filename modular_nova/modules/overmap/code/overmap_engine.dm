// MODULE ID: OVERMAP
// Overmap-aware engine base. Subclasses Nova's `/obj/machinery/power/shuttle_engine`
// so we inherit the modern weld/wrench/connect-to-shuttle plumbing, while
// adding the WS-style "enabled toggle, thrust value, burn_engine -> consume
// fuel and return thrust" semantics that the helm and movement code rely on.
//
// Engines draw power from the ship's electrical grid and consume reaction mass
// from a linked fuel injector (primary) or inserted fuel core (fallback).

/obj/machinery/power/shuttle_engine/overmap
	name = "overmap thruster"
	desc = "An overmap-rated thruster. Toggleable from a linked helm console."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap
	/// Toggleable from helm. Disabled engines neither consume fuel nor provide thrust.
	var/enabled = TRUE
	/// Base thrust output at full power with a 1.0x efficiency core.
	var/thrust = 25
	/// Maximum power draw from the grid in watts.
	var/max_power_draw = 50000
	/// Active state used by `update_engine()`. Set by `update_engine()`.
	var/thruster_active = FALSE
	/// Whether this engine currently has a burn in progress (for fuel consumption).
	var/burning = FALSE
	/// Inserted fuel core item. NULL if no core loaded.
	var/obj/item/fuel_core/fuel_core
	/// Adjacent fuel injector weakref.
	var/datum/weakref/linked_injector
	/// Layer-2 propellant feed port toward the fuel manifold.
	var/datum/gas_machine_connector/feed_connector
	/// TRUE when linked to the injector via L2 pipenet rather than adjacency.
	var/link_via_pipe = FALSE

/obj/machinery/power/shuttle_engine/overmap/Initialize(mapload)
	. = ..()
	feed_connector = new(loc, src, dir, CELL_VOLUME * 0.5, OVERMAP_HNT_FEED_LAYER)
	update_engine()
	update_icon_state()

/obj/machinery/power/shuttle_engine/overmap/Destroy()
	QDEL_NULL(fuel_core)
	QDEL_NULL(feed_connector)
	linked_injector = null
	return ..()

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
	if(injector?.has_propellant())
		return injector.base_isp
	if(fuel_core && !fuel_core.is_depleted())
		return fuel_core.efficiency
	return 0

/obj/machinery/power/shuttle_engine/overmap/proc/get_current_thrust()
	var/isp = get_isp_efficiency()
	if(!isp)
		return 0
	var/power_fraction = get_power_fraction()
	return thrust * power_fraction * isp

/obj/machinery/power/shuttle_engine/overmap/proc/burn_engine(percentage = 100, skip_engine_update = FALSE)
	if(!enabled)
		return 0
	if(!skip_engine_update && !update_engine())
		return 0
	var/power_fraction = get_power_fraction()
	var/isp = get_isp_efficiency()
	if(!isp)
		return 0
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector?.has_propellant())
		var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(src)
		var/obj/structure/overmap/ship/simulated/ship = port?.current_ship
		if(ship?.processing_fuel_batch)
			return thrust * power_fraction * isp * (percentage / 100)
		var/requested_moles = overmap_engine_propellant_share_moles(thrust, power_fraction, percentage)
		var/list/burn_result = injector.consume_for_burn(requested_moles, power_fraction)
		var/burn_fraction = burn_result[1]
		var/effective_isp = burn_result[2]
		if(burn_fraction <= 0)
			return 0
		var/effective_thrust = thrust * power_fraction * effective_isp * (percentage / 100) * burn_fraction
		use_energy(max_power_draw * power_fraction * (percentage / 100))
		burning = TRUE
		return effective_thrust
	var/effective_thrust = thrust * power_fraction * isp * (percentage / 100)
	if(fuel_core && !fuel_core.is_depleted())
		var/consumption = effective_thrust / max(fuel_core.efficiency * OVERMAP_G0, 0.01) * 0.01
		fuel_core.reaction_mass = max(0, fuel_core.reaction_mass - consumption)
		if(fuel_core.is_depleted())
			core_depleted()
		use_energy(max_power_draw * power_fraction * (percentage / 100))
		burning = TRUE
		return effective_thrust
	return 0

/obj/machinery/power/shuttle_engine/overmap/proc/core_depleted()
	visible_message(span_warning("[src] sputters as its fuel core is depleted!"))
	thruster_active = FALSE
	burning = FALSE
	update_icon_state()

/obj/machinery/power/shuttle_engine/overmap/proc/return_fuel()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector)
		return injector.return_fuel()
	if(fuel_core)
		return fuel_core.reaction_mass
	return 0

/obj/machinery/power/shuttle_engine/overmap/proc/return_fuel_cap()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector)
		return injector.return_fuel_cap()
	if(fuel_core)
		return fuel_core.reaction_mass_max
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
	if(injector?.has_propellant())
		return TRUE
	if(fuel_core && !fuel_core.is_depleted())
		return TRUE
	thruster_active = FALSE
	return FALSE

/obj/machinery/power/shuttle_engine/overmap/attackby(obj/item/attacking_item, mob/user, params)
	if(istype(attacking_item, /obj/item/fuel_core))
		if(fuel_core)
			to_chat(user, span_warning("There is already a fuel core installed. Remove it first."))
			return
		if(!user.transferItemToLoc(attacking_item, src))
			return
		fuel_core = attacking_item
		to_chat(user, span_notice("You insert [attacking_item] into [src]."))
		update_engine()
		update_icon_state()
		return
	return ..()

/obj/machinery/power/shuttle_engine/overmap/crowbar_act(mob/living/user, obj/item/tool)
	if(fuel_core)
		to_chat(user, span_notice("You pry [fuel_core] out of [src]."))
		fuel_core.forceMove(get_turf(src))
		fuel_core = null
		update_engine()
		update_icon_state()
		return ITEM_INTERACT_SUCCESS
	return ..()

/obj/machinery/power/shuttle_engine/overmap/multitool_act(mob/living/user, obj/item/tool)
	. = ..()
	enabled = !enabled
	balloon_alert(user, "engine [enabled ? "enabled" : "disabled"]")
	update_engine()
	update_icon_state()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/shuttle_engine/overmap/examine(mob/user)
	. = ..()
	. += span_notice("It is currently [enabled ? "enabled" : "disabled"]. Use a multitool to toggle.")
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector)
		. += span_notice("Linked to [injector][link_via_pipe ? " via propellant manifold" : " by adjacency"].")
	if(fuel_core)
		. += span_notice("Fuel core: [fuel_core.core_type] ([round(fuel_core.reaction_mass / fuel_core.reaction_mass_max * 100)]% remaining).")
	else if(!injector)
		. += span_warning("No fuel source. Link a fuel injector or insert a fuel core.")
