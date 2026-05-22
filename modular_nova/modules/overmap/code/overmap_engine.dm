// MODULE ID: OVERMAP
// Overmap-aware engine base. Subclasses Nova's `/obj/machinery/power/shuttle_engine`
// so we inherit the modern weld/wrench/connect-to-shuttle plumbing, while
// adding the WS-style "enabled toggle, thrust value, burn_engine -> consume
// fuel and return thrust" semantics that the helm and movement code rely on.
//
// The default implementation here is a FREE-FUEL engine: enabling it gives
// the shuttle thrust, no resource cost. Subtypes (in overmap_engine_types.dm)
// add real fuel costs.

/obj/machinery/power/shuttle_engine/overmap
	name = "overmap thruster"
	desc = "An overmap-rated thruster. Toggleable from a linked helm console."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap
	/// Toggleable from helm. Disabled engines neither consume fuel nor provide thrust.
	var/enabled = TRUE
	/// Raw thrust contribution per full burn. Overmap movement uses this and
	/// the bound shuttle's mass to derive acceleration in tiles-per-tick.
	var/thrust = 25
	/// Active state used by `update_icon_state`. Set by `update_engine()`.
	var/thruster_active = FALSE

/obj/machinery/power/shuttle_engine/overmap/Initialize(mapload)
	. = ..()
	update_engine()
	update_icon_state()

/// Consume the fuel cost of one burn (full or fractional) and return the
/// resulting thrust contribution. Default implementation is free-fuel; the
/// fueled subtypes scale return value by how much of the requested fuel
/// they could actually afford.
/obj/machinery/power/shuttle_engine/overmap/proc/burn_engine(percentage = 100)
	if(!enabled)
		return 0
	if(!update_engine())
		return 0
	return thrust * (percentage / 100)

/// Returns current fuel level, in whatever unit the engine wants to display.
/// Default 100 (matches `return_fuel_cap`) for the free-fuel base engine.
/obj/machinery/power/shuttle_engine/overmap/proc/return_fuel()
	return 100

/// Returns the fuel capacity. Helm's UI uses this to size the fuel bar.
/obj/machinery/power/shuttle_engine/overmap/proc/return_fuel_cap()
	return 100

/// Sets `thruster_active` based on whether the engine is currently in a
/// burnable state. Subtypes override to add fuel/heater checks. Returns
/// FALSE if the engine cannot fire right now.
/obj/machinery/power/shuttle_engine/overmap/proc/update_engine()
	thruster_active = TRUE
	if(panel_open)
		thruster_active = FALSE
		return FALSE
	if(!enabled)
		thruster_active = FALSE
		return FALSE
	return TRUE

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
	. += span_notice("Fuel: [return_fuel()]/[return_fuel_cap()].")
