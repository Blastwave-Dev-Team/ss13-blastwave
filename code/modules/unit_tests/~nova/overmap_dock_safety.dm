// MODULE ID: OVERMAP

/datum/unit_test/overmap_dock_safety
	abstract_type = /datum/unit_test/overmap_dock_safety
	/// Reserved transit block holding the loaded SolFed Cutter hull.
	var/datum/turf_reservation/cutter_reserve
	/// Mobile port from the loaded solfed_cutter shuttle template.
	var/obj/docking_port/mobile/overmap/frigate/solfed_cutter/cutter

/datum/unit_test/overmap_dock_safety/Destroy()
	if(!QDELETED(cutter))
		if(cutter.current_ship)
			cutter.current_ship.shuttle = null
			cutter.current_ship = null
		qdel(cutter, force = TRUE)
	cutter = null
	QDEL_NULL(cutter_reserve)
	for(var/obj/docking_port/port in allocated.Copy())
		if(!QDELETED(port))
			qdel(port, force = TRUE)
	return ..()

/datum/unit_test/overmap_dock_safety/proc/make_stationary_port(turf/port_turf, size = 1)
	var/obj/docking_port/stationary/port = allocate(/obj/docking_port/stationary, port_turf)
	port.width = size
	port.height = size
	port.dwidth = 0
	port.dheight = 0
	port.setDir(NORTH)
	return port

/// COMSIG_SHUTTLE_SHOULD_MOVE handler used to force canMove() to fail.
/datum/unit_test/overmap_dock_safety/proc/block_shuttle_move(datum/source)
	SIGNAL_HANDLER
	return BLOCK_SHUTTLE_MOVE

/// Load solfed_cutter.dmm into a transit reservation large enough for hull + pad.
/datum/unit_test/overmap_dock_safety/proc/load_solfed_cutter()
	var/datum/map_template/shuttle/template = SSmapping.shuttle_templates["solfed_cutter"]
	TEST_ASSERT(template, "solfed_cutter missing from SSmapping.shuttle_templates")

	var/reserve_w = template.width * 2 + 8
	var/reserve_h = max(template.height, template.width) + 4
	cutter_reserve = SSmapping.request_turf_block_reservation(
		reserve_w,
		reserve_h,
		1,
		reservation_type = /datum/turf_reservation/transit,
	)
	TEST_ASSERT(cutter_reserve, "Failed to reserve transit block for solfed_cutter")

	var/turf/anchor = cutter_reserve.bottom_left_turfs[1]
	TEST_ASSERT(anchor, "Cutter reservation has no bottom-left turf")
	// Suppress engine atmos_init runtimes during cutter load (not under test).
	var/datum/unit_test/prior_test = GLOB.current_test
	GLOB.current_test = null
	var/loaded = template.load(anchor, centered = FALSE, register = TRUE)
	GLOB.current_test = prior_test
	TEST_ASSERT(loaded, "template.load failed for solfed_cutter")

	for(var/turf/affected as anything in template.get_affected_turfs(anchor, FALSE))
		for(var/obj/docking_port/mobile/overmap/frigate/solfed_cutter/found in affected)
			cutter = found
			break
		if(cutter)
			break
	TEST_ASSERT(cutter, "No solfed_cutter mobile port after template load")
	template.post_load(cutter)
	return cutter

/// Stationary pad matching `mobile`, shifted clear of its hull footprint.
/datum/unit_test/overmap_dock_safety/proc/make_matching_dest_pad(obj/docking_port/mobile/mobile)
	var/list/coords = mobile.return_coords()
	var/shift_x = abs(coords[3] - coords[1]) + 3
	var/turf/dest_turf = locate(mobile.x + shift_x, mobile.y, mobile.z)
	TEST_ASSERT(dest_turf, "Failed to locate destination pad turf beside cutter hull")
	TEST_ASSERT(cutter_reserve.calculate_turf_bounds_information(dest_turf), "Destination pad turf outside cutter reservation")

	var/obj/docking_port/stationary/dest = allocate(/obj/docking_port/stationary, dest_turf)
	dest.name = "Dock Safety Pad"
	dest.shuttle_id = "[OVERMAP_DOCK_PREFIX]_[SSovermap.main.id]"
	dest.width = mobile.width
	dest.height = mobile.height
	dest.dwidth = mobile.dwidth
	dest.dheight = mobile.dheight
	dest.setDir(mobile.dir)

	var/list/pad_coords = dest.return_coords()
	var/turf/far_corner = locate(max(pad_coords[1], pad_coords[3]), max(pad_coords[2], pad_coords[4]), dest_turf.z)
	TEST_ASSERT(far_corner && cutter_reserve.calculate_turf_bounds_information(far_corner), "Destination pad footprint leaves cutter reservation")
	return dest

/datum/unit_test/overmap_dock_safety/footprint_clear

/datum/unit_test/overmap_dock_safety/footprint_clear/Run()
	var/turf/pad = run_loc_floor_bottom_left
	pad.ChangeTurf(/turf/open/floor/plating)

	var/obj/docking_port/stationary/clear_port = make_stationary_port(pad)
	TEST_ASSERT(SSovermap.dock_footprint_is_clear(clear_port), "Plating footprint should be clear.")

	pad.ChangeTurf(/turf/open/floor/iron)
	TEST_ASSERT(!SSovermap.dock_footprint_is_clear(clear_port), "Iron floor is not in the nav landing whitelist.")

	pad.ChangeTurf(/turf/open/floor/plating)
	TEST_ASSERT(SSovermap.dock_footprint_is_clear(clear_port), "Plating should be clear again after restore.")

	var/obj/structure/closet/blocker = allocate(/obj/structure/closet, pad)
	TEST_ASSERT(blocker.density, "Closet fixture should be dense.")
	blocker.anchored = FALSE
	TEST_ASSERT(SSovermap.dock_footprint_is_clear(clear_port), "Dense but unanchored objects must not block the footprint.")
	blocker.anchored = TRUE
	TEST_ASSERT(!SSovermap.dock_footprint_is_clear(clear_port), "Dense anchored obstacle should fail footprint clear.")
	qdel(blocker)

	var/obj/machinery/door/airlock/door = allocate(/obj/machinery/door/airlock, pad)
	TEST_ASSERT(SSovermap.dock_footprint_is_clear(clear_port), "Airlocks are allowed on a clear landing footprint.")
	qdel(door)

	pad.ChangeTurf(/turf/closed/wall)
	TEST_ASSERT(!SSovermap.dock_footprint_is_clear(clear_port), "Wall turfs must fail footprint clear.")
	pad.ChangeTurf(/turf/open/floor/plating)

	// Multi-tile footprints must check every tile, not just the port tile.
	for(var/dx in 0 to 1)
		for(var/dy in 0 to 1)
			var/turf/block_tile = locate(pad.x + dx, pad.y + dy, pad.z)
			TEST_ASSERT(block_tile, "Missing turf for 2x2 footprint fixture.")
			block_tile.ChangeTurf(/turf/open/floor/plating)
	var/obj/docking_port/stationary/wide_port = make_stationary_port(pad, size = 2)
	TEST_ASSERT(SSovermap.dock_footprint_is_clear(wide_port), "Fully plated 2x2 footprint should be clear.")
	var/turf/far_tile = locate(pad.x + 1, pad.y + 1, pad.z)
	far_tile.ChangeTurf(/turf/open/floor/iron)
	TEST_ASSERT(!SSovermap.dock_footprint_is_clear(wide_port), "One obstructed tile must fail a multi-tile footprint.")
	far_tile.ChangeTurf(/turf/open/floor/plating)

/datum/unit_test/overmap_dock_safety/bind_whitelist

/datum/unit_test/overmap_dock_safety/bind_whitelist/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/area/stage_area = get_area(stage)

	var/obj/docking_port/mobile/overmap/frigate/overmap_port = allocate(/obj/docking_port/mobile/overmap/frigate, stage, list(stage_area))
	TEST_ASSERT(SSovermap.should_bind_shuttle(overmap_port), "Overmap frigate ports should bind.")

	var/obj/docking_port/mobile/custom/custom_port = allocate(/obj/docking_port/mobile/custom, stage, list(stage_area))
	TEST_ASSERT(SSovermap.should_bind_shuttle(custom_port), "Custom shuttle ports should bind.")

	var/obj/docking_port/mobile/generic = allocate(/obj/docking_port/mobile, stage, list(stage_area))
	TEST_ASSERT(!SSovermap.should_bind_shuttle(generic), "Generic mobile ports should not bind.")

	// Oddly typed ports still bind when their area maps to an overmap ship type.
	var/obj/docking_port/mobile/odd_fighter = allocate(/obj/docking_port/mobile, stage, list(stage_area))
	odd_fighter.area_type = /area/shuttle/overmap/fighter
	TEST_ASSERT(SSovermap.should_bind_shuttle(odd_fighter), "Generic port with an overmap fighter area must bind.")
	TEST_ASSERT_EQUAL(SSovermap.ship_type_for_port(odd_fighter), /obj/structure/overmap/ship/simulated/fighter, "Fighter area should map to the fighter ship type.")
	TEST_ASSERT_EQUAL(SSovermap.ship_type_for_port(overmap_port), /obj/structure/overmap/ship/simulated/frigate, "Frigate area should map to the frigate ship type.")
	TEST_ASSERT_EQUAL(SSovermap.ship_type_for_port(generic), /obj/structure/overmap/ship/simulated, "Generic port should map to the base simulated ship type.")

	var/obj/docking_port/mobile/emergency/escape = allocate(/obj/docking_port/mobile/emergency, stage, list(stage_area))
	TEST_ASSERT(!SSovermap.should_bind_shuttle(escape), "Emergency shuttle must not bind.")

	var/obj/docking_port/mobile/supply/cargo = allocate(/obj/docking_port/mobile/supply, stage, list(stage_area))
	TEST_ASSERT(!SSovermap.should_bind_shuttle(cargo), "Supply shuttle must not bind.")

	TEST_ASSERT(!SSovermap.should_bind_shuttle(null), "Null port must not bind.")

/datum/unit_test/overmap_dock_safety/home_affiliation
	/// Pre-test station_revealed_to_ds2, restored in Destroy so a mid-test
	/// assertion failure can't leak the flipped global into later tests.
	var/saved_reveal = -1

/datum/unit_test/overmap_dock_safety/home_affiliation/Destroy()
	if(saved_reveal != -1)
		SSovermap.station_revealed_to_ds2 = saved_reveal
	return ..()

/datum/unit_test/overmap_dock_safety/home_affiliation/Run()
	if(!SSovermap.main)
		return

	saved_reveal = SSovermap.station_revealed_to_ds2
	var/obj/structure/overmap/ship/simulated/ship = allocate(/obj/structure/overmap/ship/simulated, run_loc_floor_bottom_left)

	ship.home_level_id = MAIN_OVERMAP_OBJECT_ID
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_NT, "MAIN home_level_id should resolve NT.")
	TEST_ASSERT(SSovermap.can_view_installation(ship, SSovermap.main), "NT-home ship must see the station.")

	ship.home_level_id = DES_TWO_OVERMAP_OBJECT_ID
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_DS2, "DES_TWO home_level_id should resolve DS2.")
	SSovermap.station_revealed_to_ds2 = FALSE
	TEST_ASSERT(!SSovermap.can_view_installation(ship, SSovermap.main), "DS2-home ship must not see station before reveal.")
	SSovermap.station_revealed_to_ds2 = TRUE
	TEST_ASSERT(SSovermap.can_view_installation(ship, SSovermap.main), "DS2-home ship must see station after reveal.")

	ship.home_level_id = null
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_NEUTRAL, "Unset home_level_id should be neutral.")

	ship.home_level_id = "no_such_level"
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_NEUTRAL, "Unknown home_level_id should be neutral.")

/datum/unit_test/overmap_dock_safety/adjacency_seed

/datum/unit_test/overmap_dock_safety/adjacency_seed/Run()
	var/turf/stage = run_loc_floor_top_right
	var/obj/structure/overmap/first = allocate(/obj/structure/overmap, stage)
	var/obj/structure/overmap/second = allocate(/obj/structure/overmap, stage)

	TEST_ASSERT(first in second.close_overmap_objects, "Second spawn should register first as adjacent.")
	TEST_ASSERT(second in first.close_overmap_objects, "Crossed should be bidirectional.")

	first.on_overmap_crossed(second, null)
	var/count = 0
	for(var/obj/structure/overmap/peer as anything in first.close_overmap_objects)
		if(peer == second)
			count++
	TEST_ASSERT_EQUAL(count, 1, "on_overmap_crossed should be idempotent.")

	// Moving off the tile must uncross both sides.
	var/turf/away = get_step(stage, WEST)
	TEST_ASSERT(away, "Missing adjacent turf for uncross fixture.")
	second.forceMove(away)
	TEST_ASSERT(!(first in second.close_overmap_objects), "Moving away should uncross the mover's list.")
	TEST_ASSERT(!(second in first.close_overmap_objects), "Moving away should uncross the stayer's list.")

	// Moving back onto the tile must re-cross.
	second.forceMove(stage)
	TEST_ASSERT(first in second.close_overmap_objects, "Returning to the tile should re-cross.")
	TEST_ASSERT(second in first.close_overmap_objects, "Re-cross should be bidirectional.")

/datum/unit_test/overmap_dock_safety/call_mode_commit

/datum/unit_test/overmap_dock_safety/call_mode_commit/Run()
	if(!SSovermap.main)
		return

	load_solfed_cutter()
	var/obj/docking_port/stationary/dest = make_matching_dest_pad(cutter)
	TEST_ASSERT(SSovermap.dock_footprint_is_clear(dest), "Destination pad must be footprint-clear for dock().")
	TEST_ASSERT(cutter.check_dock(dest, TRUE), "Cutter must be able to dock at the surveyed pad.")

	var/obj/structure/overmap/ship/simulated/ship = allocate(
		/obj/structure/overmap/ship/simulated,
		run_loc_floor_bottom_left,
		cutter.shuttle_id,
		cutter,
	)
	cutter.current_ship = ship
	ship.state = OVERMAP_SHIP_FLYING
	ship.home_level_id = MAIN_OVERMAP_OBJECT_ID
	ship.vel_x = 0
	ship.vel_y = 0
	LAZYADD(ship.close_overmap_objects, SSovermap.main)

	// The candidate lookup must resolve to our pad, not a station dock that
	// happens to share the "[OVERMAP_DOCK_PREFIX]_[id]" naming.
	TEST_ASSERT_EQUAL(ship.find_dock_quiet(dest.shuttle_id), dest, "Candidate dock ID must resolve to the test pad.")

	cutter.mode = SHUTTLE_CALL
	cutter.destination = null

	// Rejection: ship still drifting.
	ship.vel_x = 1
	var/moving = ship.dock(SSovermap.main)
	TEST_ASSERT(findtext(moving, "must be stopped"), "Drifting ship should be rejected, got: [moving]")
	TEST_ASSERT_EQUAL(ship.state, OVERMAP_SHIP_FLYING, "Drift rejection must not change ship state.")
	ship.vel_x = 0

	// Rejection: engines cannot move (canMove precheck).
	RegisterSignal(cutter, COMSIG_SHUTTLE_SHOULD_MOVE, PROC_REF(block_shuttle_move))
	var/blocked = ship.dock(SSovermap.main)
	TEST_ASSERT(findtext(blocked, "Engines not responding"), "Blocked canMove should be rejected, got: [blocked]")
	TEST_ASSERT_EQUAL(ship.state, OVERMAP_SHIP_FLYING, "canMove rejection must not change ship state.")
	UnregisterSignal(cutter, COMSIG_SHUTTLE_SHOULD_MOVE)

	// Rejection: obstructed pad drops out of the candidate scan entirely.
	var/obj/structure/closet/obstruction = allocate(/obj/structure/closet, get_turf(dest))
	obstruction.anchored = TRUE
	TEST_ASSERT(!SSovermap.dock_footprint_is_clear(dest), "Obstruction fixture should dirty the pad footprint.")
	var/no_dock = ship.dock(SSovermap.main)
	TEST_ASSERT(findtext(no_dock, "No automatic dock found"), "Obstructed pad should yield no dock, got: [no_dock]")
	TEST_ASSERT_EQUAL(ship.state, OVERMAP_SHIP_FLYING, "No-dock rejection must not change ship state.")
	qdel(obstruction)
	TEST_ASSERT(SSovermap.dock_footprint_is_clear(dest), "Pad footprint should be clear again after obstruction removal.")

	// Rejection: request() fails to commit (mode unhandled by request's switch),
	// which must roll DOCKING back to FLYING.
	cutter.mode = SHUTTLE_PREARRIVAL
	cutter.destination = null
	var/uncommitted = ship.dock(SSovermap.main)
	TEST_ASSERT(findtext(uncommitted, "could not commit"), "Failed request() should reject, got: [uncommitted]")
	TEST_ASSERT_EQUAL(ship.state, OVERMAP_SHIP_FLYING, "Commit failure must roll ship state back to FLYING.")
	TEST_ASSERT(isnull(ship.docked), "Commit failure must clear the pending docked target.")

	cutter.mode = SHUTTLE_CALL
	cutter.destination = null

	var/result = ship.dock(SSovermap.main)
	TEST_ASSERT(findtext(result, "Commencing docking"), "Expected successful dock commit, got: [result]")
	TEST_ASSERT_EQUAL(ship.state, OVERMAP_SHIP_DOCKING, "Ship state should stay DOCKING after SHUTTLE_CALL commit.")
	TEST_ASSERT_EQUAL(cutter.destination, dest, "request() should redirect SHUTTLE_CALL onto the surveyed pad.")
	TEST_ASSERT(cutter.mode == SHUTTLE_CALL || cutter.mode == SHUTTLE_IGNITING || cutter.mode == SHUTTLE_PREARRIVAL, "Committed shuttle mode should remain inbound.")

	var/busy = ship.dock(SSovermap.main)
	TEST_ASSERT_EQUAL(busy, "Docking already in progress.", "Second dock while DOCKING must be rejected.")

	// Park the shuttle so SSshuttle can't fire the queued CALL mid-suite.
	cutter.mode = SHUTTLE_IDLE
	cutter.destination = null
	if(cutter.current_ship == ship)
		cutter.current_ship = null
	ship.shuttle = null
