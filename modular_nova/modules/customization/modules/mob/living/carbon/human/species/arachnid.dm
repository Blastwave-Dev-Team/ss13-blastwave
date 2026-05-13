// =============================================================================
// Arachnid species. Modernized port of the Whitesands Rachnid (Arachnid) species
// onto the Blastwave/Nova customization framework.
//
// Key changes from the original:
//   * Old `mutant_bodyparts = list("spider_legs", ...)` map replaced with
//     external organs + sprite_accessory subtypes registered through
//     SSaccessories (see modules/surgery/organs/arachnid.dm and
//     modules/mob/dead/new_player/sprite_accessories/species/arachnid.dm).
//   * Web-walking and web-salvaging covered by the modern TRAIT_WEB_SURFER /
//     TRAIT_WEB_WEAVER traits (see code/game/objects/effects/spiderwebs.dm).
//   * Active web/cocoon spinning is granted by the spinneret organ as
//     /datum/action/cooldown/mob_cooldown/{lay_web,wrap}/arachnid - lose the
//     spinneret, lose the abilities. See surgery/organs/arachnid_silk.dm.
//   * Flyswatter weakness migrated from `check_species_weakness` to the
//     COMSIG_ATOM_ATTACKBY signal hook used by /datum/species/moth and
//     /datum/species/fly.
//   * Pesticide weakness intentionally NOT given a custom override - the base
//     /datum/reagent/toxin/pestkiller already deals tox damage to MOB_BUG mobs.
//   * Modern `get_species_description` / `get_species_lore` /
//     `get_physical_attributes` / perks pipeline used in place of the bare
//     `loreblurb` var.
//   * WS-era species-level `liked_food`/`disliked_food`/`toxic_food` moved onto
//     /obj/item/organ/tongue/spider as the modern foodtype bitfields.
// =============================================================================

/mob/living/carbon/human/species/arachnid
	race = /datum/species/arachnid

/datum/species/arachnid
	name = "Arachnid"
	plural_form = "Arachnids"
	id = SPECIES_ARACHNID
	inherent_traits = list(
		TRAIT_ADVANCEDTOOLUSER,
		TRAIT_CAN_STRIP,
		TRAIT_LITERATE,
		TRAIT_MUTANT_COLORS,
		TRAIT_NO_UNDERWEAR,
		TRAIT_WEB_WEAVER,
		TRAIT_WEB_SURFER,
	)
	// MOB_BUG is what causes pestkiller to deal extra tox damage in
	// /datum/reagent/toxin/pestkiller/on_mob_life - no species-specific override needed.
	inherent_biotypes = MOB_ORGANIC|MOB_HUMANOID|MOB_BUG
	meat = /obj/item/food/meat/slab/spider
	mutanteyes = /obj/item/organ/eyes/night_vision/spider
	mutanttongue = /obj/item/organ/tongue/spider
	// Reuse the existing roach DNA-infuser organs for chitinous guts.
	// Stomach: ignores disgust, slightly worse reagent absorption, hungrier.
	// Liver:   higher tox tolerance but doubles tox damage if it gets through.
	// Appendix: cannot become inflamed.
	mutantstomach = /obj/item/organ/stomach/roach
	mutantliver = /obj/item/organ/liver/roach
	mutantappendix = /obj/item/organ/appendix/roach
	species_language_holder = /datum/language_holder/arachnid
	changesource_flags = MIRROR_BADMIN | WABBAJACK | MIRROR_MAGIC | MIRROR_PRIDE | ERT_SPAWN | RACE_SWAP | SLIME_EXTRACT
	payday_modifier = 1.0

/datum/species/arachnid/get_default_mutant_bodyparts()
	return list(
		FEATURE_SPIDER_LEGS = MUTPART_BLUEPRINT("Plain", is_randomizable = FALSE),
		FEATURE_SPIDER_SPINNERET = MUTPART_BLUEPRINT("Plain", is_randomizable = FALSE),
		FEATURE_SPIDER_MANDIBLES = MUTPART_BLUEPRINT("Plain", is_randomizable = FALSE),
		FEATURE_TAIL = MUTPART_BLUEPRINT(SPRITE_ACCESSORY_NONE, is_randomizable = FALSE),
		FEATURE_WINGS = MUTPART_BLUEPRINT(SPRITE_ACCESSORY_NONE, is_randomizable = FALSE),
		FEATURE_LEGS = MUTPART_BLUEPRINT(NORMAL_LEGS, is_randomizable = FALSE, is_feature = TRUE),
	)

/datum/species/arachnid/get_species_description()
	return "Arachnids are a competitive, hardworking offshoot of arthropoid life that have integrated themselves \
		into Nanotrasen's workforce in steadily growing numbers. Their males are diligent and well-tempered employees, \
		while their voracious females remain largely independent of the wider galactic order."

/datum/species/arachnid/get_physical_attributes()
	return "Arachnids have basic low-light vision but are easily flashed, and a chitinous bug physiology - \
		hardier guts but a violent reaction to pesticides and flyswatters. They prefer raw meat and find most \
		vegetable matter, dairy, and cloth outright toxic."

/datum/species/arachnid/get_species_lore()
	return list(
		"Arachnids evolved on a competitive world that selected aggressively for tireless work ethic. \
		The result is a humanoid arthropod species that genuinely seems to enjoy long shifts, complex tasks, \
		and tight deadlines - traits that have made them a popular hire on stations near independent Arachnid civilizations.",

		"While their males have integrated easily into mixed-species crews, the dominant females have so far refused most \
		offers of integration, often violently. NT recruiters now operate under standing orders to extend employment offers \
		only to males.",

		"All Arachnids share a fondness for raw meat, a wariness of vegetable matter, and a deep-seated dislike of being \
		swatted at. Most also retain functional spinnerets and outer mandibles, even after being absorbed into station life.",
	)

/datum/species/arachnid/create_pref_unique_perks()
	var/list/to_add = list()
	to_add += list(
		list(
			SPECIES_PERK_TYPE = SPECIES_POSITIVE_PERK,
			SPECIES_PERK_ICON = FA_ICON_SPIDER,
			SPECIES_PERK_NAME = "Web Walker",
			SPECIES_PERK_DESC = "Arachnids walk through sticky spider webs without getting caught and can salvage existing webs into raw cloth.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_POSITIVE_PERK,
			SPECIES_PERK_ICON = FA_ICON_SPIDER,
			SPECIES_PERK_NAME = "Silk Spinner",
			SPECIES_PERK_DESC = "A working spinneret organ grants two abilities: spin a sticky web on your tile, or wrap an adjacent target into a cocoon. Both cost a long uninterrupted weave AND a chunk of nutrition - moving cancels the weave. Lose the spinneret, lose the abilities.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_POSITIVE_PERK,
			SPECIES_PERK_ICON = FA_ICON_EYE,
			SPECIES_PERK_NAME = "Compound Eyes",
			SPECIES_PERK_DESC = "Arachnid compound eyes grant basic low-light vision.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
			SPECIES_PERK_ICON = FA_ICON_DRUMSTICK_BITE,
			SPECIES_PERK_NAME = "Carnivorous Palate",
			SPECIES_PERK_DESC = "Arachnids prefer raw meat and find cloth, dairy, and most vegetables outright toxic.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEGATIVE_PERK,
			SPECIES_PERK_ICON = FA_ICON_SUN,
			SPECIES_PERK_NAME = "Light Sensitive",
			SPECIES_PERK_DESC = "Arachnid eyes are easily flashed - protective eyewear is recommended.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEGATIVE_PERK,
			SPECIES_PERK_ICON = FA_ICON_HAND_HOLDING,
			SPECIES_PERK_NAME = "Splat Risk",
			SPECIES_PERK_DESC = "Arachnids take massively increased damage from flyswatters.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEGATIVE_PERK,
			SPECIES_PERK_ICON = FA_ICON_SPRAY_CAN,
			SPECIES_PERK_NAME = "Pesticide Aversion",
			SPECIES_PERK_DESC = "As bug-biotype creatures, Arachnids take heavy toxin damage from pest killer reagents.",
		),
		list(
			SPECIES_PERK_TYPE = SPECIES_NEUTRAL_PERK,
			SPECIES_PERK_ICON = FA_ICON_BUG,
			SPECIES_PERK_NAME = "Chitinous Guts",
			SPECIES_PERK_DESC = "Roach-like internal organs let Arachnids ignore disgust and shrug off appendicitis, but their \
				livers double the damage of any toxins that slip past them - and they get hungry fast.",
		),
	)
	return to_add

/datum/species/arachnid/prepare_human_for_preview(mob/living/carbon/human/preview)
	preview.dna.features[FEATURE_MUTANT_COLOR] = "#00FF00"
	preview.dna.features[FEATURE_MUTANT_COLOR_TWO] = "#00FF00"
	preview.dna.features[FEATURE_MUTANT_COLOR_THREE] = "#00FF00"
	preview.dna.features[FEATURE_LEGS] = NORMAL_LEGS
	preview.dna.mutant_bodyparts[FEATURE_SPIDER_LEGS] = build_mutant_part("Plain", list("#00FF00"))
	preview.dna.mutant_bodyparts[FEATURE_SPIDER_SPINNERET] = build_mutant_part("Plain", list("#00FF00"))
	preview.dna.mutant_bodyparts[FEATURE_SPIDER_MANDIBLES] = build_mutant_part("Plain", list("#00FF00"))
	regenerate_organs(preview, src, visual_only = TRUE)
	preview.update_body(TRUE)

/datum/species/arachnid/randomize_features()
	var/list/features = ..()
	// Future-proofs against multi-color sprite variants by seeding all three slots
	// the way akula/tajaran do, even if our current accessories only sample COLOR.
	var/picked_color = pick("#00FF00", "#3DAB1F", "#7FBF34", "#1F6E0E")
	features[FEATURE_MUTANT_COLOR] = picked_color
	features[FEATURE_MUTANT_COLOR_TWO] = picked_color
	features[FEATURE_MUTANT_COLOR_THREE] = picked_color
	return features

// Random Arachnid name helper (kept as a /proc/ for legacy callers; the species
// itself relies on the language-holder driven generate_random_name_species_based()
// path which will hit /datum/language/rachnidian/get_random_name).
/proc/random_unique_arachnid_name(attempts_to_find_unique_name = 10)
	for(var/i in 1 to attempts_to_find_unique_name)
		. = "[capitalize(pick(GLOB.rachnid_first_names))] [capitalize(pick(GLOB.rachnid_last_names))]"
		if(!findname(.))
			break

/datum/species/arachnid/on_species_gain(mob/living/carbon/human/gainer, datum/species/old_species, pref_load, regenerate_icons)
	. = ..()
	RegisterSignal(gainer, COMSIG_ATOM_ATTACKBY, PROC_REF(on_attackby))

/datum/species/arachnid/on_species_loss(mob/living/carbon/human/loser, datum/species/new_species, pref_load)
	. = ..()
	UnregisterSignal(loser, COMSIG_ATOM_ATTACKBY)

/datum/species/arachnid/proc/on_attackby(mob/living/source, obj/item/attacking_item, mob/living/attacker, list/modifiers, list/attack_modifiers)
	SIGNAL_HANDLER
	if(istype(attacking_item, /obj/item/melee/flyswatter))
		MODIFY_ATTACK_FORCE_MULTIPLIER(attack_modifiers, 9) // matches the Whitesands 9x flyswatter weakness
