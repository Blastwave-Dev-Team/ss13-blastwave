/datum/area_spawn/character_atm
	target_areas = list(
		/area/station/hallway/secondary/entry,
		/area/station/commons/lounge,
		/area/station/hallway/primary/central,
	)
	desired_atom = /obj/machinery/atm
	mode = AREA_SPAWN_MODE_HUG_WALL
	blacklisted_stations = list(
		"Void Raptor",
		"Ouroboros",
		"Snowglobe Station",
		"Runtime Station",
		"MultiZ Debug",
		"Gateway Test",
		"Blueshift",
		"Pubby Station",
		"SerenityStation",
		"Minimal Runtime Station",
		"MetaStation",
		"Delta Station",
		"Ice Box Station",
		"Tramstation",
		"Wawastation",
		"NebulaStation",
		"Catwalk Station",
	)
