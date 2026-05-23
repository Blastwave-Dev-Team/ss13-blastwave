// Character-creation preferences for the Arachnid species' three signature
// external organs (legs, spinneret, mandibles).
//
// Why this file exists at all:
//   The main character preview (render_new_preview_appearance) explicitly
//   resets mannequin.dna.mutant_bodyparts to an empty list before re-applying
//   prefs, and /datum/species/set_species only restores defaults when
//   `allow_customizable_dna_features` is FALSE. Arachnids leave that flag at
//   its default (TRUE) so all of their visible mutant parts MUST be backed by
//   a /datum/preference/choiced/mutant_choice subtype, otherwise the parts
//   never make it back into dna.mutant_bodyparts and /datum/species/regenerate_organs
//   (Nova override) has nothing to install organs from.
//
// Color model:
//   The spider sprite accessories declare `color_src = USE_ONE_COLOR`, meaning
//   only the primary color slot (`mutant_part.colors[1]`) is ever applied at
//   render time - the engine ignores slots 2/3 for single-color accessories.
//   Rather than show the player three swatches and quietly drop two of them,
//   we use a single /datum/preference/color/... per part and write to
//   set_primary_color(). If the WS art is ever split into _primary/_secondary/
//   _tertiary masks (USE_MATRIXED_COLORS) these can be upgraded to tri_color
//   without changing the savefile keys (the key naming stayed identical).
//
// Always-on:
//   Spider parts are species signifiers, not optional features. There is no
//   per-part enable toggle - the mutant_choice overrides is_part_enabled() to
//   always return TRUE, bypassing the toggle-gating in the base class. The
//   species-side visibility is still automatic via get_features() walking
//   GLOB.default_mutant_bodyparts["Arachnid"], so non-arachnids never see
//   these prefs even though is_part_enabled is unconditional.
//
// Emissive:
//   /datum/preference/toggle/emissive base class sets all 3 emissive slots to
//   the same bool, which is the right thing for USE_ONE_COLOR (only slot 1
//   gets rendered anyway). check_mode = TRICOLOR_CHECK_ACCESSORY hides the
//   emissive toggle when the player has the part set to "None".
//
//   Two footguns in the base class that we have to work around per-pref:
//     1. /datum/preference/toggle's default_value is TRUE, so we explicitly
//        set FALSE - emissive chitin "on by default" is loud and surprising.
//     2. /datum/preference/toggle/emissive/apply_to_human does NOT consult
//        the global /datum/preference/toggle/allow_emissives, even though
//        is_accessible() does. That means a saved/defaulted TRUE will still
//        apply even when the global emissives toggle is off and the per-part
//        checkbox is hidden in the UI. We override apply_to_human to gate on
//        the global pref, mirroring what /datum/preference/toggle/eye_emissives
//        already does.

/// Shared base for arachnid emissive prefs. Forces default OFF and refuses to
/// apply emissives at all if the global /datum/preference/toggle/allow_emissives
/// is off. Mirrors the pattern used by /datum/preference/toggle/eye_emissives.
/datum/preference/toggle/emissive/arachnid_part
	abstract_type = /datum/preference/toggle/emissive/arachnid_part
	category = PREFERENCE_CATEGORY_SECONDARY_FEATURES
	savefile_identifier = PREFERENCE_CHARACTER
	default_value = FALSE
	check_mode = TRICOLOR_CHECK_ACCESSORY

/datum/preference/toggle/emissive/arachnid_part/apply_to_human(mob/living/carbon/human/target, value, datum/preferences/preferences)
	// Hard-gate on the global "allow emissives" toggle - the base class only
	// checks it in is_accessible(), so a stale TRUE in the savefile would
	// otherwise still render emissives even with the global pref off.
	if(!preferences?.read_preference(/datum/preference/toggle/allow_emissives))
		value = FALSE
	return ..(target, value)

/// === SPIDER LEGS ==================================================

/datum/preference/choiced/mutant_choice/spider_legs
	savefile_key = "feature_spider_legs"
	relevant_mutant_bodypart = FEATURE_SPIDER_LEGS
	default_accessory_type = /datum/sprite_accessory/spider_legs/plain

/datum/preference/choiced/mutant_choice/spider_legs/is_part_enabled(datum/preferences/preferences)
	return TRUE

/datum/preference/color/spider_legs
	category = PREFERENCE_CATEGORY_SECONDARY_FEATURES
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "spider_legs_color"
	relevant_mutant_bodypart = FEATURE_SPIDER_LEGS

/datum/preference/color/spider_legs/apply_to_human(mob/living/carbon/human/target, value)
	var/datum/mutant_bodypart/mutant_part = target.dna.mutant_bodyparts[FEATURE_SPIDER_LEGS]
	if(mutant_part)
		mutant_part.set_primary_color(sanitize_hexcolor(value))

/datum/preference/toggle/emissive/arachnid_part/spider_legs
	savefile_key = "spider_legs_emissive"
	relevant_mutant_bodypart = FEATURE_SPIDER_LEGS
	type_to_check = /datum/preference/choiced/mutant_choice/spider_legs

/// === SPIDER SPINNERET ============================================

/datum/preference/choiced/mutant_choice/spider_spinneret
	savefile_key = "feature_spider_spinneret"
	relevant_mutant_bodypart = FEATURE_SPIDER_SPINNERET
	default_accessory_type = /datum/sprite_accessory/spider_spinneret/plain

/datum/preference/choiced/mutant_choice/spider_spinneret/is_part_enabled(datum/preferences/preferences)
	return TRUE

/datum/preference/color/spider_spinneret
	category = PREFERENCE_CATEGORY_SECONDARY_FEATURES
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "spider_spinneret_color"
	relevant_mutant_bodypart = FEATURE_SPIDER_SPINNERET

/datum/preference/color/spider_spinneret/apply_to_human(mob/living/carbon/human/target, value)
	var/datum/mutant_bodypart/mutant_part = target.dna.mutant_bodyparts[FEATURE_SPIDER_SPINNERET]
	if(mutant_part)
		mutant_part.set_primary_color(sanitize_hexcolor(value))

/datum/preference/toggle/emissive/arachnid_part/spider_spinneret
	savefile_key = "spider_spinneret_emissive"
	relevant_mutant_bodypart = FEATURE_SPIDER_SPINNERET
	type_to_check = /datum/preference/choiced/mutant_choice/spider_spinneret

/// === SPIDER MANDIBLES ============================================

/datum/preference/choiced/mutant_choice/spider_mandibles
	savefile_key = "feature_spider_mandibles"
	relevant_mutant_bodypart = FEATURE_SPIDER_MANDIBLES
	default_accessory_type = /datum/sprite_accessory/spider_mandibles/plain

/datum/preference/choiced/mutant_choice/spider_mandibles/is_part_enabled(datum/preferences/preferences)
	return TRUE

/datum/preference/color/spider_mandibles
	category = PREFERENCE_CATEGORY_SECONDARY_FEATURES
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "spider_mandibles_color"
	relevant_mutant_bodypart = FEATURE_SPIDER_MANDIBLES

/datum/preference/color/spider_mandibles/apply_to_human(mob/living/carbon/human/target, value)
	var/datum/mutant_bodypart/mutant_part = target.dna.mutant_bodyparts[FEATURE_SPIDER_MANDIBLES]
	if(mutant_part)
		mutant_part.set_primary_color(sanitize_hexcolor(value))

/datum/preference/toggle/emissive/arachnid_part/spider_mandibles
	savefile_key = "spider_mandibles_emissive"
	relevant_mutant_bodypart = FEATURE_SPIDER_MANDIBLES
	type_to_check = /datum/preference/choiced/mutant_choice/spider_mandibles
