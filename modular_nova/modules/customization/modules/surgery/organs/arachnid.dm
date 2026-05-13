// Eyes, tongue, and the three external mutant body part organs (legs, spinneret,
// mandibles) for the Arachnid species.

/// Spider eyes - basic night vision, light sensitive (mirrors the Whitesands species).
/obj/item/organ/eyes/night_vision/spider
	name = "spider eyes"
	desc = "These compound eyes seem to have heightened sensitivity to bright light, offset by basic night vision."
	icon_state = "eyeballs"
	flash_protect = FLASH_PROTECTION_SENSITIVE
	low_light_cutoff = list(10, 15, 20)
	medium_light_cutoff = list(15, 20, 30)
	high_light_cutoff = list(30, 35, 50)

/// Inner mandibles tongue - allows speaking the racial languages.
/// Foodtype bitfields here are the modern equivalent of the WS-era
/// `liked_food` / `disliked_food` / `toxic_food` species vars; they drive both
/// food reactions when eating and the diet card in the prefs UI via
/// /datum/species/get_species_diet().
/obj/item/organ/tongue/spider
	name = "inner mandible"
	desc = "A set of soft, spoon-esque mandibles closer to the mouth opening, that allow for basic speech and the ability to speak Rachnidian."
	say_mod = "chitters"
	taste_sensitivity = 25 // bug-style chemoreception, slightly sharper than the human default
	liked_foodtypes = MEAT | RAW
	disliked_foodtypes = FRUIT | GROSS
	toxic_foodtypes = VEGETABLES | DAIRY | CLOTH

/obj/item/organ/tongue/spider/get_possible_languages()
	return ..() + list(
		/datum/language/rachnidian,
		/datum/language/buzzwords,
	)

/// === SPIDER LEGS - extra layered limbs that ride along the chest ===
/obj/item/organ/spider_legs
	name = "spider legs"
	desc = "A bristled cluster of arachnid limbs - decorative on humans, load-bearing on those born to carry them."
	icon = 'icons/obj/medical/organs/organs.dmi'
	icon_state = "spinalcord"
	zone = BODY_ZONE_CHEST
	slot = ORGAN_SLOT_EXTERNAL_SPIDER_LEGS
	mutantpart_key = FEATURE_SPIDER_LEGS
	bodypart_overlay = /datum/bodypart_overlay/mutant/spider_legs
	organ_flags = parent_type::organ_flags | ORGAN_EXTERNAL

/datum/bodypart_overlay/mutant/spider_legs
	layers = EXTERNAL_BEHIND | EXTERNAL_ADJACENT
	feature_key = FEATURE_SPIDER_LEGS
	color_source = ORGAN_COLOR_OVERRIDE

/datum/bodypart_overlay/mutant/spider_legs/get_global_feature_list()
	return SSaccessories.sprite_accessories[FEATURE_SPIDER_LEGS]

/datum/bodypart_overlay/mutant/spider_legs/override_color(rgb_value)
	return draw_color

/datum/bodypart_overlay/mutant/spider_legs/can_draw_on_bodypart(obj/item/bodypart/bodypart_owner, mob/living/carbon/owner, is_husked = FALSE)
	if(!..())
		return FALSE
	var/mob/living/carbon/human/wearer = bodypart_owner.owner
	if(istype(wearer) && (feature_key in wearer.try_hide_mutant_parts))
		return FALSE
	return TRUE

/// === SPIDER SPINNERET - rear-mounted silk-spinning organ ===
/obj/item/organ/spider_spinneret
	name = "spinneret"
	desc = "A bulbous, silk-spinning organ. Smells faintly sweet."
	icon = 'icons/obj/medical/organs/organs.dmi'
	icon_state = "stomach"
	zone = BODY_ZONE_CHEST
	slot = ORGAN_SLOT_EXTERNAL_SPIDER_SPINNERET
	mutantpart_key = FEATURE_SPIDER_SPINNERET
	bodypart_overlay = /datum/bodypart_overlay/mutant/spider_spinneret
	organ_flags = parent_type::organ_flags | ORGAN_EXTERNAL

/datum/bodypart_overlay/mutant/spider_spinneret
	layers = EXTERNAL_FRONT
	feature_key = FEATURE_SPIDER_SPINNERET
	color_source = ORGAN_COLOR_OVERRIDE

/datum/bodypart_overlay/mutant/spider_spinneret/get_global_feature_list()
	return SSaccessories.sprite_accessories[FEATURE_SPIDER_SPINNERET]

/datum/bodypart_overlay/mutant/spider_spinneret/override_color(rgb_value)
	return draw_color

/datum/bodypart_overlay/mutant/spider_spinneret/can_draw_on_bodypart(obj/item/bodypart/bodypart_owner, mob/living/carbon/owner, is_husked = FALSE)
	if(!..())
		return FALSE
	var/mob/living/carbon/human/wearer = bodypart_owner.owner
	if(istype(wearer) && (feature_key in wearer.try_hide_mutant_parts))
		return FALSE
	return TRUE

/// === SPIDER MANDIBLES - face attachment, draws on the head ===
/obj/item/organ/spider_mandibles
	name = "outer mandibles"
	desc = "A pair of chitinous mandibles, useful for posturing and intimidation."
	icon = 'icons/obj/medical/organs/organs.dmi'
	icon_state = "tongue"
	zone = BODY_ZONE_HEAD
	slot = ORGAN_SLOT_EXTERNAL_SPIDER_MANDIBLES
	mutantpart_key = FEATURE_SPIDER_MANDIBLES
	bodypart_overlay = /datum/bodypart_overlay/mutant/spider_mandibles
	organ_flags = parent_type::organ_flags | ORGAN_EXTERNAL

/datum/bodypart_overlay/mutant/spider_mandibles
	layers = EXTERNAL_FRONT
	feature_key = FEATURE_SPIDER_MANDIBLES
	color_source = ORGAN_COLOR_OVERRIDE

/datum/bodypart_overlay/mutant/spider_mandibles/get_global_feature_list()
	return SSaccessories.sprite_accessories[FEATURE_SPIDER_MANDIBLES]

/datum/bodypart_overlay/mutant/spider_mandibles/override_color(rgb_value)
	return draw_color

/datum/bodypart_overlay/mutant/spider_mandibles/can_draw_on_bodypart(obj/item/bodypart/bodypart_owner, mob/living/carbon/owner, is_husked = FALSE)
	if(!..())
		return FALSE
	var/mob/living/carbon/human/wearer = bodypart_owner.owner
	if(istype(wearer) && (feature_key in wearer.try_hide_mutant_parts))
		return FALSE
	// Snouts and the like already mark a head as obscuring its mouth, but
	// mandibles are mostly unobstructed - keep the visibility check simple.
	return !(bodypart_owner.owner?.obscured_slots & HIDESNOUT)
