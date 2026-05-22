// MODULE ID: OVERMAP
// Concrete overmap engine flavors. The prototype only really needs the
// `void` (free-fuel) variant for playability; the `liquid/oil` variant is
// included as the simplest "real fuel" example so the helm UI's fuel bar
// has something interesting to display when admins are testing.

/// Void engine - admin-spawn / prototype-friendly. Infinite "fuel".
/obj/machinery/power/shuttle_engine/overmap/void
	name = "void thruster"
	desc = "An exotic thruster that punches into voidspace for unlimited propulsion. Adminspawn-grade."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap/void
	thrust = 10

/obj/machinery/power/shuttle_engine/overmap/void/return_fuel()
	return 1
/obj/machinery/power/shuttle_engine/overmap/void/return_fuel_cap()
	return 1

/// Liquid-fueled engine. Burns oil from its internal reagent store. Refill
/// with a hand pump or jerrycan. Stays simple on purpose - WS' atmospherics
/// gas-paired heater design is deferred past prototype.
/obj/machinery/power/shuttle_engine/overmap/liquid
	name = "liquid fuel thruster"
	desc = "A thruster that burns reagents stored in the engine for fuel."
	icon_state = "propulsion"
	circuit = /obj/item/circuitboard/machine/engine/overmap/liquid
	thrust = 20
	/// How much liquid fuel can be loaded.
	var/max_reagents = 2000
	/// Reagent volume consumed per full burn, keyed by reagent path.
	var/list/datum/reagent/fuel_reagents = list(/datum/reagent/fuel/oil = 200)
	/// Cached sum of `fuel_reagents` values, for `return_fuel`'s denominator.
	var/reagent_amount_holder = 0

/obj/machinery/power/shuttle_engine/overmap/liquid/Initialize(mapload)
	. = ..()
	create_reagents(max_reagents, OPENCONTAINER)
	AddComponent(/datum/component/plumbing/simple_demand)
	for(var/reagent in fuel_reagents)
		reagent_amount_holder += fuel_reagents[reagent]

/obj/machinery/power/shuttle_engine/overmap/liquid/burn_engine(percentage = 100)
	. = ..()
	if(!.)
		return 0
	var/true_percentage = 1
	for(var/reagent in fuel_reagents)
		var/amount_needed = fuel_reagents[reagent] * (percentage / 100)
		var/burned = reagents.remove_reagent(reagent, amount_needed)
		true_percentage *= (amount_needed > 0 ? burned / amount_needed : 0)
	return thrust * true_percentage

/obj/machinery/power/shuttle_engine/overmap/liquid/return_fuel()
	var/true_percentage = 1
	for(var/reagent in fuel_reagents)
		true_percentage = min(reagents.get_reagent_amount(reagent) / fuel_reagents[reagent], true_percentage)
	return reagent_amount_holder * true_percentage

/obj/machinery/power/shuttle_engine/overmap/liquid/return_fuel_cap()
	return reagents.maximum_volume
