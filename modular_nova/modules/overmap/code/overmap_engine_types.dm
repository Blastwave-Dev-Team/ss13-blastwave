// MODULE ID: OVERMAP
// Concrete overmap engine flavors.

/// Void engine - admin-spawn / prototype-friendly. Has an internal infinite
/// "void core" that never depletes and doesn't require power.
/obj/machinery/power/shuttle_engine/overmap/void
	name = "void thruster"
	desc = "An exotic thruster that punches into voidspace for unlimited propulsion."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap/void
	thrust = 50

/// Void engines don't need propellant or power — always active.
/obj/machinery/power/shuttle_engine/overmap/void/update_engine()
	thruster_active = TRUE
	if(machine_stat & BROKEN)
		thruster_active = FALSE
		return FALSE
	if(panel_open)
		thruster_active = FALSE
		return FALSE
	if(!enabled)
		thruster_active = FALSE
		return FALSE
	return TRUE

/obj/machinery/power/shuttle_engine/overmap/void/burn_engine(percentage = 100, skip_engine_update = FALSE, dt = 1)
	if(!enabled)
		return 0
	if(!skip_engine_update && !update_engine())
		return 0
	if(percentage <= 0 || !ship_wants_thrust())
		return 0
	return thrust * (percentage / 100)

/obj/machinery/power/shuttle_engine/overmap/void/return_fuel()
	return 1

/obj/machinery/power/shuttle_engine/overmap/void/return_fuel_cap()
	return 1

/obj/machinery/power/shuttle_engine/overmap/void/get_current_thrust()
	return thrust

/// Hall-Nuclear-Thermal overmap engine — grid-powered Hall acceleration fed by a linked fuel injector.
/// When no propellant is available it falls back to a hall-only mode: electromagnetic ion
/// acceleration alone, producing greatly reduced thrust at a higher power cost. This makes the
/// HNT the safe choice — it can always limp home on grid power even with a dead fuel supply.
/obj/machinery/power/shuttle_engine/overmap/standard
	name = "Hall-Nuclear-Thermal engine"
	desc = "An astrogation thruster that accelerates propellant from a linked fuel injector via Hall-effect coupling and nuclear-thermal expulsion. Draws power from the ship grid. Falls back to a weak hall-only mode on grid power alone when propellant runs dry."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap/standard
	thrust = 30
	max_power_draw = 40000
	/// Fraction of rated thrust produced in hall-only mode (no propellant, grid power only).
	var/hall_only_efficiency = 0.15
	/// Power draw multiplier while running in hall-only mode.
	var/hall_only_power_mult = 2.0

/// Hall-only ISP proxy: when the injector feed is dry we still return the hall
/// efficiency so the engine reports a non-zero output and stays active on grid
/// power alone. Chamber-only (feed not yet pressurized) uses chamber ISP estimate.
/obj/machinery/power/shuttle_engine/overmap/standard/get_isp_efficiency()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector?.has_feed_propellant())
		return fuel_injector_estimate_isp(injector) || injector.base_isp
	if(injector?.has_propellant())
		return injector.base_isp
	return hall_only_efficiency

/// Active whenever it has propellant OR any grid power to run hall-only mode.
/obj/machinery/power/shuttle_engine/overmap/standard/update_engine()
	thruster_active = TRUE
	if(machine_stat & BROKEN)
		thruster_active = FALSE
		return FALSE
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
	if(get_power_fraction() > 0)
		return TRUE
	thruster_active = FALSE
	return FALSE

/obj/machinery/power/shuttle_engine/overmap/standard/burn_engine(percentage = 100, skip_engine_update = FALSE, dt = 1)
	if(!enabled)
		return 0
	if(!skip_engine_update && !update_engine())
		return 0
	if(percentage <= 0 || !ship_wants_thrust())
		return 0
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector?.has_feed_propellant())
		return ..(percentage, skip_engine_update = TRUE, dt = dt)
	// Chamber still has gas but L2 has not pressurized yet — wait, do not hall-only.
	if(injector?.has_propellant())
		return 0
	// Hall-only fallback: reduced thrust, no propellant consumed, higher power cost.
	var/power_fraction = get_power_fraction()
	if(power_fraction <= 0)
		return 0
	consume_grid_power(power_fraction, hall_only_power_mult * (percentage / 100), dt)
	burning = TRUE
	return thrust * power_fraction * hall_only_efficiency * (percentage / 100)

/// In hall-only mode the engine's "fuel" is grid power, so report power availability
/// as fuel fullness. This keeps `undock()` and throttle-sustain working with a dry injector.
/obj/machinery/power/shuttle_engine/overmap/standard/return_fuel()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector)
		return injector.return_fuel()
	return get_power_fraction() * 100

/obj/machinery/power/shuttle_engine/overmap/standard/return_fuel_cap()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector)
		return injector.return_fuel_cap()
	return 100

/// Reported capability reflects hall-only reduction when running without propellant.
/obj/machinery/power/shuttle_engine/overmap/standard/get_rated_thrust()
	var/obj/machinery/overmap/fuel_injector/injector = get_linked_injector()
	if(injector?.has_propellant())
		return thrust
	return thrust * hall_only_efficiency

/obj/machinery/power/shuttle_engine/overmap/standard/no_fuel_examine()
	return span_warning("Hall-only mode: [round(hall_only_efficiency * 100)]% thrust at elevated power draw. Restore the fuel injector supply for full performance.")
