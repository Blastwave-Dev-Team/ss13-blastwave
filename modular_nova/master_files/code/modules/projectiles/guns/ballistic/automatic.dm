/obj/item/gun/ballistic/automatic/battle_rifle
	max_shots_before_degradation = 30 // one clean mag before maintenance becomes an issue
	shots_before_degradation = 30
	degradation_probability = 5


/obj/item/gun/ballistic/automatic/rusty/c20r
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
	var/jam_chance = 10
	var/unjam_chance = 25
	var/jamming_increment = 5
	var/jammed = FALSE
	var/can_jam = TRUE

/obj/item/gun/ballistic/automatic/rusty/c20r/update_overlays()
	. = ..()
	if(!chambered && empty_indicator) //this is duplicated due to a layering issue with the select fire icon.
		. += "[icon_state]_empty"

/obj/item/gun/ballistic/automatic/rusty/c20r/process_fire(atom/target, mob/living/user, message, params, zone_override, bonus_spread)
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
			jam_chance = clamp (jam_chance, 0, 100)
	return ..()

/obj/item/gun/ballistic/automatic/rusty/c20r/attack_self(mob/user)
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


/obj/item/gun/ballistic/automatic/rusty/l6_saw
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
	var/jam_chance = 5
	var/jamming_increment = 1
	var/jammed = FALSE
	var/can_jam = TRUE

/obj/item/gun/ballistic/automatic/rusty/l6_saw/Initialize(mapload)
	. = ..()
	AddElement(/datum/element/update_icon_updates_onmob)
	AddComponent(/datum/component/automatic_fire, 0.25 SECONDS, /datum/component/two_handed)

/obj/item/gun/ballistic/automatic/rusty/l6_saw/process_fire(atom/target, mob/living/user, message, params, zone_override, bonus_spread)
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
			jam_chance = clamp (jam_chance, 0, 100)
	return ..()

/obj/item/gun/ballistic/automatic/rusty/l6_saw/attack_self(mob/user)
	if(jammed)
		if(do_after(user, 2 SECONDS))
			jammed = FALSE
			jam_chance = initial(jam_chance)
			balloon_alert(user, "the belt is forced back in place!")

	return ..()
