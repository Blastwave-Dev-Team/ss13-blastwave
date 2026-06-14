// Character-creation preferences for the Arachnid species' three signature
// external organs (legs, spinneret, mandibles).

/datum/preference/choiced/mutant_choice/arachnid_part
	abstract_type = /datum/preference/choiced/mutant_choice/arachnid_part
	var/datum/sprite_accessory/native_default_type

/datum/preference/choiced/mutant_choice/arachnid_part/is_part_enabled(datum/preferences/preferences)
	return TRUE

/datum/preference/choiced/mutant_choice/arachnid_part/proc/is_species_native(datum/preferences/preferences)
	var/species_type = preferences?.read_preference(/datum/preference/choiced/species)
	var/datum/species/species = GLOB.species_prototypes[species_type]
	return species && (savefile_key in species.get_features())

/datum/preference/choiced/mutant_choice/arachnid_part/create_informed_default_value(datum/preferences/preferences)
	if(is_species_native(preferences))
		return initial(native_default_type.name)
	return SPRITE_ACCESSORY_NONE

/datum/preference/choiced/mutant_choice/arachnid_part/apply_to_human(mob/living/carbon/human/target, value, datum/preferences/preferences)
	if(!preferences || !is_species_native(preferences))
		target.dna.mutant_bodyparts -= relevant_mutant_bodypart
		return FALSE
	if(value == SPRITE_ACCESSORY_NONE)
		value = initial(native_default_type.name)
	var/datum/mutant_bodypart/mutant_bodypart = target.dna.mutant_bodyparts[relevant_mutant_bodypart]
	if(mutant_bodypart)
		mutant_bodypart.name = value
	else
		target.dna.mutant_bodyparts[relevant_mutant_bodypart] = build_mutant_part(value)
	return TRUE

/datum/preference/color/arachnid_part
	abstract_type = /datum/preference/color/arachnid_part
	priority = PREFERENCE_PRIORITY_PRE_SPECIES
	category = PREFERENCE_CATEGORY_SECONDARY_FEATURES
	savefile_identifier = PREFERENCE_CHARACTER

/datum/preference/color/arachnid_part/apply_to_human(mob/living/carbon/human/target, value)
	var/datum/mutant_bodypart/mutant_part = target.dna.mutant_bodyparts[relevant_mutant_bodypart]
	if(mutant_part)
		mutant_part.set_primary_color(sanitize_hexcolor(value))

/datum/preference/toggle/emissive/arachnid_part
	abstract_type = /datum/preference/toggle/emissive/arachnid_part
	priority = PREFERENCE_PRIORITY_PRE_SPECIES
	category = PREFERENCE_CATEGORY_SECONDARY_FEATURES
	savefile_identifier = PREFERENCE_CHARACTER
	default_value = FALSE
	check_mode = TRICOLOR_CHECK_ACCESSORY

/datum/preference/toggle/emissive/arachnid_part/apply_to_human(mob/living/carbon/human/target, value, datum/preferences/preferences)
	if(!preferences?.read_preference(/datum/preference/toggle/allow_emissives))
		value = FALSE
	var/datum/mutant_bodypart/mutant_part = target.dna.mutant_bodyparts[relevant_mutant_bodypart]
	if(isnull(mutant_part))
		return TRUE
	mutant_part.set_emissive_tri_bool_list(value, value, value)
	return TRUE

/// === SPIDER LEGS ==================================================

/datum/preference/choiced/mutant_choice/arachnid_part/spider_legs
	savefile_key = "feature_spider_legs"
	relevant_mutant_bodypart = FEATURE_SPIDER_LEGS
	default_accessory_type = /datum/sprite_accessory/spider_legs/none
	native_default_type = /datum/sprite_accessory/spider_legs/plain

/datum/preference/color/arachnid_part/spider_legs
	savefile_key = "spider_legs_color"
	relevant_mutant_bodypart = FEATURE_SPIDER_LEGS

/datum/preference/toggle/emissive/arachnid_part/spider_legs
	savefile_key = "spider_legs_emissive"
	relevant_mutant_bodypart = FEATURE_SPIDER_LEGS
	type_to_check = /datum/preference/choiced/mutant_choice/arachnid_part/spider_legs

/// === SPIDER SPINNERET ============================================

/datum/preference/choiced/mutant_choice/arachnid_part/spider_spinneret
	savefile_key = "feature_spider_spinneret"
	relevant_mutant_bodypart = FEATURE_SPIDER_SPINNERET
	default_accessory_type = /datum/sprite_accessory/spider_spinneret/none
	native_default_type = /datum/sprite_accessory/spider_spinneret/plain

/datum/preference/color/arachnid_part/spider_spinneret
	savefile_key = "spider_spinneret_color"
	relevant_mutant_bodypart = FEATURE_SPIDER_SPINNERET

/datum/preference/toggle/emissive/arachnid_part/spider_spinneret
	savefile_key = "spider_spinneret_emissive"
	relevant_mutant_bodypart = FEATURE_SPIDER_SPINNERET
	type_to_check = /datum/preference/choiced/mutant_choice/arachnid_part/spider_spinneret

/// === SPIDER MANDIBLES ============================================

/datum/preference/choiced/mutant_choice/arachnid_part/spider_mandibles
	savefile_key = "feature_spider_mandibles"
	relevant_mutant_bodypart = FEATURE_SPIDER_MANDIBLES
	default_accessory_type = /datum/sprite_accessory/spider_mandibles/none
	native_default_type = /datum/sprite_accessory/spider_mandibles/plain

/datum/preference/color/arachnid_part/spider_mandibles
	savefile_key = "spider_mandibles_color"
	relevant_mutant_bodypart = FEATURE_SPIDER_MANDIBLES

/datum/preference/toggle/emissive/arachnid_part/spider_mandibles
	savefile_key = "spider_mandibles_emissive"
	relevant_mutant_bodypart = FEATURE_SPIDER_MANDIBLES
	type_to_check = /datum/preference/choiced/mutant_choice/arachnid_part/spider_mandibles
