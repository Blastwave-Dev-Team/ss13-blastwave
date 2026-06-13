// MODULE ID: OVERMAP
// Autolathe design and cargo pack for the fuel injector board.

/datum/design/board/overmap_fuel_injector
	name = "Overmap Fuel Injector Board"
	desc = "The circuit board for an overmap hybrid propellant processor."
	id = "overmap_fuel_injector"
	build_path = /obj/item/circuitboard/machine/overmap/fuel_injector
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/supply_pack/engineering/overmap_fuel_injector
	name = "Overmap Fuel Injector Board Crate"
	desc = "Contains a circuit board for building an overmap fuel injector."
	cost = CARGO_CRATE_VALUE * 2
	contains = list(/obj/item/circuitboard/machine/overmap/fuel_injector)
	crate_name = "overmap fuel injector board crate"
	crate_type = /obj/structure/closet/crate/engineering
