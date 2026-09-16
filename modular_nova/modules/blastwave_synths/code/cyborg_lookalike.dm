// MODULE ID: BLASTWAVE_SYNTHS
// Cyborg-shaped ruin enemies. Deliberately NOT /mob/living/silicon/robot (that is a player silicon: laws, models,
// radio, AI link, modules) and NOT /mob/living/basic/bot (station-bot UX: ID unlock, patrol, emag, possession).
// This is hivebot combat guts wearing borg skin.

/mob/living/basic/blastwave_cyborg
	name = "derelict cyborg"
	desc = "An armoured cyborg chassis with its faceplate scoured back to bare metal. The optics still track you."
	icon = 'icons/mob/silicon/robots.dmi'
	icon_state = "robot"
	icon_living = "robot"
	icon_dead = "robot"
	gender = NEUTER
	mob_biotypes = MOB_ROBOTIC
	basic_mob_flags = DEL_ON_DEATH
	faction = list(FACTION_BLASTWAVE_DERELICT)

	maxHealth = 160
	health = 160
	melee_damage_lower = 12
	melee_damage_upper = 18
	melee_attack_cooldown = 1.4 SECONDS
	attack_verb_continuous = "slams"
	attack_verb_simple = "slam"
	attack_sound = 'sound/items/weapons/punch1.ogg'
	attack_vis_effect = ATTACK_EFFECT_SMASH
	combat_mode = TRUE
	speed = 1.4

	verb_say = "states"
	verb_ask = "queries"
	verb_exclaim = "declares"
	verb_yell = "alarms"
	speech_span = SPAN_ROBOT
	bubble_icon = "machine"
	death_message = "shudders and goes dark!"

	// Sealed chassis: vacuum-proof, and it does not care about the temperature either.
	habitable_atmos = null
	minimum_survivable_temperature = 0
	unsuitable_atmos_damage = 0
	unsuitable_cold_damage = 0
	unsuitable_heat_damage = 0
	damage_coeff = list(BRUTE = 1, BURN = 1, TOX = 0, STAMINA = 0, OXY = 0)
	// Spark-only on hit. No blood override here, unlike the synth troopers.
	default_blood_volume = 0
	ai_controller = /datum/ai_controller/basic_controller/trooper

/mob/living/basic/blastwave_cyborg/Initialize(mapload)
	. = ..()
	ADD_TRAIT(src, TRAIT_SPACEWALK, INNATE_TRAIT)
	AddElement(/datum/element/death_drops, /obj/effect/decal/cleanable/blood/gibs/robot_debris)
	AddElement(/datum/element/footstep, footstep_type = FOOTSTEP_MOB_HEAVY)

/mob/living/basic/blastwave_cyborg/death(gibbed)
	do_sparks(5, FALSE, src)
	return ..()

/mob/living/basic/blastwave_cyborg/emp_act(severity)
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	apply_damage(severity == EMP_HEAVY ? 60 : 30, BRUTE)
	do_sparks(5, FALSE, src)

/// Disabler-armed security chassis. The one you want covering an open room.
/mob/living/basic/blastwave_cyborg/security
	name = "derelict security cyborg"
	desc = "A security cyborg chassis, one arm ending in a disabler emitter that never got the stand-down order."
	icon_state = "sec"
	icon_living = "sec"
	icon_dead = "sec"
	ai_controller = /datum/ai_controller/basic_controller/trooper/ranged

/mob/living/basic/blastwave_cyborg/security/Initialize(mapload)
	. = ..()
	AddComponent(\
		/datum/component/ranged_attacks,\
		casing_type = /obj/item/ammo_casing/energy/disabler,\
		projectile_sound = 'sound/items/weapons/taser2.ogg',\
		cooldown_time = 2 SECONDS,\
	)

/// Heavier engineering chassis, for the core rooms.
/mob/living/basic/blastwave_cyborg/engineering
	name = "derelict engineering cyborg"
	desc = "An engineering cyborg chassis, still hauling tools for repairs it will never finish."
	icon_state = "engineer"
	icon_living = "engineer"
	icon_dead = "engineer"
	maxHealth = 220
	health = 220
	melee_damage_lower = 18
	melee_damage_upper = 24
	speed = 1.8
