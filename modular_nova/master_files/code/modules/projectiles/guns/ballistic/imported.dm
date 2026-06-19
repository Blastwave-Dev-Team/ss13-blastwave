// the bullshit
/obj/item/gun/ballistic/rusty
	// chance for the gun to jam
	var/jam_chance = 0
	//chance for gun to unjam
	var/unjam_chance = 100
	//jam chance increase
	var/jamming_increment = 0
	//is the gun jammed
	var/jammed = FALSE
	//can the gun jam
	var/can_jam = FALSE

/obj/item/gun/ballistic/rusty/l6_saw
    name = "\improper damaged L6 SAW"
    desc = "A heavily modified, and degraded, 7mm light machine gun, designated 'L6 SAW'. the top-cover is missing and the bolt seems worn enough that its started slipping"
    icon_state = "l6"
    inhand_icon_state = "l6closedmag"
    base_icon_state = "l6"
    w_class = WEIGHT_CLASS_HUGE
    slot_flags = 0
    accepted_magazine_type = /obj/item/ammo_box/magazine/m7mm
    weapon_weight = WEAPON_HEAVY
    burst_size = 1
    projectile_damage_multiplier = 0.5
    actions_types = list()
    can_suppress = FALSE
    spread = 7
    pin = /obj/item/firing_pin
    bolt_type = BOLT_TYPE_OPEN
    show_bolt_icon = FALSE
    mag_display = TRUE
    mag_display_ammo = TRUE
    tac_reloads = FALSE
    fire_sound = 'sound/items/weapons/gun/l6/shot.ogg'
    rack_sound = 'sound/items/weapons/gun/l6/l6_rack.ogg'
    suppressed_sound = 'sound/items/weapons/gun/general/heavy_shot_suppressed.ogg'
    jam_chance = 5
    jamming_increment = 1
    jammed = FALSE
    can_jam = TRUE

/obj/item/gun/ballistic/rusty/l6_saw/Initialize(mapload)
    . = ..()
    AddElement(/datum/element/update_icon_updates_onmob)
    AddComponent(/datum/component/automatic_fire, 0.25 SECONDS, /datum/component/two_handed)

/obj/item/gun/ballistic/rusty/l6_saw/process_fire(atom/target, mob/living/user, message, params, zone_override, bonus_spread)
    if(jammed)
        balloon_alert(user, "the belt is loose!")
        return FALSE
    if(can_jam)
        if(chambered.loaded_projectile)
            if(prob(jam_chance))
                jammed = TRUE
                balloon_alert(user, "the belt slips from your hand!")
                playsound(user,'sound/items/weapons/jammed.ogg', 25, TRUE)
                jam_chance = initial(jam_chance)
                return FALSE
            jam_chance += jamming_increment
            jam_chance = clamp (jam_chance, -50, 100)
    return ..()

/obj/item/gun/ballistic/rusty/l6_saw/attack_self(mob/user)
    if(jammed)
        if(do_after(user, 2 SECONDS))
            jammed = FALSE
            jam_chance = initial(jam_chance)
            balloon_alert(user, "the belt is forced back in place!")

    return ..()

/obj/item/gun/ballistic/rusty/c20r
	name = "\improper rusty C-20r SMG"
	desc = "A formerly three-round burst bullpup, .45 SMG designated 'C-20r'. its so heavily rusted yu can't see manufacturer details anymore."
	icon_state = "c20r"
	inhand_icon_state = "c20r"
	selector_switch_icon = TRUE
	accepted_magazine_type = /obj/item/ammo_box/magazine/smgm45
	spawn_magazine_type = /obj/item/ammo_box/magazine/smgm45
	burst_size = 2
	burst_delay = 3
	projectile_damage_multiplier = 0.8
	pin = /obj/item/firing_pin
	mag_display = TRUE
	mag_display_ammo = TRUE
	empty_indicator = TRUE
	jam_chance = 10
	unjam_chance = 25
	jamming_increment = 5
	jammed = FALSE
	can_jam = TRUE

/obj/item/gun/ballistic/rusty/c20r/update_overlays()
	. = ..()
	if(!chambered && empty_indicator) //this is duplicated due to a layering issue with the select fire icon.
		. += "[icon_state]_empty"

/obj/item/gun/ballistic/rusty/c20r/process_fire(atom/target, mob/living/user, message, params, zone_override, bonus_spread)
	if(jammed)
		balloon_alert(user, "the bolt is seized!")
		return FALSE
	if(can_jam)
		if(chambered.loaded_projectile)
			if(prob(jam_chance))
				jammed = TRUE
				balloon_alert(user, "the bolt locks up!")
				playsound(user,'sound/items/weapons/jammed.ogg', 25, TRUE)
				jam_chance = initial(jam_chance)
				return FALSE
			jam_chance += jamming_increment
			jam_chance = clamp (jam_chance, -50, 100)
	return ..()

/obj/item/gun/ballistic/rusty/c20r/attack_self(mob/user)
	if(jammed)
		if(prob(unjam_chance))
			jammed = FALSE
			unjam_chance = initial(unjam_chance)
		else
			unjam_chance += 10
			balloon_alert(user, "bolt is still stuck!")
			playsound(user,'sound/items/weapons/jammed.ogg', 25, TRUE)
			return FALSE
	return ..()

/obj/item/gun/ballistic/rusty/bulldog
	name = "\improper Degraded Bulldog Shotgun"
	desc = "A 2-round burst fire, mag-fed shotgun for combat in narrow corridors, \
		nicknamed 'Bulldog' by boarding parties. Compatible only with specialized 8-round drum magazines. \
		has a port for a secondary magazine, but there's so much rust buildup over the electronics that \
		you doubt you could cram one in if you tried."
	icon_state = "bulldog"
	lefthand_file = 'icons/mob/inhands/weapons/guns_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/weapons/guns_righthand.dmi'
	inhand_icon_state = "bulldog"
	worn_icon = 'icons/mob/clothing/back.dmi'
	worn_icon_state = "bulldog"
	inhand_x_dimension = 32
	inhand_y_dimension = 32
	projectile_damage_multiplier = 0.65
	weapon_weight = WEAPON_MEDIUM
	accepted_magazine_type = /obj/item/ammo_box/magazine/m12g
	spawn_magazine_type = /obj/item/ammo_box/magazine/m12g/slug
	can_suppress = FALSE
	burst_size = 2
	fire_delay = 4
	burst_delay = 3
	randomspread = 15
	dual_wield_spread = 50
	pin = /obj/item/firing_pin
	fire_sound = 'sound/items/weapons/gun/shotgun/shot_alt.ogg'
	actions_types = list(/datum/action/item_action/toggle_firemode)
	mag_display = TRUE
	empty_indicator = TRUE
	empty_alarm = TRUE
	special_mags = TRUE
	mag_display_ammo = TRUE
	semi_auto = TRUE
	internal_magazine = FALSE
	tac_reloads = TRUE
	burst_fire_selection = TRUE
	jam_chance = 20
	unjam_chance = 25
	jamming_increment = 10
	jammed = FALSE
	can_jam = TRUE

/obj/item/gun/ballistic/rusty/bulldog/update_overlays()
	. = ..()
	if(!chambered && empty_indicator) //this is duplicated due to a layering issue with the select fire icon.
		. += "[icon_state]_empty"

/obj/item/gun/ballistic/rusty/bulldog/process_fire(atom/target, mob/living/user, message, params, zone_override, bonus_spread)
	if(jammed)
		balloon_alert(user, "the bolt is seized!")
		return FALSE
	if(can_jam)
		if(chambered.loaded_projectile)
			if(prob(jam_chance))
				jammed = TRUE
				balloon_alert(user, "the bolt locks up!")
				playsound(user,'sound/items/weapons/jammed.ogg', 25, TRUE)
				jam_chance = initial(jam_chance)
				return FALSE
			jam_chance += jamming_increment
			jam_chance = clamp (jam_chance, -50, 100)
	return ..()

/obj/item/gun/ballistic/rusty/bulldog/attack_self(mob/user)
	if(jammed)
		if(prob(unjam_chance))
			jammed = FALSE
			unjam_chance = initial(unjam_chance)
		else
			unjam_chance += 10
			balloon_alert(user, "bolt is still stuck!")
			playsound(user,'sound/items/weapons/jammed.ogg', 25, TRUE)
			return FALSE
	return ..()

/obj/item/gun/ballistic/rusty/makarov
	name = "\improper damaged Makarov pistol"
	desc = "A small, easily concealable 9x25mm Mk.12 handgun. Has a threaded barrel for suppressors... despite the rust, it hasnt lost much functionality"
	icon_state = "pistol"
	w_class = WEIGHT_CLASS_SMALL
	accepted_magazine_type = /obj/item/ammo_box/magazine/m9mm
	can_suppress = TRUE
	burst_size = 1
	projectile_damage_multiplier = 0.9
	fire_delay = 0.2 SECONDS
	actions_types = list()
	bolt_type = BOLT_TYPE_LOCKING
	fire_sound = 'sound/items/weapons/gun/pistol/shot.ogg'
	dry_fire_sound = 'sound/items/weapons/gun/pistol/dry_fire.ogg'
	suppressed_sound = 'sound/items/weapons/gun/pistol/shot_suppressed.ogg'
	load_sound = 'sound/items/weapons/gun/pistol/mag_insert.ogg'
	load_empty_sound = 'sound/items/weapons/gun/pistol/mag_insert.ogg'
	eject_sound = 'sound/items/weapons/gun/pistol/mag_release.ogg'
	eject_empty_sound = 'sound/items/weapons/gun/pistol/mag_release.ogg'
	rack_sound = 'sound/items/weapons/gun/pistol/rack_small.ogg'
	lock_back_sound = 'sound/items/weapons/gun/pistol/lock_small.ogg'
	bolt_drop_sound = 'sound/items/weapons/gun/pistol/drop_small.ogg'
	drop_sound = 'sound/items/handling/gun/ballistics/pistol/pistol_drop1.ogg'
	pickup_sound = 'sound/items/handling/gun/ballistics/pistol/pistol_pickup1.ogg'
	fire_sound_volume = 90
	bolt_wording = "slide"
	suppressor_x_offset = 10
	suppressor_y_offset = -1
	recoil_backtime_multiplier = 1

	jam_chance = 5
	unjam_chance = 70
	jamming_increment = 1
	jammed = FALSE
	can_jam = TRUE


/obj/item/gun/ballistic/rusty/makarov/process_fire(atom/target, mob/living/user, message, params, zone_override, bonus_spread)
	if(jammed)
		balloon_alert(user, "the bolt is seized!")
		return FALSE
	if(can_jam)
		if(chambered.loaded_projectile)
			if(prob(jam_chance))
				jammed = TRUE
				balloon_alert(user, "the bolt locks up!")
				playsound(user,'sound/items/weapons/jammed.ogg', 25, TRUE)
				jam_chance = initial(jam_chance)
				return FALSE
			jam_chance += jamming_increment
			jam_chance = clamp (jam_chance, -50, 100)
	return ..()

/obj/item/gun/ballistic/rusty/makarov/attack_self(mob/user)
	if(jammed)
		if(prob(unjam_chance))
			jammed = FALSE
			unjam_chance = initial(unjam_chance)
		else
			unjam_chance += 15
			balloon_alert(user, "bolt is still stuck!")
			playsound(user,'sound/items/weapons/jammed.ogg', 25, TRUE)
			return FALSE
	return ..()
