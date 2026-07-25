/// Stop must settle to the nearest turf under the visible sprite before
/// clearing fractional offsets (spacepod half-tile rule).

/datum/unit_test/overmap_stop_settle

/datum/unit_test/overmap_stop_settle/proc/stage_turf()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/stage = locate(origin.x + 2, origin.y + 2, origin.z)
	TEST_ASSERT(istype(stage, /turf), "Missing interior stage turf for stop-settle fixture.")
	for(var/direction in list(NORTH, SOUTH, EAST, WEST))
		TEST_ASSERT(get_step(stage, direction), "Stage turf needs a [dir2text(direction)] neighbor.")
	return stage

/datum/unit_test/overmap_stop_settle/Run()
	var/turf/stage = stage_turf()
	var/obj/structure/overmap/ship = allocate(/obj/structure/overmap/ship, stage)
	var/obj/structure/overmap/target = allocate(/obj/structure/overmap, stage)

	// Eastbound residual: logical turf advanced, sprite still ~0.8 behind.
	ship.forceMove(stage)
	ship.offset_x = -0.8
	ship.offset_y = 0
	ship.motion_last_offset_x = -0.8
	ship.motion_last_offset_y = 0
	ship.vel_x = 0
	ship.vel_y = 0
	ship.deactivate_physics()
	TEST_ASSERT_EQUAL(ship.x, stage.x - 1, "Eastbound stop should settle one tile west onto the visible turf.")
	TEST_ASSERT_EQUAL(ship.y, stage.y, "Eastbound stop must not change Y.")
	TEST_ASSERT_EQUAL(ship.offset_x, 0, "Stop must clear offset_x after settle.")
	TEST_ASSERT_EQUAL(ship.offset_y, 0, "Stop must clear offset_y after settle.")
	TEST_ASSERT(target in ship.close_overmap_objects, "A ship settled beside its target must remain in interaction range.")
	TEST_ASSERT(ship in target.close_overmap_objects, "Overmap interaction range must remain symmetric after settling.")

	// Westbound residual: logical turf advanced west, sprite ahead (+0.8).
	ship.forceMove(stage)
	ship.offset_x = 0.8
	ship.offset_y = 0
	ship.motion_last_offset_x = 0.8
	ship.motion_last_offset_y = 0
	ship.vel_x = 0
	ship.vel_y = 0
	ship.deactivate_physics()
	TEST_ASSERT_EQUAL(ship.x, stage.x + 1, "Westbound stop should settle one tile east onto the visible turf.")
	TEST_ASSERT_EQUAL(ship.y, stage.y, "Westbound stop must not change Y.")
	TEST_ASSERT_EQUAL(ship.offset_x, 0, "Westbound stop must clear offset_x.")

	// Sub-threshold residual stays on the logical turf (nearest).
	ship.forceMove(stage)
	ship.offset_x = -0.4
	ship.offset_y = 0
	ship.motion_last_offset_x = -0.4
	ship.motion_last_offset_y = 0
	ship.vel_x = 0
	ship.vel_y = 0
	ship.deactivate_physics()
	TEST_ASSERT_EQUAL(ship.x, stage.x, "Sub-threshold X residual should stay on the current turf.")
	TEST_ASSERT_EQUAL(ship.offset_x, 0, "Sub-threshold stop must still clear offset_x.")

	// Northbound residual.
	ship.forceMove(stage)
	ship.offset_x = 0
	ship.offset_y = -0.8
	ship.motion_last_offset_x = 0
	ship.motion_last_offset_y = -0.8
	ship.vel_x = 0
	ship.vel_y = 0
	ship.deactivate_physics()
	TEST_ASSERT_EQUAL(ship.x, stage.x, "Northbound stop must not change X.")
	TEST_ASSERT_EQUAL(ship.y, stage.y - 1, "Northbound stop should settle one tile south onto the visible turf.")
	TEST_ASSERT_EQUAL(ship.offset_y, 0, "Northbound stop must clear offset_y.")

	// Sub-threshold Y residual.
	ship.forceMove(stage)
	ship.offset_x = 0
	ship.offset_y = -0.4
	ship.motion_last_offset_x = 0
	ship.motion_last_offset_y = -0.4
	ship.vel_x = 0
	ship.vel_y = 0
	ship.deactivate_physics()
	TEST_ASSERT_EQUAL(ship.y, stage.y, "Sub-threshold Y residual should stay on the current turf.")
	TEST_ASSERT_EQUAL(ship.offset_y, 0, "Sub-threshold Y stop must clear offset_y.")
