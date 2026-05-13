// Sprite accessories for the Arachnid species' three signature mutant body parts.
// Icon files retain the original Whitesands artwork; the icon-state names there
// already follow the modern "m_<key>_<state>_<layer>" convention used by
// /datum/bodypart_overlay/mutant/get_image(), so the keys below MUST match the
// icon-state prefixes (FEATURE_SPIDER_LEGS = "spider_legs" etc.).

/// === SPIDER LEGS ===
/datum/sprite_accessory/spider_legs
	key = FEATURE_SPIDER_LEGS
	icon = 'modular_nova/master_files/icons/mob/sprite_accessory/species/spider_legs.dmi'
	color_src = USE_ONE_COLOR
	relevent_layers = list(BODY_BEHIND_LAYER, BODY_ADJ_LAYER)
	organ_type = /obj/item/organ/spider_legs

/datum/sprite_accessory/spider_legs/none
	name = SPRITE_ACCESSORY_NONE
	icon_state = "none"
	color_src = null
	factual = FALSE
	natural_spawn = FALSE

/datum/sprite_accessory/spider_legs/plain
	name = "Plain"
	icon_state = "plain"

/datum/sprite_accessory/spider_legs/fuzzy
	name = "Fuzzy"
	icon_state = "fuzzy"

/datum/sprite_accessory/spider_legs/spiky
	name = "Spiky"
	icon_state = "spiky"

/// === SPIDER SPINNERET ===
/datum/sprite_accessory/spider_spinneret
	key = FEATURE_SPIDER_SPINNERET
	icon = 'modular_nova/master_files/icons/mob/sprite_accessory/species/spider_spinneret.dmi'
	color_src = USE_ONE_COLOR
	relevent_layers = list(BODY_FRONT_LAYER)
	organ_type = /obj/item/organ/spider_spinneret

/datum/sprite_accessory/spider_spinneret/none
	name = SPRITE_ACCESSORY_NONE
	icon_state = "none"
	color_src = null
	factual = FALSE
	natural_spawn = FALSE

/datum/sprite_accessory/spider_spinneret/plain
	name = "Plain"
	icon_state = "plain"

/datum/sprite_accessory/spider_spinneret/fuzzy
	name = "Fuzzy"
	icon_state = "fuzzy"

/datum/sprite_accessory/spider_spinneret/blackwidow
	name = "Black Widow"
	icon_state = "blackwidow"

/// === SPIDER MANDIBLES ===
/datum/sprite_accessory/spider_mandibles
	key = FEATURE_SPIDER_MANDIBLES
	icon = 'modular_nova/master_files/icons/mob/sprite_accessory/species/spider_mandibles.dmi'
	color_src = USE_ONE_COLOR
	relevent_layers = list(BODY_FRONT_LAYER)
	organ_type = /obj/item/organ/spider_mandibles

/datum/sprite_accessory/spider_mandibles/none
	name = SPRITE_ACCESSORY_NONE
	icon_state = "none"
	color_src = null
	factual = FALSE
	natural_spawn = FALSE

/datum/sprite_accessory/spider_mandibles/plain
	name = "Plain"
	icon_state = "plain"

/datum/sprite_accessory/spider_mandibles/fuzzy
	name = "Fuzzy"
	icon_state = "fuzzy"

/datum/sprite_accessory/spider_mandibles/spiky
	name = "Spiky"
	icon_state = "spiky"
