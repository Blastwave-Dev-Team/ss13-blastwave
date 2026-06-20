// Detective equipment beacons: sidearm and melee choices

/obj/item/choice_beacon/detective
	name = "detective equipment beacon"
	desc = "A single-use beacon to deliver equipment for investigative duties. Please only call this in your office!"
	icon_state = "sec_beacon"
	inhand_icon_state = "electronic"
	icon = 'modular_nova/modules/modular_items/icons/remote.dmi'
	company_source = "Nanotrasen Rapid Equipment Deployment Division"
	company_message = span_bold("Supply Pod incoming, please stand by.")

/obj/item/choice_beacon/detective/can_use_beacon(mob/living/user)
	if(user.mind?.assigned_role == JOB_DETECTIVE)
		return ..()

	playsound(src, 'sound/machines/buzz/buzz-sigh.ogg', 40, TRUE)
	return FALSE

/obj/item/choice_beacon/detective/sidearm
	name = "detective sidearm beacon"
	desc = "A single-use beacon to deliver your choice of sidearm. Please only call this in your office!"

/obj/item/choice_beacon/detective/sidearm/generate_display_names()
	var/static/list/selectable_types = list(
		"Colt Detective Special" = /obj/item/storage/toolbox/guncase/nova/detective/revolver,
		"Commissar" = /obj/item/storage/toolbox/guncase/nova/detective/commissar,
	)
	return selectable_types

/obj/item/choice_beacon/detective/melee
	name = "detective melee beacon"
	desc = "A single-use beacon to deliver your choice of melee weapon. Please only call this in your office!"

/obj/item/choice_beacon/detective/melee/generate_display_names()
	var/static/list/selectable_types = list(
		"Knuckleduster" = /obj/item/melee/knuckleduster,
		"Police Baton" = /obj/item/melee/baton,
	)
	return selectable_types

/obj/item/storage/toolbox/guncase/nova/detective/revolver
	name = "\improper Detective Revolver gunset"
	weapon_to_spawn = /obj/item/gun/ballistic/revolver/c38/detective
	extra_to_spawn = /obj/item/ammo_box/speedloader/c38

/obj/item/storage/toolbox/guncase/nova/detective/commissar
	name = "\improper Commissar gunset"
	weapon_to_spawn = /obj/item/gun/ballistic/automatic/pistol/commander/commissar/no_mag
	extra_to_spawn = /obj/item/ammo_box/magazine/co9mm
