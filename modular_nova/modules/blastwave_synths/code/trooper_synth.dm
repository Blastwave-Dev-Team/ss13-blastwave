// MODULE ID: BLASTWAVE_SYNTHS
// Derelict military synth infantry. Copies /mob/living/basic/trooper rather than spawning real humans,
// but wears the military synth chassis so corpses have synth organs and bleed coolant.

/// Corpse the troopers drop. Carries the species, so surgery and forensics on the body see real synth hardware.
/obj/effect/mob_spawn/corpse/human/blastwave_synth
	name = "military synthetic"
	mob_species = /datum/species/synthetic/military
	outfit = /datum/outfit/blastwave_synth

/datum/outfit/blastwave_synth
	name = "Military Synthetic"
	uniform = /obj/item/clothing/under/blastwave
	suit = /obj/item/clothing/suit/armor/vest
	shoes = /obj/item/clothing/shoes/combat
	gloves = /obj/item/clothing/gloves/combat
	mask = /obj/item/clothing/mask/gas/full

/mob/living/basic/trooper/blastwave_synth
	name = "military synthetic"
	desc = "A humanoid chassis in dust-caked plate, moving on old orders nobody is left to countermand. Something pale weeps from the seams."
	faction = list(FACTION_BLASTWAVE_DERELICT)
	species_path = /datum/species/synthetic/military
	corpse = /obj/effect/mob_spawn/corpse/human/blastwave_synth
	mob_spawner = /obj/effect/mob_spawn/corpse/human/blastwave_synth
	maxHealth = 120
	health = 120
	mob_biotypes = MOB_ROBOTIC | MOB_HUMANOID
	// Sealed chassis. Vacuum and temperature are not what stops these.
	unsuitable_atmos_damage = 0
	unsuitable_cold_damage = 0
	unsuitable_heat_damage = 0
	habitable_atmos = null
	minimum_survivable_temperature = 0
	// /mob/living/basic inherits default_blood_volume = 0, which makes CAN_HAVE_BLOOD false and suppresses every
	// splatter. Without this the coolant never shows up on a living hit, no matter what the species says.
	default_blood_volume = BLOOD_VOLUME_NORMAL
	ai_controller = /datum/ai_controller/basic_controller/trooper/calls_reinforcements

/mob/living/basic/trooper/blastwave_synth/Initialize(mapload)
	. = ..()
	ADD_TRAIT(src, TRAIT_SPACEWALK, INNATE_TRAIT)

/**
 * The choke point for every visible drop of blood this mob produces.
 *
 * /mob/living/get_bloodtype() never reads species: it sends MOB_ROBOTIC straight to oil. Overriding here is what
 * actually colors the flying splatter (temp_visual), the floor decal (make_blood_splatter) and blood left on
 * weapons and clothing (get_blood_dna_list). The global robotic-to-oil fallback is left alone on purpose.
 */
/mob/living/basic/trooper/blastwave_synth/get_bloodtype()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/mob/living/basic/trooper/blastwave_synth/emp_act(severity)
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	apply_damage(severity == EMP_HEAVY ? 30 : 15, BRUTE)
	do_sparks(3, FALSE, src)

/// Rifle-armed variant. Reuses the syndicate trooper's ranged plumbing.
/mob/living/basic/trooper/blastwave_synth/ranged
	desc = "A humanoid chassis in dust-caked plate, carrying a rifle it has clearly not cleaned in years."
	r_hand = /obj/item/gun/ballistic/automatic/pistol
	ai_controller = /datum/ai_controller/basic_controller/trooper/ranged

/mob/living/basic/trooper/blastwave_synth/ranged/Initialize(mapload)
	. = ..()
	AddComponent(\
		/datum/component/ranged_attacks,\
		casing_type = /obj/item/ammo_casing/c9mm,\
		projectile_sound = 'sound/items/weapons/gun/pistol/shot.ogg',\
		cooldown_time = 1.5 SECONDS,\
	)
