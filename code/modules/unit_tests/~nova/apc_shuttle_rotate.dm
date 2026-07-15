// MODULE ID: APC_SHUTTLE_ROTATE
/// Wallmount APCs must keep a single-axis pixel offset after setDir / shuttleRotate.
/datum/unit_test/apc_shuttle_rotate

/datum/unit_test/apc_shuttle_rotate/Run()
	var/obj/machinery/power/apc/apc = allocate(/obj/machinery/power/apc, run_loc_floor_bottom_left)

	apc.setDir(NORTH)
	TEST_ASSERT_EQUAL(apc.pixel_x, 0, "NORTH APC should clear pixel_x")
	TEST_ASSERT_EQUAL(apc.pixel_y, APC_PIXEL_OFFSET, "NORTH APC should set pixel_y")

	apc.setDir(EAST)
	TEST_ASSERT_EQUAL(apc.pixel_x, APC_PIXEL_OFFSET, "EAST APC after NORTH should set pixel_x")
	TEST_ASSERT_EQUAL(apc.pixel_y, 0, "EAST APC after NORTH should clear leftover pixel_y")

	apc.setDir(SOUTH)
	TEST_ASSERT_EQUAL(apc.pixel_x, 0, "SOUTH APC after EAST should clear leftover pixel_x")
	TEST_ASSERT_EQUAL(apc.pixel_y, -APC_PIXEL_OFFSET, "SOUTH APC should set pixel_y")

	apc.setDir(WEST)
	TEST_ASSERT_EQUAL(apc.pixel_x, -APC_PIXEL_OFFSET, "WEST APC should set pixel_x")
	TEST_ASSERT_EQUAL(apc.pixel_y, 0, "WEST APC after SOUTH should clear leftover pixel_y")

	apc.setDir(NORTH)
	apc.shuttleRotate(90, ALL)
	TEST_ASSERT_EQUAL(apc.dir, EAST, "90° shuttleRotate from NORTH should face EAST")
	TEST_ASSERT_EQUAL(apc.pixel_x, APC_PIXEL_OFFSET, "90° shuttleRotate should leave EAST wallmount pixel_x")
	TEST_ASSERT_EQUAL(apc.pixel_y, 0, "90° shuttleRotate must not leave a double-applied pixel_y")

	apc.setDir(EAST)
	apc.shuttleRotate(90, ALL)
	TEST_ASSERT_EQUAL(apc.dir, SOUTH, "90° shuttleRotate from EAST should face SOUTH")
	TEST_ASSERT_EQUAL(apc.pixel_x, 0, "90° shuttleRotate to SOUTH should clear pixel_x")
	TEST_ASSERT_EQUAL(apc.pixel_y, -APC_PIXEL_OFFSET, "90° shuttleRotate to SOUTH should set pixel_y")
