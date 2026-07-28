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
	name = "Astrogation Landing Console Board"
	desc = "The circuit board for an astrogation landing console."
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
	name = "Landing Zone Controller Board (Nanotrasen)"
	desc = "The circuit board for a Nanotrasen-locked landing zone controller."
	id = "overmap_landing_controller"
	build_path = /obj/item/circuitboard/computer/landing_controller/nanotrasen
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_COMPUTER_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/design/board/overmap_landing_controller_programmable
	name = "Landing Zone Controller Board (Programmable)"
	desc = "The circuit board for an ID-programmable landing zone controller (syndicate-aligned docking)."
	id = "overmap_landing_controller_programmable"
	build_path = /obj/item/circuitboard/computer/landing_controller/programmable
	build_type = AWAY_IMPRINTER
	category = list(
		RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_COMPUTER_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/obj/item/disk/design_disk/techweb_unlock/overmap_landing_programmable
	name = "Programmable Landing Authority Research Disk"
	desc = "Contains research data for ID-programmable landing zone controllers. Upload to an R&D Console to unlock Programmable Landing Authority."
	node_id = TECHWEB_NODE_OVERMAP_LANDING_PROGRAMMABLE

/datum/supply_pack/engineering/overmap_landing_programmable_disk
	name = "Programmable Landing Authority Research Disk"
	desc = "A research disk that unlocks away-imprinter designs for ID-programmable landing zone controllers (syndicate-aligned docking)."
	cost = CARGO_CRATE_VALUE * 3
	contains = list(/obj/item/disk/design_disk/techweb_unlock/overmap_landing_programmable = 1)
	crate_name = "programmable landing authority disk crate"
	crate_type = /obj/structure/closet/crate/engineering
	order_flags = ORDER_CONTRABAND

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

/datum/design/board/shipyard_fabricator
	name = "Shipyard Fabricator Assembly Board"
	desc = "The circuit board for one half of a paired shipyard fabricator."
	id = "shipyard_fabricator"
	build_path = /obj/item/circuitboard/machine/shipyard_fabricator
	build_type = IMPRINTER
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/design/ship_blueprint_disk
	name = "Personal Travel Shuttle Blueprint Disk"
	desc = "A production manifest for fabricating a personal travel shuttle."
	id = "ship_blueprint_disk"
	build_path = /obj/item/ship_blueprint_disk/personal_shuttle
	build_type = PROTOLATHE
	materials = list(
		/datum/material/iron = HALF_SHEET_MATERIAL_AMOUNT,
		/datum/material/glass = HALF_SHEET_MATERIAL_AMOUNT,
	)
	category = list(RND_CATEGORY_TOOLS + RND_SUBCATEGORY_TOOLS_ENGINEERING)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_CARGO

/datum/supply_pack/engineering/shipyard_fabricator
	name = "Shipyard Fabricator Starter Kit"
	desc = "Two fabricator assembly boards, a basic ship blueprint disk, and a rapid part exchange device."
	cost = CARGO_CRATE_VALUE * 8
	contains = list(
		/obj/item/circuitboard/machine/shipyard_fabricator = 2,
		/obj/item/ship_blueprint_disk/personal_shuttle,
		/obj/item/storage/part_replacer,
	)
	crate_name = "shipyard fabricator kit crate"
	crate_type = /obj/structure/closet/crate/engineering

/datum/supply_pack/engineering/overmap_fuel_injector
	name = "Shuttle Construction Kit"
	desc = "Contains circuit boards for building a basic shuttle: helm and landing consoles, fuel injectors, Hall-Nuclear-Thermal engines, and a landing zone controller with corner beacons."
	cost = CARGO_CRATE_VALUE * 8
	contains = list(
		/obj/item/circuitboard/computer/shuttle/helm,
		/obj/item/circuitboard/computer/shuttle/overmap_nav,
		/obj/item/circuitboard/machine/overmap/fuel_injector = 2,
		/obj/item/circuitboard/machine/engine/overmap/standard = 2,
		/obj/item/circuitboard/computer/landing_controller, // unlocked / open dock
		/obj/item/circuitboard/machine/landing_corner = 4,
	)
	crate_name = "shuttle construction kit crate"
	crate_type = /obj/structure/closet/crate/engineering
