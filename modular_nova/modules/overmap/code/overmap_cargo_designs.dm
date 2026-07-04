// MODULE ID: OVERMAP
// Autolathe designs and cargo pack for overmap shuttle construction.

/datum/design/board/overmap_fuel_injector
	name = "Astrogation Fuel Injector Board"
	desc = "The circuit board for a hybrid propellant processor."
	id = "overmap_fuel_injector"
	build_path = /obj/item/circuitboard/machine/overmap/fuel_injector
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/design/board/overmap_helm_console
	name = "Astrogation Helm Board"
	desc = "The circuit board for an astrogation helm console."
	id = "overmap_helm_console"
	build_path = /obj/item/circuitboard/computer/shuttle/helm
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_COMPUTER_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/design/board/overmap_nav_computer
	name = "Astrogation Navigation Console Board"
	desc = "The circuit board for an astrogation navigation console."
	id = "overmap_nav_computer"
	build_path = /obj/item/circuitboard/computer/shuttle/overmap_nav
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_COMPUTER_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/design/board/overmap_fusion_thruster
	name = "Hall-Nuclear-Thermal Engine Board"
	desc = "The circuit board for an astrogation Hall-Nuclear-Thermal engine."
	id = "overmap_fusion_thruster"
	build_path = /obj/item/circuitboard/machine/engine/overmap/standard
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/design/board/overmap_landing_controller
	name = "Landing Zone Controller Board"
	desc = "The circuit board for a landing zone controller console."
	id = "overmap_landing_controller"
	build_path = /obj/item/circuitboard/computer/landing_controller
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_COMPUTER_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/design/board/overmap_landing_corner
	name = "Landing Zone Corner Beacon Board"
	desc = "The circuit board for a landing zone corner beacon."
	id = "overmap_landing_corner"
	build_path = /obj/item/circuitboard/machine/landing_corner
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/supply_pack/engineering/overmap_fuel_injector
	name = "Shuttle Construction Kit"
	desc = "Contains circuit boards for building a basic shuttle: helm and navigation consoles, fuel injectors, Hall-Nuclear-Thermal engines, and a landing zone controller with corner beacons."
	cost = CARGO_CRATE_VALUE * 8
	contains = list(
		/obj/item/circuitboard/computer/shuttle/helm,
		/obj/item/circuitboard/computer/shuttle/overmap_nav,
		/obj/item/circuitboard/machine/overmap/fuel_injector = 2,
		/obj/item/circuitboard/machine/engine/overmap/standard = 2,
		/obj/item/circuitboard/computer/landing_controller,
		/obj/item/circuitboard/machine/landing_corner = 4,
	)
	crate_name = "shuttle construction kit crate"
	crate_type = /obj/structure/closet/crate/engineering
