/obj/item/gun/ballistic/automatic/battle_rifle
	max_shots_before_degradation = 30 // one clean mag before maintenance becomes an issue
	shots_before_degradation = 30
	degradation_probability = 5


/obj/item/gun/ballistic/automatic/c20r/rusty
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

/obj/item/gun/ballistic/automatic/c20r/rusty/update_overlays()
	. = ..()
	if(!chambered && empty_indicator) //this is duplicated due to a layering issue with the select fire icon.
		. += "[icon_state]_empty"

/obj/item/gun/ballistic/automatic/c20r/rusty/process_fire(atom/target, mob/living/user, message, params, zone_override, bonus_spread)
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

/obj/item/gun/ballistic/automatic/c20r/rusty/attack_self(mob/user)
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
