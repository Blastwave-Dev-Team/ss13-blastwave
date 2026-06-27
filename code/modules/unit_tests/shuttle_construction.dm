#define EXPECTED_FLOOR_TYPE /turf/open/floor/iron
#define RESET_TO_EXPECTED(turf) \
	turf.ChangeTurf(EXPECTED_FLOOR_TYPE); \
	turf.assemble_baseturfs(initial(turf.baseturfs))

/datum/unit_test/shuttle_construction
	abstract_type = /datum/unit_test/shuttle_construction

/datum/unit_test/shuttle_construction/proc/reset_shuttle_frame_turf(turf/target)
	var/datum/shuttle_frame/frame = GLOB.shuttle_frames_by_turf[target]
	if(frame)
		frame.remove_turfs(frame.turfs.Copy())
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

/datum/unit_test/shuttle_construction/proc/apply_shuttle_rods(turf/target, obj/item/stack/rods/shuttle/rods, mob/user)
	TEST_ASSERT(target.build_shuttle_frame_with_rods(rods, user), "build_shuttle_frame_with_rods should succeed on [target.type]")

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating/Run()
	var/turf/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	prepare_plating(target)

	var/rod_count = rods.get_amount()
	apply_shuttle_rods(target, rods, user)

	TEST_ASSERT_EQUAL(rods.get_amount(), rod_count - 1, "Shuttle frame rod should be consumed")
	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Visible turf should be plating after anchoring frame rods")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "Plating should have shuttle construction trait")
	TEST_ASSERT(GLOB.shuttle_frames_by_turf[target], "Plating should be registered to a shuttle frame")
	TEST_ASSERT(!target.depth_to_find_baseturf(/turf/baseturf_skipover/shuttle), "Skipover should not be inserted during frame construction")

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating_attackby

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_plating_attackby/Run()
	var/turf/target = run_loc_floor_bottom_left
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
	var/turf/target = run_loc_floor_bottom_left
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/stack/rods/shuttle/rods = allocate(/obj/item/stack/rods/shuttle/five)
	RESET_TO_EXPECTED(target)
	TEST_ASSERT(istype(target, EXPECTED_FLOOR_TYPE), "Test turf should start as iron floor")

	apply_shuttle_rods(target, rods, user)

	TEST_ASSERT(istype(target, /turf/open/floor/plating), "Anchoring rods on tiled floor should place plating on top")
	TEST_ASSERT(HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF), "New plating layer should have shuttle construction trait")
	var/list/baseturf_list = islist(target.baseturfs) ? target.baseturfs : list(target.baseturfs)
	TEST_ASSERT(baseturf_list.Find(EXPECTED_FLOOR_TYPE), "Prior floor type should be preserved in baseturfs")

/datum/unit_test/shuttle_construction/shuttle_frame_rods_on_tiled_floor/Destroy()
	reset_shuttle_frame_turf(run_loc_floor_bottom_left)
	return ..()

/datum/unit_test/shuttle_construction/shuttle_frame_trait_survives_tiling

/datum/unit_test/shuttle_construction/shuttle_frame_trait_survives_tiling/Run()
	var/turf/target = run_loc_floor_bottom_left
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
	var/turf/target = run_loc_floor_bottom_left
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
	var/turf/target = run_loc_floor_bottom_left
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
	var/turf/target = run_loc_floor_bottom_left
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

#undef RESET_TO_EXPECTED
#undef EXPECTED_FLOOR_TYPE
