// MODULE ID: OVERMAP
// Decorative engine heater placeholder. WS paired its plasma-fueled
// thrusters with a gas-storage atmospherics heater; for the prototype we
// only need a placeable fixture so M7's `area_spawn` entries feel correct
// next to the engines they sit beside. Real gas-storage / fuel routing is
// deferred past prototype, so this is a plain `/obj/machinery` rather than
// an `/obj/machinery/atmospherics/...` to skirt all the atmos plumbing.

/obj/machinery/shuttle_heater
	name = "engine heater"
	desc = "Directs energy into compressed particles in order to power an attached thruster. Currently a decorative placeholder."
	icon = 'icons/obj/machines/atmospherics/unary_devices.dmi'
	icon_state = "smes_off"
	density = TRUE
	max_integrity = 400
	layer = OBJ_LAYER
	use_power = NO_POWER_USE
	circuit = /obj/item/circuitboard/machine/shuttle_heater

/obj/machinery/shuttle_heater/examine(mob/user)
	. = ..()
	. += span_notice("This heater is currently decorative. Real fuel routing lands post-prototype.")
