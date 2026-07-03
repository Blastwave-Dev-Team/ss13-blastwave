/obj/item/gun/ballistic/rifle/c96
	name = "\improper NT M-96" //needed to be a rifle subtype to use bolt action code for internal magazine and all sorts of extra things
	desc = "An antiquated design revived due to its long-expired patent and interest from collectors of the original, although this model comes in at a fraction of the price as the real deal. Still pricey, however, due to its complicated construction."
	icon = 'modular_nova/modules/modular_weapons/icons/obj/company_and_or_faction_based/nanotrasen_armories/ballistic.dmi'
	icon_state = "mauser"
	inhand_icon_state = "gun"
	lefthand_file = 'icons/mob/inhands/weapons/guns_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/weapons/guns_righthand.dmi'
	worn_icon_state = "gun"
	fire_sound = 'modular_nova/modules/modular_weapons/sounds/bay_gunshot_magnum.ogg'
	fire_sound_volume = 80

	w_class = WEIGHT_CLASS_NORMAL
	slot_flags = ITEM_SLOT_BELT
	accepted_magazine_type = /obj/item/ammo_box/magazine/internal/c96
	can_suppress = FALSE
	casing_ejector = TRUE
	empty_indicator = FALSE
	bolt_type = BOLT_TYPE_LOCKING
	need_bolt_lock_to_interact = TRUE
	weapon_weight = WEAPON_MEDIUM
	semi_auto = TRUE
	fire_delay = 0.45 SECONDS
	projectile_damage_multiplier = 0.7 //crew gun using what's typically an antag round, this is more than warranted, maybe even will go lower after testing
	spread = 5 //maybe needs to go lower in the future, we shall see
/obj/item/gun/ballistic/rifle/c96/give_manufacturer_examine()
	AddElement(/datum/element/manufacturer_examine, COMPANY_NANOTRASEN)

/obj/item/gun/ballistic/automatic/pistol/commander
	name = "\improper Commander"
	desc = "A modification on the classic M1911 handgun, this one is chambered in 9mm. Much like its predecessor, it suffers from low capacity."
	icon = 'modular_nova/modules/modular_weapons/icons/obj/company_and_or_faction_based/nanotrasen_armories/ballistic.dmi'
	icon_state = "commander"
	w_class = WEIGHT_CLASS_NORMAL
	accepted_magazine_type = /obj/item/ammo_box/magazine/co9mm
	can_suppress = FALSE
	mag_display = FALSE
	fire_sound = 'sound/items/weapons/gun/pistol/shot_alt.ogg'
	rack_sound = 'sound/items/weapons/gun/pistol/rack.ogg'
	lock_back_sound = 'sound/items/weapons/gun/pistol/slide_lock.ogg'
	bolt_drop_sound = 'sound/items/weapons/gun/pistol/slide_drop.ogg'

/obj/item/gun/ballistic/automatic/pistol/commander/give_manufacturer_examine()
	AddElement(/datum/element/manufacturer_examine, COMPANY_NANOTRASEN)

/obj/item/gun/ballistic/automatic/pistol/commander/no_mag
	spawnwithmagazine = FALSE

/obj/item/gun/ballistic/automatic/pistol/commander/commissar
	name = "\improper Commissar"
	desc = "An NT Armories-issue variant of the Commander with a threaded barrel for pistol suppressors. Issued to investigative personnel who prefer a magazine-fed sidearm."
	can_suppress = TRUE
	suppressed_sound = 'sound/items/weapons/gun/pistol/shot_suppressed.ogg'
	suppressor_x_offset = 10
	suppressor_y_offset = -1

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/no_mag
	spawnwithmagazine = FALSE

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox
	name = "\improper Commissar (Vox)"
	desc = "There's a strange little speaker attached to the side of the pistol. It's giving you a sense of authority and command."
	var/funnysounds = TRUE
	var/cooldown = 0

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox/equipped(mob/living/user, slot)
	. = ..()
	if(slot == ITEM_SLOT_HANDS && funnysounds)
		playsound(src, 'modular_nova/modules/modular_weapons/sounds/commissar/pickup.ogg', 30, FALSE)

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox/shoot_live_shot(mob/living/user, pointblank = 0, atom/pbtarget = null, message = 1)
	. = ..()
	if(prob(50) && funnysounds)
		playsound(src, 'modular_nova/modules/modular_weapons/sounds/commissar/shot.ogg', 30, FALSE)

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox/shoot_with_empty_chamber(mob/living/user)
	. = ..()
	if(prob(50) && funnysounds)
		playsound(src, 'modular_nova/modules/modular_weapons/sounds/commissar/dry.ogg', 30, FALSE)

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox/insert_magazine(mob/user, obj/item/ammo_box/magazine/AM, display_message = TRUE)
	. = ..()
	if(bolt_locked)
		drop_bolt(user)
		if(. && funnysounds)
			playsound(src, 'modular_nova/modules/modular_weapons/sounds/commissar/magazine.ogg', 30, FALSE)

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox/multitool_act(mob/living/user, obj/item/tool)
	. = ..()
	funnysounds = !funnysounds
	to_chat(user, span_notice("You toggle [src]'s vox audio functions."))
	return ITEM_INTERACT_SUCCESS

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox/click_alt(mob/user)
	if(!isliving(user) || !user.can_perform_action(src, FORBID_TELEKINESIS_REACH))
		return
	if((cooldown < world.time - 200) && funnysounds)
		user.audible_message("<font color='red' size='5'><b>DON'T TURN AROUND!</b></font>")
		playsound(src, 'modular_nova/modules/modular_weapons/sounds/commissar/dontturnaround.ogg', 50, FALSE, 4)
		cooldown = world.time
	return CLICK_ACTION_SUCCESS

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox/examine(mob/user)
	. = ..()
	if(funnysounds)
		. += span_info("Alt-click to use \the [src] vox hailer.")

/obj/item/gun/ballistic/automatic/pistol/commander/commissar/vox/no_mag
	spawnwithmagazine = FALSE
