#define EXPECTED_FLOOR_TYPE /turf/open/floor/iron
#define RESET_TO_EXPECTED(turf) \
	turf.ChangeTurf(EXPECTED_FLOOR_TYPE); \
	turf.assemble_baseturfs(initial(turf.baseturfs))

/datum/unit_test/shuttle_construction
	abstract_type = /datum/unit_test/shuttle_construction

/datum/unit_test/shuttle_construction/proc/reset_shuttle_frame_turf(turf/target)
	var/datum/shuttle_frame/frame = GLOB.shuttle_frames_by_turf[target]
	if(frame)
		// Remove the trait rather than calling frame.remove_turfs() directly: trait removal
		// detaches the construction element while the frame is still registered, whereas a
		// direct removal leaves the element attached with a dangling frame lookup, and the
		// ChangeTurf below then runtimes in pre_turf_changed/Detach/post_turf_changed.
		for(var/turf/frame_turf in frame.turfs.Copy())
			REMOVE_TRAIT(frame_turf, TRAIT_SHUTTLE_CONSTRUCTION_TURF, null)
	for(var/obj/structure/lattice/lattice in target)
		qdel(lattice)
	RESET_TO_EXPECTED(target)

/datum/unit_test/shuttle_construction/proc/find_adjacent_floor(turf/origin)
	for(var/dir in GLOB.cardinals)
		var/turf/check = get_step(origin, dir)
		if(isfloorturf(check))
			return check
	return null

/datum/unit_test/shuttle_construction/proc/prepare_plating(turf/target)
	RESET_TO_EXPECTED(target)
	target.ScrapeAway()
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "[target] should be bare plating after ScrapeAway")
	return target

/datum/unit_test/shuttle_construction/proc/apply_shuttle_rods(turf/open/target, obj/item/stack/rods/shuttle/rods, mob/user)
	TEST_ASSERT(target.build_shuttle_frame_with_rods(rods, user), "build_shuttle_frame_with_rods should succeed on [target.type]")

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	prepare_plating(target)

	var/rod_count = rods.get_amount()
	apply_shuttle_rods(target, rods, user)

	TEST_ASSERT_EQUAL(rods.get_amount(), rod_count - 1, "Shuttle frame rod should be consumed")
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Turf should remain plating after anchoring frame rods")
	TEST_ASSERT(!locate(/obj/structure/lattice) in target, "Frame rods should not spawn a lattice object on plating")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "Plating should have shuttle construction trait")
	TEST_ASSERT(GLOB.shuttle_frames_by_turf[target], "Plating should be registered to a shuttle frame")
	TEST_ASSERT(!target.depth_to_find_baseturf(/turf/baseturf_skipover/shuttle), "Skipover should not be inserted during frame construction")

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating_attackby

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating_attackby/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	prepare_plating(target)

	var/rod_count = rods.get_amount()
	user.put_in_hands(rods, forced = TRUE)
	target.attackby(rods, user)

	TEST_ASSERT_EQUAL(rods.get_amount(), rod_count - 1, "attackby hook should consume a shuttle frame rod")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "attackby hook should mark plating as shuttle frame turf")

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating_attackby/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_tiled_floor

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_tiled_floor/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	RESET_TO_EXPECTED(target)
	TEST_ASSERT(istype(target, EXPECTED_FLOOR_TYPE), "Test turf should start as iron floor")

	apply_shuttle_rods(target, rods, user)

	TEST_ASSERT(istype(target, EXPECTED_FLOOR_TYPE), "Anchoring rods on tiled floor should preserve the original turf type")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "Tiled floor should have shuttle construction trait")

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_tiled_floor/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_trait_survives_tiling

/datum/unit_test/shuttle_construction/shuttle_frame_trait_survives_tiling/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	prepare_plating(target)
	apply_shuttle_rods(target, rods, user)

	var/datum/shuttle_frame/frame = GLOB.shuttle_frames_by_turf[target]
	TEST_ASSERT(frame, "Frame should exist before tiling")

	target = tiles.place_tile(target, user)
	TEST_ASSERT(target, "place_tile should return the new floor turf")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "Shuttle construction trait should survive tiling")
	TEST_ASSERT(GLOB.shuttle_frames_by_turf[target] == frame, "Tiled turf should remain in the same shuttle frame")

/datum/unit_test/shuttle_construction/shuttle_frame_trait_survives_tiling/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_adjacent_merge

/datum/unit_test/shuttle_construction/shuttle_frame_adjacent_merge/Run()
	var/turf/first = run_loc_floor_bottom_left
	var/turf/second = find_adjacent_floor(first)
	TEST_ASSERT(second, "Could not find an adjacent floor turf for merge test")

	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	prepare_plating(first)
	prepare_plating(second)

	apply_shuttle_rods(first, rods, user)
	apply_shuttle_rods(second, rods, user)

	var/datum/shuttle_frame/first_frame = GLOB.shuttle_frames_by_turf[first]
	var/datum/shuttle_frame/second_frame = GLOB.shuttle_frames_by_turf[second]
	TEST_ASSERT(first_frame, "First turf should belong to a shuttle frame")
	TEST_ASSERT(second_frame, "Second turf should belong to a shuttle frame")
	TEST_ASSERT(first_frame == second_frame, "Adjacent frame turfs should merge into one shuttle frame")
	TEST_ASSERT_EQUAL(length(first_frame.turfs), 2, "Merged frame should contain both turfs")

/datum/unit_test/shuttle_construction/shuttle_frame_adjacent_merge/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	var/turf/second = find_adjacent_floor(run_loc_floor_bottom_left)
	if(second)
		reset_shuttle_frame_turf(second)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_rods_reject_duplicate

/datum/unit_test/shuttle_construction/shuttle_frame_rods_reject_duplicate/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	prepare_plating(target)
	apply_shuttle_rods(target, rods, user)

	var/rod_count = rods.get_amount()
	var/datum/shuttle_frame/frame = GLOB.shuttle_frames_by_turf[target]
	TEST_ASSERT(target.build_shuttle_frame_with_rods(rods, user), "Duplicate application should be handled without falling through")
	TEST_ASSERT_EQUAL(rods.get_amount(), rod_count, "Duplicate application should not consume another rod")
	TEST_ASSERT(GLOB.shuttle_frames_by_turf[target] == frame, "Duplicate application should not create a new shuttle frame")

/datum/unit_test/shuttle_construction/shuttle_frame_rods_reject_duplicate/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_regular_rods_unchanged

/datum/unit_test/shuttle_construction/shuttle_frame_regular_rods_unchanged/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/rods = allocate(/obj/item/stack/rods/ten)
	prepare_plating(target)

	user.put_in_hands(rods, forced = TRUE)
	target.attackby(rods, user)

	TEST_ASSERT(!HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "Regular rods should not start shuttle frame construction")
	TEST_ASSERT(!GLOB.shuttle_frames_by_turf[target], "Regular rods should not register a shuttle frame")

/datum/unit_test/shuttle_construction/shuttle_frame_regular_rods_unchanged/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_space_lattice_unchanged

/datum/unit_test/shuttle_construction/shuttle_frame_space_lattice_unchanged/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/original_baseturfs = islist(target.baseturfs) ? target.baseturfs.Copy() : target.baseturfs

	target.ChangeTurf(/turf/open/space, /turf/open/space)
	TEST_ASSERT(istype(target, /turf/open/space), "Test turf should be space")

	var/rod_count = rods.get_amount()
	target.build_with_rods(rods, user)

	TEST_ASSERT_EQUAL(rods.get_amount(), rod_count - 1, "Space should still consume a rod to build a lattice")
	var/obj/structure/lattice/lattice = locate(/obj/structure/lattice) in target
	TEST_ASSERT(lattice, "Shuttle rods on space should still create a lattice")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "Lattice path should mark turf as shuttle construction")

	qdel(lattice)
	target.ChangeTurf(EXPECTED_FLOOR_TYPE, original_baseturfs)
	target.assemble_baseturfs(initial(target.baseturfs))

/datum/unit_test/shuttle_construction/shuttle_frame_space_lattice_unchanged/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_tile_builds_plating

/datum/unit_test/shuttle_construction/shuttle_frame_tile_builds_plating/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	RESET_TO_EXPECTED(target)
	apply_shuttle_rods(target, rods, user)

	var/datum/shuttle_frame/frame = GLOB.shuttle_frames_by_turf[target]
	TEST_ASSERT(frame, "Frame should exist before tile placement")
	TEST_ASSERT(HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Rod source should be present before tile")

	TEST_ASSERT(target.shuttle_frame_build_plating_with_tile(tiles, user), "shuttle_frame_build_plating_with_tile should succeed")
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Tile on rod-frame floor should produce plating, got [target.type]")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "Frame trait should survive plating")
	TEST_ASSERT(!HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Rod source should be cleared after plating")
	TEST_ASSERT(GLOB.shuttle_frames_by_turf[target] == frame, "Turf should remain in the same shuttle frame")
	TEST_ASSERT(!GLOB.shuttle_frame_overlays_by_turf[target], "Rod overlay should be gone after plating")

/datum/unit_test/shuttle_construction/shuttle_frame_tile_builds_plating/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_tile_then_tile

/datum/unit_test/shuttle_construction/shuttle_frame_tile_then_tile/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	prepare_plating(target)
	apply_shuttle_rods(target, rods, user)

	target.shuttle_frame_build_plating_with_tile(tiles, user)
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "First tile should produce plating")

	target = tiles.place_tile(target, user)
	TEST_ASSERT(target, "Second tile (place_tile) should return the new turf")
	TEST_ASSERT(istype(target, EXPECTED_FLOOR_TYPE), "Second tile should produce iron floor via normal place_tile")

/datum/unit_test/shuttle_construction/shuttle_frame_tile_then_tile/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_rcd_builds_plating

/datum/unit_test/shuttle_construction/shuttle_frame_rcd_builds_plating/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	RESET_TO_EXPECTED(target)
	apply_shuttle_rods(target, rods, user)

	var/datum/shuttle_frame/frame = GLOB.shuttle_frames_by_turf[target]
	var/list/rcd_data = list("[RCD_DESIGN_MODE]" = RCD_TURF, "[RCD_DESIGN_PATH]" = /turf/open/floor/plating/rcd)
	TEST_ASSERT(target.shuttle_frame_rcd_act(rcd_data), "shuttle_frame_rcd_act should succeed on rod-frame turf")
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "RCD on rod-frame turf should produce plating, got [target.type]")
	TEST_ASSERT(!iswallturf(target), "RCD should NOT produce a wall on rod-frame turf")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "Frame trait should survive RCD plating")
	TEST_ASSERT(!HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Rod source should be cleared after RCD plating")
	TEST_ASSERT(GLOB.shuttle_frames_by_turf[target] == frame, "Turf should remain in the same shuttle frame")

/datum/unit_test/shuttle_construction/shuttle_frame_rcd_builds_plating/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_space_no_overlay

/datum/unit_test/shuttle_construction/shuttle_frame_space_no_overlay/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	var/original_baseturfs = islist(target.baseturfs) ? target.baseturfs.Copy() : target.baseturfs

	target.ChangeTurf(/turf/open/space, /turf/open/space)
	target.build_with_rods(rods, user)
	TEST_ASSERT(!GLOB.shuttle_frame_overlays_by_turf[target], "Space-lattice path should NOT produce a rod overlay")

	target.build_with_floor_tiles(tiles, user)
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Floor tile on lattice should produce plating")
	TEST_ASSERT(!GLOB.shuttle_frame_overlays_by_turf[target], "Plating built over space lattice should NOT have a rod overlay")

	target.ChangeTurf(EXPECTED_FLOOR_TYPE, original_baseturfs)
	target.assemble_baseturfs(initial(target.baseturfs))

/datum/unit_test/shuttle_construction/shuttle_frame_space_no_overlay/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_station_overlay

/datum/unit_test/shuttle_construction/shuttle_frame_station_overlay/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	RESET_TO_EXPECTED(target)
	apply_shuttle_rods(target, rods, user)

	TEST_ASSERT(GLOB.shuttle_frame_overlays_by_turf[target], "Station rod frame should have the lattice overlay")

	target.shuttle_frame_build_plating_with_tile(tiles, user)
	target = get_turf(target)
	TEST_ASSERT(!GLOB.shuttle_frame_overlays_by_turf[target], "Overlay should be gone after building plating over station rods")

/datum/unit_test/shuttle_construction/shuttle_frame_station_overlay/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_examine_marker

/datum/unit_test/shuttle_construction/shuttle_frame_examine_marker/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	RESET_TO_EXPECTED(target)
	apply_shuttle_rods(target, rods, user)

	var/list/examine_lines = target.examine(user)
	var/found_hint = FALSE
	for(var/line in examine_lines)
		if(findtext(line, "Shuttle frame rods"))
			found_hint = TRUE
			break
	TEST_ASSERT(found_hint, "Examine should contain shuttle frame rod hint on a rod-frame turf")

	target.shuttle_frame_build_plating_with_tile(tiles, user)
	target = get_turf(target)
	examine_lines = target.examine(user)
	found_hint = FALSE
	for(var/line in examine_lines)
		if(findtext(line, "Shuttle frame rods"))
			found_hint = TRUE
			break
	TEST_ASSERT(!found_hint, "Examine should NOT contain shuttle frame rod hint after plating is built")

/datum/unit_test/shuttle_construction/shuttle_frame_examine_marker/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_deconstruct_reexposes_rods

/datum/unit_test/shuttle_construction/shuttle_frame_deconstruct_reexposes_rods/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	RESET_TO_EXPECTED(target)
	apply_shuttle_rods(target, rods, user)

	var/datum/shuttle_frame/frame = GLOB.shuttle_frames_by_turf[target]
	TEST_ASSERT(target.shuttle_frame_build_plating_with_tile(tiles, user), "Should build plating over rods")
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Built layer should be plating")
	TEST_ASSERT(!HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Rod source should be hidden while plating is built")

	target.ScrapeAway()
	target = get_turf(target)
	TEST_ASSERT(HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Deconstructing plating should re-expose the frame rods")
	TEST_ASSERT(GLOB.shuttle_frame_overlays_by_turf[target], "Rod overlay should return after deconstruction")
	TEST_ASSERT(GLOB.shuttle_frames_by_turf[target] == frame, "Re-exposed turf should remain in the same shuttle frame")

	TEST_ASSERT(target.shuttle_frame_build_plating_with_tile(tiles, user), "Should be able to rebuild plating on the re-exposed frame turf")

/datum/unit_test/shuttle_construction/shuttle_frame_deconstruct_reexposes_rods/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_skipover_preserves_landing_pad

/datum/unit_test/shuttle_construction/shuttle_skipover_preserves_landing_pad/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)

	// Station landing pad: iron floor over station plating over space.
	target.ChangeTurf(/turf/open/floor/iron, list(/turf/open/space, /turf/open/floor/plating))
	apply_shuttle_rods(target, rods, user)
	TEST_ASSERT(target.shuttle_frame_build_plating_with_tile(tiles, user), "Should build hull plating over station rods")
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Hull layer should be plating")

	insert_shuttle_skipover(target)
	TEST_ASSERT_EQUAL(target.depth_to_find_baseturf(/turf/baseturf_skipover/shuttle), 1, "Skipover should sit directly beneath the hull plating, not under the station floors")
	var/list/stack = target.baseturfs
	TEST_ASSERT_EQUAL(stack[length(stack) - 1], /turf/open/floor/iron, "Station floor should remain below the skipover")

	// Idempotent: a second call must not stack another skipover.
	insert_shuttle_skipover(target)
	var/skipover_count = 0
	for(var/base in target.baseturfs)
		if(base == /turf/baseturf_skipover/shuttle)
			skipover_count++
	TEST_ASSERT_EQUAL(skipover_count, 1, "Repeated skipover insertion should be idempotent")

/datum/unit_test/shuttle_construction/shuttle_skipover_preserves_landing_pad/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_skipover_tiled_hull

/datum/unit_test/shuttle_construction/shuttle_skipover_tiled_hull/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)

	// Station pad, hull plating built over rods, then hull floor tiled on top.
	target.ChangeTurf(/turf/open/floor/iron, list(/turf/open/space, /turf/open/floor/plating))
	apply_shuttle_rods(target, rods, user)
	TEST_ASSERT(target.shuttle_frame_build_plating_with_tile(tiles, user), "Should build hull plating over station rods")
	target = get_turf(target)
	target = tiles.place_tile(target, user)
	TEST_ASSERT(target, "place_tile should return the tiled hull floor")

	insert_shuttle_skipover(target)
	TEST_ASSERT_EQUAL(target.depth_to_find_baseturf(/turf/baseturf_skipover/shuttle), 2, "Skipover should sit beneath the hull plating (depth 2 under a tiled hull)")
	var/list/stack = target.baseturfs
	TEST_ASSERT_EQUAL(stack[length(stack)], /turf/open/floor/plating, "Hull plating should be above the skipover")
	TEST_ASSERT_EQUAL(stack[length(stack) - 2], /turf/open/floor/iron, "Station floor should remain below the skipover")

/datum/unit_test/shuttle_construction/shuttle_skipover_tiled_hull/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_skipover_space_build

/datum/unit_test/shuttle_construction/shuttle_skipover_space_build/Run()
	var/turf/open/target = run_loc_floor_bottom_left

	// Space build: bare hull plating straight over space.
	target.ChangeTurf(/turf/open/floor/plating, list(/turf/open/space))
	insert_shuttle_skipover(target)
	TEST_ASSERT_EQUAL(target.depth_to_find_baseturf(/turf/baseturf_skipover/shuttle), 1, "Skipover should sit directly beneath bare hull plating")
	var/list/stack = target.baseturfs
	TEST_ASSERT_EQUAL(stack[1], /turf/open/space, "Space should remain the bottom of the stack")

/datum/unit_test/shuttle_construction/shuttle_skipover_space_build/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_plating_pad_reexposes_rods

/datum/unit_test/shuttle_construction/shuttle_frame_plating_pad_reexposes_rods/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	prepare_plating(target)
	apply_shuttle_rods(target, rods, user)

	var/datum/shuttle_frame/frame = GLOB.shuttle_frames_by_turf[target]
	TEST_ASSERT(frame, "Frame should exist on plating pad before hull plating")
	TEST_ASSERT(target.shuttle_frame_build_plating_with_tile(tiles, user), "Should build hull plating over plating-pad rods")
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Hull layer should be plating")
	TEST_ASSERT(!HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Rod source should be hidden under hull plating")

	target.ScrapeAway()
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Scraping hull should restore landing-pad plating")
	TEST_ASSERT(HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Hull scrape onto pad plating should re-expose frame rods")
	TEST_ASSERT(GLOB.shuttle_frame_overlays_by_turf[target], "Rod overlay should return after hull scrape onto pad plating")
	TEST_ASSERT(GLOB.shuttle_frames_by_turf[target] == frame, "Re-exposed plating pad should remain in the same shuttle frame")

/datum/unit_test/shuttle_construction/shuttle_frame_plating_pad_reexposes_rods/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_tile_scrape_keeps_rods_hidden

/datum/unit_test/shuttle_construction/shuttle_frame_tile_scrape_keeps_rods_hidden/Run()
	var/turf/open/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/stack/tile/iron/tiles = allocate(/obj/item/stack/tile/iron/fifty)
	prepare_plating(target)
	apply_shuttle_rods(target, rods, user)

	TEST_ASSERT(target.shuttle_frame_build_plating_with_tile(tiles, user), "Should build hull plating over rods")
	target = get_turf(target)
	target = tiles.place_tile(target, user)
	TEST_ASSERT(target, "place_tile should return the tiled hull floor")
	TEST_ASSERT(istype(target, EXPECTED_FLOOR_TYPE), "Hull should be tiled iron")
	TEST_ASSERT(!HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Rods stay hidden under tiled hull")

	target.ScrapeAway()
	target = get_turf(target)
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Scraping the tile should leave hull plating")
	TEST_ASSERT(!HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Tile scrape onto hull plating must not re-expose rods")
	TEST_ASSERT(!GLOB.shuttle_frame_overlays_by_turf[target], "Rod overlay must stay cleared under hull plating")

/datum/unit_test/shuttle_construction/shuttle_frame_tile_scrape_keeps_rods_hidden/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_cut_rods_with_wirecutter

/datum/unit_test/shuttle_construction/shuttle_frame_cut_rods_with_wirecutter/Run()
	var/turf/open/floor/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	var/obj/item/wirecutters/cutters = allocate(/obj/item/wirecutters)
	prepare_plating(target)
	target = get_turf(target)
	apply_shuttle_rods(target, rods, user)

	TEST_ASSERT(HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Rods should be exposed before cutting")
	TEST_ASSERT(GLOB.shuttle_frame_overlays_by_turf[target], "Rod overlay should exist before cutting")

	user.put_in_hands(cutters, forced = TRUE)
	TEST_ASSERT(istype(target, /turf/open/floor), "Cut target should remain a floor turf")
	TEST_ASSERT(target.cut_shuttle_frame_rods(user, cutters), "cut_shuttle_frame_rods should handle exposed rods")

	TEST_ASSERT(!HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE), "Wirecutters should remove the rod trait source")
	TEST_ASSERT(!GLOB.shuttle_frame_overlays_by_turf[target], "Rod overlay should be cleared after cutting")
	var/obj/item/stack/rods/shuttle/dropped = locate(/obj/item/stack/rods/shuttle) in target
	TEST_ASSERT(dropped, "Cutting rods should drop a shuttle frame rod")
	TEST_ASSERT_EQUAL(dropped.get_amount(), 1, "Cutting should yield exactly one shuttle frame rod")

/datum/unit_test/shuttle_construction/shuttle_frame_cut_rods_with_wirecutter/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_reorient_direction

/datum/unit_test/shuttle_construction/shuttle_reorient_direction/proc/restore_testroom_areas(list/turf/hull_turfs)
	var/area/testroom = GLOB.areas_by_type[/area/misc/testroom]
	if(!testroom)
		return
	var/list/orphan_shuttle_areas = list()
	for(var/turf/hull as anything in hull_turfs)
		if(!hull)
			continue
		var/area/current = get_area(hull)
		if(istype(current, /area/shuttle) && current != testroom)
			orphan_shuttle_areas[current] = TRUE
		if(current != testroom)
			set_turf_to_area(hull, testroom)
	for(var/area/shuttle_area as anything in orphan_shuttle_areas)
		if(!QDELETED(shuttle_area) && !shuttle_area.has_contained_turfs())
			qdel(shuttle_area)

/datum/unit_test/shuttle_construction/shuttle_reorient_direction/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/neighbor = get_step(origin, EAST)
	TEST_ASSERT(neighbor, "Need an adjacent turf for a two-tile shuttle")
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/list/turfs = list(origin, neighbor)

	var/obj/docking_port/mobile/custom/shuttle = create_shuttle(
		user,
		origin,
		turfs.Copy(),
		list(),
		WEST,
		WEST,
		name = "Reorient Test Shuttle",
		id = "test_reorient_shuttle",
	)
	TEST_ASSERT(istype(shuttle), "create_shuttle should return a custom mobile port")
	TEST_ASSERT_EQUAL(shuttle.dir, WEST, "Build direction should set mobile port dir")
	TEST_ASSERT_EQUAL(shuttle.preferred_direction, WEST, "Build direction should set preferred_direction")
	TEST_ASSERT_EQUAL(shuttle.port_direction, SOUTH, "Matching port/shuttle dirs yield SOUTH port_direction")

	TEST_ASSERT(reorient_custom_shuttle(shuttle, SOUTH), "reorient_custom_shuttle should succeed while idle")
	TEST_ASSERT_EQUAL(shuttle.dir, SOUTH, "Reorient should update dir")
	TEST_ASSERT_EQUAL(shuttle.preferred_direction, SOUTH, "Reorient should update preferred_direction")
	TEST_ASSERT_EQUAL(shuttle.port_direction, SOUTH, "Reorient with matching dirs keeps SOUTH port_direction")

	var/obj/docking_port/stationary/docked = shuttle.get_docked()
	if(docked)
		TEST_ASSERT_EQUAL(docked.dir, SOUTH, "Docked stationary port should sync dir")
		TEST_ASSERT_EQUAL(docked.width, shuttle.width, "Docked stationary port should sync width")
		TEST_ASSERT_EQUAL(docked.height, shuttle.height, "Docked stationary port should sync height")

	TEST_ASSERT(!reorient_custom_shuttle(shuttle, 5), "Non-cardinal dirs should be rejected")

	// Soft qdel leaves docking_ports alive (parent returns QDEL_HINT_LETMELIVE),
	// and create_shuttle reparents turfs into /area/shuttle/custom. Both poison
	// later tests (unregister spam + maptest_area_contents).
	restore_testroom_areas(turfs)
	qdel(shuttle, force = TRUE)
	if(!QDELETED(docked))
		qdel(docked, force = TRUE)

/datum/unit_test/shuttle_construction/shuttle_reorient_direction/Destroy()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/neighbor = get_step(origin, EAST)
	restore_testroom_areas(list(origin, neighbor))
	reset_shuttle_frame_turf(origin)
	if(neighbor)
		reset_shuttle_frame_turf(neighbor)
	// Force-clear any leftover ports soft-qdel left behind on these turfs.
	for(var/turf/hull as anything in list(origin, neighbor))
		if(!hull)
			continue
		for(var/obj/docking_port/port in hull)
			qdel(port, force = TRUE)
	return ..()

#undef RESET_TO_EXPECTED
#undef EXPECTED_FLOOR_TYPE
