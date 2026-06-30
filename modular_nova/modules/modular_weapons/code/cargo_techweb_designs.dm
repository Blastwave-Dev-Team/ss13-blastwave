/datum/design/mag_c35sol_pistol
	name = "Magazine (.35 Sol Short)"
	desc = "A twelve-round magazine for SolFed pistols."
	id = "mag_c35sol_pistol"
	build_type = PROTOLATHE | AWAY_LATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	build_path = /obj/item/ammo_box/magazine/c35sol_pistol/starts_empty
	category = list(
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/mag_c35sol_pistol_stendo
	name = "Magazine (.35 Sol Short, Extended)"
	desc = "A twenty-four-round extended magazine for SolFed pistols."
	id = "mag_c35sol_pistol_stendo"
	build_type = PROTOLATHE | AWAY_LATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 3)
	build_path = /obj/item/ammo_box/magazine/c35sol_pistol/stendo/starts_empty
	category = list(
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/mag_c40sol_rifle
	name = "Magazine (.40 Sol Long, Short)"
	desc = "A fifteen-round shortened magazine for SolFed rifles."
	id = "mag_c40sol_rifle"
	build_type = PROTOLATHE | AWAY_LATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 3)
	build_path = /obj/item/ammo_box/magazine/c40sol_rifle/starts_empty
	category = list(
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/mag_c40sol_rifle_standard
	name = "Magazine (.40 Sol Long)"
	desc = "A thirty-round magazine for SolFed rifles."
	id = "mag_c40sol_rifle_standard"
	build_type = PROTOLATHE | AWAY_LATHE
	materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 4,
		/datum/material/plastic = HALF_SHEET_MATERIAL_AMOUNT,
	)
	build_path = /obj/item/ammo_box/magazine/c40sol_rifle/standard/starts_empty
	category = list(
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/mag_c980_grenade
	name = "Kiboko Grenade Box"
	desc = "A four-shell box magazine for .980 grenade launchers."
	id = "mag_c980_grenade"
	build_type = PROTOLATHE | AWAY_LATHE
	materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 4,
		/datum/material/plastic = SHEET_MATERIAL_AMOUNT,
	)
	build_path = /obj/item/ammo_box/magazine/c980_grenade/starts_empty
	category = list(
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/mag_c980_grenade_drum
	name = "Kiboko Grenade Drum"
	desc = "A six-shell drum magazine for .980 grenade launchers."
	id = "mag_c980_grenade_drum"
	build_type = PROTOLATHE | AWAY_LATHE
	materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 5,
		/datum/material/plastic = SHEET_MATERIAL_AMOUNT,
	)
	build_path = /obj/item/ammo_box/magazine/c980_grenade/drum/starts_empty
	category = list(
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY

/datum/design/mag_co9mm
	name = "Commander Magazine (9mm)"
	desc = "An eight-round single-stack magazine for NT Commander and Commissar pistols."
	id = "mag_co9mm"
	build_type = PROTOLATHE | AWAY_LATHE
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	build_path = /obj/item/ammo_box/magazine/co9mm/starts_empty
	category = list(
		RND_CATEGORY_WEAPONS + RND_SUBCATEGORY_WEAPONS_AMMO
	)
	departmental_flags = DEPARTMENT_BITFLAG_SECURITY
