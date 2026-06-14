// Mutation toxin and slime-extract synthesis recipe for the Arachnid species.
// Follows the modern Blastwave/Nova reagent registration pattern (mirrors the
// other slime-green driven race-shifting toxins in
// code/modules/reagents/chemistry/recipes/slime_extracts.dm).

/datum/reagent/mutationtoxin/arachnid
	name = "Arachnid Mutation Toxin"
	description = "A glowing, faintly silken toxin."
	color = "#5EFF3B"
	race = /datum/species/arachnid
	taste_description = "silk"
	chemical_flags = REAGENT_CAN_BE_SYNTHESIZED
	randomized_spawns = REAGENT_SPAWN_ALL_RANDOM_SPAWNS
	process_flags = REAGENT_ORGANIC | REAGENT_SYNTHETIC

/datum/chemical_reaction/slime/slimearachnid
	results = list(/datum/reagent/mutationtoxin/arachnid = 1)
	required_reagents = list(/datum/reagent/spider_extract = 1)
	required_container = /obj/item/slime_extract/green
