/// Returns true if the map we're playing on is on a planet, but it DOES have space access.
/datum/controller/subsystem/mapping/proc/is_planetary_with_space()
	return is_planetary() && current_map.allow_space_when_planetary


/datum/map_config
	/// Are we allowing space even if we're planetary?
	var/allow_space_when_planetary = FALSE
	/// When TRUE, SSovermap owns space ruin spawning instead of SSmapping.
	/// Set via map JSON ("overmap_space_ruins": true). Defaults FALSE so
	/// non-overmap stations keep normal behavior.
	var/overmap_space_ruins = FALSE

/datum/controller/subsystem/mapping/setup_ruins()
	// Skip space ruin seeding when the overmap subsystem handles it.
	if(!current_map.overmap_space_ruins)
		var/list/space_ruins = levels_by_trait(ZTRAIT_SPACE_RUINS)
		if(space_ruins.len)
			var/proportional_budget = round(CONFIG_GET(number/space_budget) * (space_ruins.len / DEFAULT_SPACE_RUIN_LEVELS))
			seedRuins(space_ruins, proportional_budget, list(/area/space), themed_ruins[ZTRAIT_SPACE_RUINS], mineral_budget = 0, ruins_type = ZTRAIT_SPACE_RUINS)

	// Jungle Ruins, Serenity
	var/list/jungle_ruins = levels_by_trait(ZTRAIT_JUNGLE_RUINS)
	if(jungle_ruins.len)
		seedRuins(jungle_ruins, CONFIG_GET(number/jungle_budget), list(/area/forestplanet/outdoors/unexplored), themed_ruins[ZTRAIT_JUNGLE_RUINS], clear_below = TRUE)

	// Jungle Cave Ruins, Serenity
	var/list/jungle_cave_ruins = levels_by_trait(ZTRAIT_JUNGLE_CAVE_RUINS)
	if(jungle_cave_ruins.len)
		seedRuins(jungle_ruins, CONFIG_GET(number/jungle_cave_budget), list(/area/forestplanet/outdoors/unexplored/deep), themed_ruins[ZTRAIT_JUNGLE_CAVE_RUINS], clear_below = TRUE)
	return ..()
