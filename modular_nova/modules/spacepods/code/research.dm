// MODULE ID: SPACEPODS
// Protolathe/imprinter designs and the techweb node that unlocks them.
// Ported from Whitesands (whitesands/code/modules/research/designs/spacepod_designs.dm
// and the relevant techweb node).

#define RND_SUBCATEGORY_SPACEPODS "/Spacepods"

/datum/design/board/spacepod_main
	name = "Circuit Design (Space Pod Mainboard)"
	desc = "Allows for the construction of a Space Pod mainboard."
	id = "spacepod_main"
	build_path = /obj/item/circuitboard/mecha/pod
	category = list(RND_CATEGORY_EXOSUIT_BOARDS + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

/datum/design/pod_core
	name = "Spacepod Core"
	desc = "Allows for the construction of a spacepod core system, made up of the engine and life support systems."
	id = "podcore"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 3, /datum/material/uranium = SHEET_MATERIAL_AMOUNT, /datum/material/plasma = SHEET_MATERIAL_AMOUNT * 3)
	build_path = /obj/item/pod_parts/core
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

/datum/design/pod_armor_civ
	name = "Spacepod Armor (civilian)"
	desc = "Allows for the construction of spacepod armor. This is the civilian version."
	id = "podarmor_civ"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 8, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/plasma = SHEET_MATERIAL_AMOUNT * 5)
	build_path = /obj/item/pod_parts/armor
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

/datum/design/pod_armor_black
	name = "Spacepod Armor (dark)"
	desc = "Allows for the construction of spacepod armor. This is the dark civilian version."
	id = "podarmor_dark"
	build_type = PROTOLATHE
	build_path = /obj/item/pod_parts/armor/black
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 8, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/plasma = SHEET_MATERIAL_AMOUNT * 5)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/datum/design/pod_armor_industrial
	name = "Spacepod Armor (industrial)"
	desc = "Allows for the construction of spacepod armor. This is the industrial grade version."
	id = "podarmor_industrial"
	build_type = PROTOLATHE
	build_path = /obj/item/pod_parts/armor/industrial
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 8, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/plasma = SHEET_MATERIAL_AMOUNT * 5, /datum/material/diamond = SHEET_MATERIAL_AMOUNT * 3, /datum/material/silver = SHEET_MATERIAL_AMOUNT * 4)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING

/datum/design/pod_armor_sec
	name = "Spacepod Armor (security)"
	desc = "Allows for the construction of spacepod armor. This is the security version."
	id = "podarmor_sec"
	build_type = PROTOLATHE
	build_path = /obj/item/pod_parts/armor/security
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 8, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/plasma = SHEET_MATERIAL_AMOUNT * 5, /datum/material/diamond = SHEET_MATERIAL_AMOUNT * 3, /datum/material/silver = SHEET_MATERIAL_AMOUNT * 4)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/pod_armor_gold
	name = "Spacepod Armor (golden)"
	desc = "Allows for the construction of spacepod armor. This is the golden version."
	id = "podarmor_gold"
	build_type = PROTOLATHE
	build_path = /obj/item/pod_parts/armor/gold
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 3, /datum/material/glass = SHEET_MATERIAL_AMOUNT, /datum/material/plasma = SHEET_MATERIAL_AMOUNT * 4, /datum/material/gold = SHEET_MATERIAL_AMOUNT * 5)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

//////////////////////////////////////////
//////SPACEPOD GUNS///////////////////////
//////////////////////////////////////////

/datum/design/pod_gun_disabler
	name = "Spacepod Equipment (Disabler)"
	desc = "Allows for the construction of a spacepod mounted disabler."
	id = "podgun_disabler"
	build_type = PROTOLATHE
	build_path = /obj/item/spacepod_equipment/weaponry/disabler
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 8)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/pod_gun_bdisabler
	name = "Spacepod Equipment (Burst Disabler)"
	desc = "Allows for the construction of a spacepod mounted disabler. This is the burst-fire model."
	id = "podgun_bdisabler"
	build_type = PROTOLATHE
	build_path = /obj/item/spacepod_equipment/weaponry/burst_disabler
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 8, /datum/material/plasma = SHEET_MATERIAL_AMOUNT)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/pod_gun_laser
	name = "Spacepod Equipment (Laser)"
	desc = "Allows for the construction of a spacepod mounted laser."
	id = "podgun_laser"
	build_type = PROTOLATHE
	build_path = /obj/item/spacepod_equipment/weaponry/laser
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 5, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/gold = SHEET_MATERIAL_AMOUNT, /datum/material/silver = SHEET_MATERIAL_AMOUNT)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/pod_ka_basic
	name = "Spacepod Equipment (Basic Kinetic Accelerator)"
	desc = "Allows for the construction of a weak spacepod Kinetic Accelerator."
	id = "pod_ka_basic"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 5, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/silver = SHEET_MATERIAL_AMOUNT, /datum/material/uranium = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/spacepod_equipment/weaponry/basic_pod_ka
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO

/datum/design/pod_ka
	name = "Spacepod Equipment (Kinetic Accelerator)"
	desc = "Allows for the construction of a spacepod Kinetic Accelerator."
	id = "pod_ka"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 5, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/silver = SHEET_MATERIAL_AMOUNT, /datum/material/gold = SHEET_MATERIAL_AMOUNT, /datum/material/diamond = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/spacepod_equipment/weaponry/pod_ka
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO

/datum/design/pod_plasma_cutter
	name = "Spacepod Equipment (Plasma Cutter)"
	desc = "Allows for the construction of a plasma cutter."
	id = "pod_plasma_cutter"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 5, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/silver = SHEET_MATERIAL_AMOUNT, /datum/material/gold = SHEET_MATERIAL_AMOUNT, /datum/material/diamond = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/spacepod_equipment/weaponry/plasma_cutter
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO

/datum/design/pod_adv_plasma_cutter
	name = "Spacepod Equipment (Advanced Plasma cutter)"
	desc = "Allows for the construction of an advanced plasma cutter."
	id = "pod_adv_plasma_cutter"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 5, /datum/material/glass = SHEET_MATERIAL_AMOUNT * 3, /datum/material/silver = SHEET_MATERIAL_AMOUNT * 2, /datum/material/gold = SHEET_MATERIAL_AMOUNT * 2, /datum/material/diamond = SHEET_MATERIAL_AMOUNT * 2)
	build_path = /obj/item/spacepod_equipment/weaponry/plasma_cutter/adv
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO

//////////////////////////////////////////
//////SPACEPOD MISC. ITEMS////////////////
//////////////////////////////////////////

/datum/design/pod_misc_tracker
	name = "Spacepod Tracking Module"
	desc = "Allows for the construction of a Space Pod Tracking Module."
	id = "podmisc_tracker"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 3)
	build_path = /obj/item/spacepod_equipment/tracker
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

//////////////////////////////////////////
//////SPACEPOD CARGO ITEMS////////////////
//////////////////////////////////////////

/datum/design/pod_cargo_ore
	name = "Spacepod Ore Storage Module"
	desc = "Allows for the construction of a Space Pod Ore Storage Module."
	id = "podcargo_ore"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 10, /datum/material/glass = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/spacepod_equipment/cargo/large/ore
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO

/datum/design/pod_cargo_crate
	name = "Spacepod Crate Storage Module"
	desc = "Allows the construction of a Space Pod Crate Storage Module."
	id = "podcargo_crate"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 13)
	build_path = /obj/item/spacepod_equipment/cargo/large
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

//////////////////////////////////////////
//////SPACEPOD SEC CARGO ITEMS////////////
//////////////////////////////////////////

/datum/design/passenger_seat
	name = "Spacepod Passenger Seat"
	desc = "Allows the construction of a Space Pod Passenger Seat Module."
	id = "podcargo_seat"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 4, /datum/material/glass = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/spacepod_equipment/cargo/chair
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

//////////////////////////////////////////
//////SPACEPOD LOCK ITEMS////////////////
//////////////////////////////////////////

/datum/design/pod_lock_keyed
	name = "Spacepod Tumbler Lock"
	desc = "Allows for the construction of a tumbler style podlock."
	id = "podlock_keyed"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	build_path = /obj/item/spacepod_equipment/lock/keyed
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

/datum/design/pod_key
	name = "Spacepod Tumbler Lock Key"
	desc = "Allows for the construction of a blank key for a podlock."
	id = "podkey"
	build_type = PROTOLATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT)
	build_path = /obj/item/spacepod_key
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	departmental_flags = DEPARTMENT_BITFLAG_CARGO | DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE | DEPARTMENT_BITFLAG_SECURITY

/datum/design/lockbuster
	name = "Spacepod Lock Buster"
	desc = "Allows for the construction of a spacepod lockbuster."
	id = "pod_lockbuster"
	build_type = PROTOLATHE
	build_path = /obj/item/lock_buster
	category = list(RND_CATEGORY_EQUIPMENT + RND_SUBCATEGORY_SPACEPODS)
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 8, /datum/material/diamond = SHEET_MATERIAL_AMOUNT) //it IS a drill!
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

//////////////////////////////////////////
//////SPACEPOD TECHWEB NODE////////////////
//////////////////////////////////////////

/datum/techweb_node/spacepods
	id = "spacepods"
	display_name = "Spacepod Construction"
	description = "Single-occupant utility pods for EVA salvage, mining, and patrol."
	prereq_ids = list(TECHWEB_NODE_MECH_ASSEMBLY)
	design_ids = list(
		"spacepod_main",
		"podcore",
		"podarmor_civ",
		"podarmor_dark",
		"podarmor_industrial",
		"podarmor_sec",
		"podarmor_gold",
		"podgun_disabler",
		"podgun_bdisabler",
		"podgun_laser",
		"pod_ka_basic",
		"pod_ka",
		"pod_plasma_cutter",
		"pod_adv_plasma_cutter",
		"podmisc_tracker",
		"podcargo_ore",
		"podcargo_crate",
		"podcargo_seat",
		"podlock_keyed",
		"podkey",
		"pod_lockbuster",
	)
	research_costs = list(TECHWEB_POINT_TYPE_GENERIC = TECHWEB_TIER_2_POINTS)

#undef RND_SUBCATEGORY_SPACEPODS
