// MODULE ID: OVERMAP
// Overmap-aware engine base. Subclasses Nova's `/obj/machinery/power/shuttle_engine`
// so we inherit the modern weld/wrench/connect-to-shuttle plumbing, while
// adding the WS-style "enabled toggle, thrust value, burn_engine -> consume
// fuel and return thrust" semantics that the helm and movement code rely on.
//
// Engines draw power from the ship's electrical grid and consume reaction mass
// from an inserted fuel core. Thrust = base_thrust * power_fraction * core_efficiency.

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
	/// Active state used by `update_icon_state`. Set by `update_engine()`.
	var/thruster_active = FALSE
	/// Whether this engine currently has a burn in progress (for fuel consumption).
	var/burning = FALSE
	/// Inserted fuel core item. NULL if no core loaded.
	var/obj/item/fuel_core/fuel_core

/obj/machinery/power/shuttle_engine/overmap/Initialize(mapload)
	. = ..()
	update_engine()
	update_icon_state()

/obj/machinery/power/shuttle_engine/overmap/Destroy()
	QDEL_NULL(fuel_core)
	return ..()

/// Get available power as a fraction of max_power_draw (0..1).
/obj/machinery/power/shuttle_engine/overmap/proc/get_power_fraction()
	if(!powernet)
		return 0
	var/available = clamp(powernet.avail - powernet.load, 0, max_power_draw)
	return available / max(max_power_draw, 1)

/// Compute current effective thrust based on power and core.
/obj/machinery/power/shuttle_engine/overmap/proc/get_current_thrust()
	if(!fuel_core || fuel_core.is_depleted())
		return 0
	var/power_fraction = get_power_fraction()
	return thrust * power_fraction * fuel_core.efficiency

/// Consume the fuel cost of one burn tick and return thrust contribution.
/obj/machinery/power/shuttle_engine/overmap/proc/burn_engine(percentage = 100)
	if(!enabled)
		return 0
	if(!update_engine())
		return 0
	if(!fuel_core || fuel_core.is_depleted())
		return 0
	var/power_fraction = get_power_fraction()
	var/effective_thrust = thrust * power_fraction * fuel_core.efficiency * (percentage / 100)
	// Consume reaction mass: consumption = thrust / (ISP * g0)
	var/consumption = effective_thrust / max(fuel_core.efficiency * OVERMAP_G0, 0.01) * 0.01
	fuel_core.reaction_mass = max(0, fuel_core.reaction_mass - consumption)
	if(fuel_core.is_depleted())
		core_depleted()
	// Draw power from grid
	use_energy(max_power_draw * power_fraction * (percentage / 100))
	burning = TRUE
	return effective_thrust

/// Called when the fuel core runs out mid-burn.
/obj/machinery/power/shuttle_engine/overmap/proc/core_depleted()
	visible_message(span_warning("[src] sputters as its fuel core is depleted!"))
	thruster_active = FALSE
	burning = FALSE
	update_icon_state()

/// Returns current fuel level (reaction mass remaining).
/obj/machinery/power/shuttle_engine/overmap/proc/return_fuel()
	if(!fuel_core)
		return 0
	return fuel_core.reaction_mass

/// Returns the fuel capacity.
/obj/machinery/power/shuttle_engine/overmap/proc/return_fuel_cap()
	if(!fuel_core)
		return 0
	return fuel_core.reaction_mass_max

/// Sets `thruster_active` based on whether the engine can fire.
/obj/machinery/power/shuttle_engine/overmap/proc/update_engine()
	thruster_active = TRUE
	if(panel_open)
		thruster_active = FALSE
		return FALSE
	if(!enabled)
		thruster_active = FALSE
		return FALSE
	if(!fuel_core || fuel_core.is_depleted())
		thruster_active = FALSE
		return FALSE
	return TRUE

/// Handle inserting/removing fuel cores via attackby.
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

/// Remove fuel core on crowbar.
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
	if(fuel_core)
		. += span_notice("Fuel core: [fuel_core.core_type] ([round(fuel_core.reaction_mass / fuel_core.reaction_mass_max * 100)]% remaining).")
	else
		. += span_warning("No fuel core installed. Insert one to enable thrust.")
