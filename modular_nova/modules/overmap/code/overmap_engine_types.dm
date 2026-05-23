// MODULE ID: OVERMAP
// Concrete overmap engine flavors.

/// Void engine - admin-spawn / prototype-friendly. Has an internal infinite
/// "void core" that never depletes and doesn't require power.
/obj/machinery/power/shuttle_engine/overmap/void
	name = "void thruster"
	desc = "An exotic thruster that punches into voidspace for unlimited propulsion. Adminspawn-grade."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap/void
	thrust = 10

/// Void engines don't need fuel cores or power — always active.
/obj/machinery/power/shuttle_engine/overmap/void/update_engine()
	thruster_active = TRUE
	if(panel_open)
		thruster_active = FALSE
		return FALSE
	if(!enabled)
		thruster_active = FALSE
		return FALSE
	return TRUE

/obj/machinery/power/shuttle_engine/overmap/void/burn_engine(percentage = 100)
	if(!enabled)
		return 0
	if(!update_engine())
		return 0
	return thrust * (percentage / 100)

/obj/machinery/power/shuttle_engine/overmap/void/return_fuel()
	return 1

/obj/machinery/power/shuttle_engine/overmap/void/return_fuel_cap()
	return 1

/obj/machinery/power/shuttle_engine/overmap/void/get_current_thrust()
	return thrust

/// Standard overmap engine that requires a fuel core and ship power.
/obj/machinery/power/shuttle_engine/overmap/standard
	name = "fusion thruster"
	desc = "A standard overmap thruster. Requires a fuel core and draws power from the ship's grid."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap/standard
	thrust = 30
	max_power_draw = 80000
