// MODULE ID: OVERMAP
// Circuit boards and autolathe designs for radar machines and overmap keys.

/obj/item/circuitboard/computer/overmap_radar
	name = "Deep-Space Radar Console"
	desc = "A computer board. Displays contacts from a linked station radar array."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/overmap_radar

/obj/item/circuitboard/machine/overmap_radar
	name = "Deep-Space Radar Machine"
	abstract_type = /obj/item/circuitboard/machine/overmap_radar
	greyscale_colors = CIRCUIT_COLOR_ENGINEERING
	req_components = list(
		/datum/stock_part/scanning_module = 1,
		/datum/stock_part/micro_laser = 1,
		/obj/item/stack/cable_coil = 2,
	)

/obj/item/circuitboard/machine/overmap_radar/processor
	name = "Deep-Space Radar Processor"
	desc = "A machine board. Cleans compressed radar packets for Flight Ops consoles."
	build_path = /obj/machinery/overmap_radar/processor

/obj/item/circuitboard/machine/overmap_radar/bus
	name = "Deep-Space Radar Bus"
	desc = "A machine board. Junction for Flight Ops radar machines."
	build_path = /obj/machinery/overmap_radar/bus

/obj/item/circuitboard/machine/overmap_radar/dish
	name = "Deep-Space Radar Array"
	desc = "A machine board. Exterior radome that sweeps deep space."
	build_path = /obj/machinery/overmap_radar/dish
	req_components = list(
		/datum/stock_part/scanning_module = 2,
		/datum/stock_part/micro_laser = 2,
		/obj/item/stack/cable_coil = 5,
		/obj/item/stack/sheet/glass = 2,
	)

/obj/item/circuitboard/machine/overmap_radio_antenna
	name = "Deep-Space Radio Array"
	desc = "A machine board. Long-range deep-space radio antenna."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/overmap_radio/antenna
	req_components = list(
		/datum/stock_part/micro_laser = 1,
		/obj/item/stack/cable_coil = 2,
		/obj/item/stack/sheet/glass = 1,
	)

/datum/design/board/overmap_radar_console
	name = "Deep-Space Radar Console Board"
	id = "overmap_radar_console"
	build_path = /obj/item/circuitboard/computer/overmap_radar
	category = list(
		RND_CATEGORY_COMPUTER + RND_SUBCATEGORY_COMPUTER_COMMAND,
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE

/datum/design/board/overmap_radar_processor
	name = "Deep-Space Radar Processor Board"
	id = "overmap_radar_processor"
	build_type = IMPRINTER
	materials = list(/datum/material/glass = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/circuitboard/machine/overmap_radar/processor
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_TELECOMMS,
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE

/datum/design/board/overmap_radar_bus
	name = "Deep-Space Radar Bus Board"
	id = "overmap_radar_bus"
	build_type = IMPRINTER
	materials = list(/datum/material/glass = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/circuitboard/machine/overmap_radar/bus
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_TELECOMMS,
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE

/datum/design/board/overmap_radar_dish
	name = "Deep-Space Radar Array Board"
	id = "overmap_radar_dish"
	build_type = IMPRINTER
	materials = list(/datum/material/glass = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/circuitboard/machine/overmap_radar/dish
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_TELECOMMS,
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE

/datum/design/board/overmap_radio_antenna
	name = "Deep-Space Radio Array Board"
	id = "overmap_radio_antenna"
	build_type = IMPRINTER
	materials = list(/datum/material/glass = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/circuitboard/machine/overmap_radio_antenna
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_TELECOMMS,
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE

/datum/design/overmap_encryptionkey
	name = "Blank Deep-Space Encryption Key"
	id = "overmap_encryptionkey"
	build_type = AUTOLATHE | PROTOLATHE | AWAY_LATHE
	materials = list(/datum/material/iron = SMALL_MATERIAL_AMOUNT * 2, /datum/material/glass = SMALL_MATERIAL_AMOUNT)
	build_path = /obj/item/encryptionkey/overmap
	category = list(
		RND_CATEGORY_INITIAL,
		RND_CATEGORY_CONSTRUCTION + RND_SUBCATEGORY_CONSTRUCTION_ELECTRONICS,
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SERVICE
