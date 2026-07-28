// MODULE ID: OVERMAP
// Bay-exit / takeoff corridor ignore whitelist.

/datum/unit_test/overmap_bay_exit
	abstract_type = /datum/unit_test/overmap_bay_exit

/datum/unit_test/overmap_bay_exit/ignore_decor

/datum/unit_test/overmap_bay_exit/ignore_decor/Run()
	var/turf/stage = run_loc_floor_bottom_left
	TEST_ASSERT(isfloorturf(stage), "Bay-exit ignore test needs a floor turf.")

	TEST_ASSERT(!overmap_bay_tile_is_wall(stage), "Bare floor should not count as a bay wall.")

	var/obj/structure/closet/blocker = allocate(/obj/structure/closet, stage)
	blocker.anchored = TRUE
	TEST_ASSERT(overmap_bay_tile_is_wall(stage), "Anchored dense closet should block takeoff corridors.")
	qdel(blocker)

	var/obj/structure/fence/chainlink = allocate(/obj/structure/fence, stage)
	TEST_ASSERT(chainlink.density && chainlink.anchored, "Fence fixture should be dense and anchored.")
	TEST_ASSERT(overmap_bay_exit_ignores(chainlink), "Fence should be on GLOB.overmap_bay_exit_ignore.")
	TEST_ASSERT(!overmap_bay_tile_is_wall(stage), "Fences must not block takeoff corridor checks.")
	qdel(chainlink)

	var/obj/structure/railing/wooden_fence/wood = allocate(/obj/structure/railing/wooden_fence, stage)
	TEST_ASSERT(overmap_bay_exit_ignores(wood), "Wooden fence/railing should match railing ignore entry.")
	TEST_ASSERT(!overmap_bay_tile_is_wall(stage), "Railings must not block takeoff corridor checks.")
	qdel(wood)

	// Extensibility: appending a typepath at runtime is honored without rebuild.
	var/obj/structure/closet/crate = allocate(/obj/structure/closet, stage)
	crate.anchored = TRUE
	TEST_ASSERT(overmap_bay_tile_is_wall(stage), "Unlisted dense anchored objects should still block.")
	GLOB.overmap_bay_exit_ignore += /obj/structure/closet
	TEST_ASSERT(overmap_bay_exit_ignores(crate), "Appended typepath should be recognized by overmap_bay_exit_ignores.")
	TEST_ASSERT(!overmap_bay_tile_is_wall(stage), "Appended ignore typepath should bypass bay-exit wall checks.")
	GLOB.overmap_bay_exit_ignore -= /obj/structure/closet
	qdel(crate)
