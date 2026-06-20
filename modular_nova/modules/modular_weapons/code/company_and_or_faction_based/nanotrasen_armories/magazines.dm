/obj/item/ammo_box/magazine/internal/c96
	name = "\improper NT M-96 pistol internal magazine"
	desc = "Oh god, this shouldn't be here"
	ammo_type = /obj/item/ammo_casing/c10mm
	caliber = CALIBER_10MM
	max_ammo = 10

/obj/item/ammo_box/magazine/co9mm
	name = "Commander magazine (9mm)"
	desc = "A single-stack M1911-style magazine, modified to chamber 9mm. Holds 8 rounds."
	icon = 'modular_nova/modules/modular_weapons/icons/obj/company_and_or_faction_based/nanotrasen_armories/magazines.dmi'
	icon_state = "co9mm-8"
	base_icon_state = "co9mm"
	ammo_type = /obj/item/ammo_casing/c9mm
	caliber = CALIBER_9MM
	max_ammo = 8

/obj/item/ammo_box/magazine/co9mm/update_icon_state()
	. = ..()
	icon_state = "[base_icon_state]-[ammo_count()]"
