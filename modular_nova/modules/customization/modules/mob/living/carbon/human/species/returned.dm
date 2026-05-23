/datum/species/returned
	name = "Returned"
	id = SPECIES_RETURNED
	inherent_traits = list(
		//BASIC TRAITS
		TRAIT_ADVANCEDTOOLUSER,
		TRAIT_CAN_STRIP,
		TRAIT_LITERATE,
		TRAIT_USES_SKINTONES,
		//RETURNED TRAITS
		TRAIT_BLOODY_MESS,
		TRAIT_EASILY_WOUNDED,
		TRAIT_EASYDISMEMBER,
		TRAIT_FAKEDEATH,
		TRAIT_LIMBATTACHMENT,
		TRAIT_LIVERLESS_METABOLISM,
		TRAIT_NOBREATH,
		TRAIT_NOSOFTCRIT,
		TRAIT_NOCRITDAMAGE,
		TRAIT_NOHUNGER,
		TRAIT_NO_DNA_COPY,
		TRAIT_NO_ZOMBIFY,
		TRAIT_RADIMMUNE,
		TRAIT_RESISTLOWPRESSURE,
		TRAIT_TOXIMMUNE,
		TRAIT_NOBLOOD,
		TRAIT_SUCCUMB_OVERRIDE,
		TRAIT_NO_EYELIDS, //There's no better way for me to prevent FAKEDEATH from constantly making Returned have their eyes shut than this right now. Ideally it would be a break right in _eyes.dm for anything undead but I can't figure that out right now. -afaenamednoah
	)
	//Eventually I'd like to move NOHUNGER from being innate to this to a neutral quirk so you can decide if your specific flavor or undead-ness means you still need to eat, but for now you're basically a high-functioning zombie.
	inherent_biotypes = MOB_UNDEAD|MOB_HUMANOID
	changesource_flags = MIRROR_BADMIN | WABBAJACK | MIRROR_PRIDE | MIRROR_MAGIC | ERT_SPAWN
	payday_modifier= 1.0
	examine_limb_id = SPECIES_HUMAN
	bodytemp_normal = T0C //Cold as a corpse. That is to say, you're the temperature of whatever the atmosphere you're in is.
	bodytemp_heat_damage_limit = FIRE_MINIMUM_TEMPERATURE_TO_EXIST //Take damage at fire temp. Normally cells would start to suffer before this but undead.
	bodytemp_cold_damage_limit = FIRE_SUIT_MIN_TEMP_PROTECT //Starts taking damage when it gets REALLY cold. Past this and you're probably in space already.

//Returned do not stabilize their body temperature by default, leaving them cold-blooded.
/datum/species/returned/body_temperature_core(mob/living/carbon/human/humi, seconds_per_tick)
	return

/datum/species/returned/get_physical_attributes()
	return "Returned are undead, and near-completely immune to most atmospheric hazards, or any physical threat that isn't blunt force trauma or burns. \
		However, they are exceedingly easy to injure, and their limbs are quite easy to pop out of place and dismember, but they can be popped back in just as easily as they can be removed. \
		They also cannot benefit at all from healing chemicals, making them entirely reliant on sutures, ointment, and surgery."

/datum/species/returned/get_species_description()
	return "The 'subspecies' simply known as the Returned are simply any member of another species that has been brought back to life in an undead state. \
		Typically, the manner in which they became undead leaves them relatively sane and aware, though this can vary depending on the Returned."

/datum/species/returned/get_species_lore()
	return list("Returned can come from any manner of different places. Use the custom species lore to give some insight into yours in particular!")

/datum/species/returned/create_pref_temperature_perks()
	var/list/to_add = list()

	to_add += list(list(
		SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
		SPECIES_PERK_ICON = "thermometer-half",
		SPECIES_PERK_NAME = "No Body Temperature",
		SPECIES_PERK_DESC = "Having been raised as an undead, the Returned do not have anything \
			regulating their body temperature anymore. This means that \
			the environment decides their body temperature - which is relatively fine, \
			unless it gets a bit too hot or they're thrown into space.",
	),
	list(
		SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
		SPECIES_PERK_ICON = "tint-slash",
		SPECIES_PERK_NAME = "Chemical Immunity",
		SPECIES_PERK_DESC = "For better or for worse (usually worse), \
			you cannot process any chemicals. This means the only way you can be healed \
			is via surgery or the direct application of sutures and ointment- \
			be very careful with burns and infections!",
	))

	return to_add

/datum/species/returned/prepare_human_for_preview(mob/living/carbon/human/human)
	human.skin_tone = "beige"
	human.hair_color = "#1d1d1d"
	human.hairstyle = "Short Hair"
	regenerate_organs(human, src, visual_only = TRUE)
	human.update_body(TRUE)
