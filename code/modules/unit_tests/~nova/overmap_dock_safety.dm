// MODULE ID: OVERMAP

/datum/unit_test/overmap_dock_safety
	abstract_type = /datum/unit_test/overmap_dock_safety
	/// Reserved transit block for cutter-sized dock fixtures (never the unit-test room).
	var/datum/turf_reservation/cutter_reserve
	/// Synthetic cutter-sized mobile port (dimensions from solfed_cutter template).
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

/// Build a cutter-sized mobile + plated runway from solfed_cutter template
/// dimensions without loading the DMM (engine atmos_init runtimes fail CI).
/// Port faces WEST: world bbox is height×width, so place it inset from the
/// reservation corner or the pad footprint hits cordon walls.
/datum/unit_test/overmap_dock_safety/proc/make_cutter_sized_shuttle()
	var/datum/map_template/shuttle/template = SSmapping.shuttle_templates["solfed_cutter"]
	TEST_ASSERT(template, "solfed_cutter missing from SSmapping.shuttle_templates")
	TEST_ASSERT(template.width > 0 && template.height > 0, "solfed_cutter template has no dimensions")

	var/ship_w = template.width
	var/ship_h = template.height
	var/dwidth = round(ship_w / 2)
	// WEST: X span = height, Y span = width. Hull + gap + matching pad + padding.
	var/reserve_w = ship_h * 2 + 8
	var/reserve_h = ship_w + 4
	cutter_reserve = SSmapping.request_turf_block_reservation(
		reserve_w,
		reserve_h,
		1,
		reservation_type = /datum/turf_reservation/transit,
	)
	TEST_ASSERT(cutter_reserve, "Failed to reserve transit block for cutter-sized fixture")

	var/turf/anchor = cutter_reserve.bottom_left_turfs[1]
	TEST_ASSERT(anchor, "Cutter reservation has no bottom-left turf")

	// Plate the hull + destination runway so check_dock / footprint checks pass.
	for(var/turf/tile as anything in block(
		anchor.x,
		anchor.y,
		anchor.z,
		anchor.x + reserve_w - 1,
		anchor.y + reserve_h - 1,
		anchor.z,
	))
		tile.ChangeTurf(/turf/open/floor/plating)

	// Inset so WEST-facing hull min corner sits on the reservation origin.
	var/turf/port_turf = locate(anchor.x + ship_h - 1, anchor.y + dwidth, anchor.z)
	TEST_ASSERT(port_turf, "Failed to locate inset cutter port turf")
	TEST_ASSERT(cutter_reserve.calculate_turf_bounds_information(port_turf), "Cutter port turf outside reservation")

	cutter = new /obj/docking_port/mobile/overmap/frigate/solfed_cutter(port_turf)
	cutter.width = ship_w
	cutter.height = ship_h
	cutter.dwidth = dwidth
	cutter.dheight = 0
	cutter.setDir(WEST)
	cutter.register(TRUE)
	// Initialize may have auto-bound an overmap ship on the reserved Z; the
	// call_mode_commit test builds its own ship fixture.
	if(cutter.current_ship)
		var/obj/structure/overmap/ship/simulated/auto_ship = cutter.current_ship
		cutter.current_ship = null
		auto_ship.shuttle = null
		qdel(auto_ship)
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
	var/min_x = min(pad_coords[1], pad_coords[3])
	var/min_y = min(pad_coords[2], pad_coords[4])
	var/max_x = max(pad_coords[1], pad_coords[3])
	var/max_y = max(pad_coords[2], pad_coords[4])
	for(var/check_x in list(min_x, max_x))
		for(var/check_y in list(min_y, max_y))
			var/turf/corner = locate(check_x, check_y, dest_turf.z)
			TEST_ASSERT(corner && cutter_reserve.calculate_turf_bounds_information(corner), "Destination pad footprint leaves cutter reservation")
	// Re-plate after port placement in case any tile was missed by the runway sweep.
	for(var/turf/pad_tile as anything in dest.return_turfs())
		if(!istype(pad_tile, /turf/open/floor/plating))
			pad_tile.ChangeTurf(/turf/open/floor/plating)
	return dest

/datum/unit_test/overmap_dock_safety/footprint_clear

/datum/unit_test/overmap_dock_safety/footprint_clear/Run()
	// Mutate a reserved block, never the shared unit-test room (area_contents).
	cutter_reserve = SSmapping.request_turf_block_reservation(
		6,
		6,
		1,
		reservation_type = /datum/turf_reservation/transit,
	)
	TEST_ASSERT(cutter_reserve, "Failed to reserve block for footprint_clear")
	var/turf/pad = cutter_reserve.bottom_left_turfs[1]
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
	// Do not pass /area/misc/testroom as shuttle_areas — that orphans the
	// unit-test room from area turf listings (maptest_area_contents).
	// custom/Initialize still requires a disposable areas list for default_area.

	var/obj/docking_port/mobile/overmap/frigate/overmap_port = allocate(/obj/docking_port/mobile/overmap/frigate, stage)
	TEST_ASSERT(SSovermap.should_bind_shuttle(overmap_port), "Overmap frigate ports should bind.")

	var/area/shuttle/custom_bind_area = new /area/shuttle
	var/obj/docking_port/mobile/custom/custom_port = allocate(/obj/docking_port/mobile/custom, stage, list(custom_bind_area))
	TEST_ASSERT(SSovermap.should_bind_shuttle(custom_port), "Custom shuttle ports should bind.")

	var/obj/docking_port/mobile/generic = allocate(/obj/docking_port/mobile, stage)
	TEST_ASSERT(!SSovermap.should_bind_shuttle(generic), "Generic mobile ports should not bind.")

	// Oddly typed ports still bind when their area maps to an overmap ship type.
	var/obj/docking_port/mobile/odd_fighter = allocate(/obj/docking_port/mobile, stage)
	odd_fighter.area_type = /area/shuttle/overmap/fighter
	TEST_ASSERT(SSovermap.should_bind_shuttle(odd_fighter), "Generic port with an overmap fighter area must bind.")
	TEST_ASSERT_EQUAL(SSovermap.ship_type_for_port(odd_fighter), /obj/structure/overmap/ship/simulated/fighter, "Fighter area should map to the fighter ship type.")
	TEST_ASSERT_EQUAL(SSovermap.ship_type_for_port(overmap_port), /obj/structure/overmap/ship/simulated/frigate, "Frigate area should map to the frigate ship type.")
	TEST_ASSERT_EQUAL(SSovermap.ship_type_for_port(generic), /obj/structure/overmap/ship/simulated, "Generic port should map to the base simulated ship type.")

	var/obj/docking_port/mobile/emergency/escape = allocate(/obj/docking_port/mobile/emergency, stage)
	TEST_ASSERT(!SSovermap.should_bind_shuttle(escape), "Emergency shuttle must not bind.")

	var/obj/docking_port/mobile/supply/cargo = allocate(/obj/docking_port/mobile/supply, stage)
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

	TEST_ASSERT(SSovermap.apply_ship_affiliation(ship, OVERMAP_AFFILIATION_NT), "apply_ship_affiliation should accept NT.")
	TEST_ASSERT_EQUAL(ship.home_level_id, MAIN_OVERMAP_OBJECT_ID, "NT affiliation should pin MAIN home_level_id.")
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_NT, "Applied NT should resolve NT.")

	TEST_ASSERT(SSovermap.apply_ship_affiliation(ship, OVERMAP_AFFILIATION_DS2), "apply_ship_affiliation should accept DS2.")
	TEST_ASSERT_EQUAL(ship.home_level_id, DES_TWO_OVERMAP_OBJECT_ID, "DS2 affiliation should pin DES_TWO home_level_id.")
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_DS2, "Applied DS2 should resolve DS2.")

	TEST_ASSERT(SSovermap.apply_ship_affiliation(ship, OVERMAP_AFFILIATION_NEUTRAL), "apply_ship_affiliation should accept neutral.")
	TEST_ASSERT_EQUAL(ship.home_level_id, null, "Neutral affiliation should clear home_level_id.")
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_NEUTRAL, "Applied neutral should resolve neutral.")

	TEST_ASSERT(!SSovermap.apply_ship_affiliation(ship, "not_a_faction"), "Unknown faction string should be rejected.")
	TEST_ASSERT(!SSovermap.apply_ship_affiliation(null, OVERMAP_AFFILIATION_NT), "Null ship should be rejected.")

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

	// Refresh must not append duplicate contacts, and should repair any
	// duplicates retained by an already-running server.
	LAZYADD(first.close_overmap_objects, second)
	LAZYADD(second.close_overmap_objects, first)
	first.refresh_close_overmap_objects()
	first.refresh_close_overmap_objects()
	count = 0
	for(var/obj/structure/overmap/peer as anything in first.close_overmap_objects)
		if(peer == second)
			count++
	TEST_ASSERT_EQUAL(count, 1, "Proximity refresh should normalize duplicate contacts.")
	count = 0
	for(var/obj/structure/overmap/peer as anything in second.close_overmap_objects)
		if(peer == first)
			count++
	TEST_ASSERT_EQUAL(count, 1, "Proximity refresh should normalize reciprocal duplicate contacts.")

	// Moving beyond interaction range must uncross both sides.
	var/turf/away = get_step(get_step(stage, WEST), WEST)
	TEST_ASSERT(away, "Missing out-of-range turf for uncross fixture.")
	second.forceMove(away)
	TEST_ASSERT(!(first in second.close_overmap_objects), "Moving out of range should uncross the mover's list.")
	TEST_ASSERT(!(second in first.close_overmap_objects), "Moving out of range should uncross the stayer's list.")

	// Moving back onto the tile must re-cross.
	second.forceMove(stage)
	TEST_ASSERT(first in second.close_overmap_objects, "Returning to the tile should re-cross.")
	TEST_ASSERT(second in first.close_overmap_objects, "Re-cross should be bidirectional.")

/datum/unit_test/overmap_dock_safety/call_mode_commit

/datum/unit_test/overmap_dock_safety/call_mode_commit/Run()
	if(!SSovermap.main)
		return

	make_cutter_sized_shuttle()
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

/// Registered test hull with explicit bbox. Unbinds any auto-created overmap icon.
/datum/unit_test/overmap_dock_safety/proc/make_sized_mobile(turf/port_turf, size = 2, id = "overlap_test")
	var/obj/docking_port/mobile/port = allocate(/obj/docking_port/mobile, port_turf)
	port.shuttle_id = id
	port.width = size
	port.height = size
	port.dwidth = 0
	port.dheight = 0
	port.setDir(NORTH)
	port.register(TRUE)
	if(port.current_ship)
		var/obj/structure/overmap/ship/simulated/auto_ship = port.current_ship
		port.current_ship = null
		auto_ship.shuttle = null
		qdel(auto_ship)
	return port

/datum/unit_test/overmap_dock_safety/overlap_occupied

/datum/unit_test/overmap_dock_safety/overlap_occupied/Run()
	cutter_reserve = SSmapping.request_turf_block_reservation(
		6,
		4,
		1,
		reservation_type = /datum/turf_reservation/transit,
	)
	TEST_ASSERT(cutter_reserve, "Failed to reserve block for overlap_occupied")
	var/turf/origin = cutter_reserve.bottom_left_turfs[1]
	for(var/turf/tile as anything in block(origin.x, origin.y, origin.z, origin.x + 5, origin.y + 3, origin.z))
		tile.ChangeTurf(/turf/open/floor/plating)

	var/obj/docking_port/mobile/occupant = make_sized_mobile(origin, 2, "overlap_occupant")
	var/turf/dest_turf = locate(origin.x + 1, origin.y, origin.z)
	var/obj/docking_port/stationary/dest = make_stationary_port(dest_turf, size = 2)
	var/obj/docking_port/mobile/incoming = make_sized_mobile(locate(origin.x + 4, origin.y, origin.z), 2, "overlap_incoming")

	TEST_ASSERT(dest.overlaps_other_mobile(incoming), "Dest bbox should overlap the occupant hull.")
	TEST_ASSERT_EQUAL(incoming.canDock(dest), SHUTTLE_SOMEONE_ELSE_DOCKED, "Occupied bbox must reject docking.")
	TEST_ASSERT(!incoming.check_dock(dest, TRUE), "check_dock must fail when another hull covers the pad.")
	TEST_ASSERT_NULL(incoming.resolve_near_station_space_fallback(dest, SHUTTLE_SOMEONE_ELSE_DOCKED), "Non-ERT hulls must not get a space fallback.")

	var/turf/clear_turf = locate(origin.x + 3, origin.y, origin.z)
	var/obj/docking_port/stationary/clear_dest = make_stationary_port(clear_turf, size = 2)
	TEST_ASSERT(!clear_dest.overlaps_other_mobile(incoming), "Adjacent non-overlapping pad should be clear of the occupant.")
	TEST_ASSERT_EQUAL(incoming.canDock(clear_dest), SHUTTLE_CAN_DOCK, "Clear adjacent pad should accept docking.")

	qdel(occupant, force = TRUE)

/datum/unit_test/overmap_dock_safety/ert_space_fallback

/datum/unit_test/overmap_dock_safety/ert_space_fallback/Run()
	TEST_ASSERT(docking_bboxes_overlap(list(1, 1, 2, 2), list(2, 2, 3, 3)), "Touching bboxes must count as overlap.")
	TEST_ASSERT(!docking_bboxes_overlap(list(1, 1, 2, 2), list(3, 1, 4, 2)), "Separated bboxes must not overlap.")
	TEST_ASSERT(!docking_bbox_is_on_map(list(1, 1, 5, 5)), "Bbox in the transition edge must be rejected.")
	TEST_ASSERT(docking_bbox_is_on_map(list(TRANSITIONEDGE, TRANSITIONEDGE, TRANSITIONEDGE + 4, TRANSITIONEDGE + 4)), "Inset bbox must be on-map.")
	TEST_ASSERT(!docking_bbox_is_on_map(list(world.maxx - 3, TRANSITIONEDGE + 2, world.maxx, TRANSITIONEDGE + 6)), "Bbox clipping world.maxx must be rejected.")
	TEST_ASSERT(!docking_bbox_is_on_map(list(TRANSITIONEDGE + 2, world.maxy - 3, TRANSITIONEDGE + 6, world.maxy)), "Bbox clipping world.maxy must be rejected.")

	var/list/station_zs = SSmapping.levels_by_trait(ZTRAIT_STATION)
	if(length(station_zs))
		var/turf/station_tile
		for(var/turf/maybe as anything in Z_TURFS(station_zs[1]))
			if(istype(maybe.loc, /area/station))
				station_tile = maybe
				break
		if(station_tile)
			var/list/station_coords = list(station_tile.x, station_tile.y, station_tile.x, station_tile.y)
			TEST_ASSERT(docking_bbox_clips_station(station_coords, station_tile.z), "A bbox on a station area tile must count as clipping the station.")
			TEST_ASSERT(!docking_bbox_clips_station(list(1, 1, 2, 2), station_tile.z), "A bbox in the map corner must not count as station clipping.")

	cutter_reserve = SSmapping.request_turf_block_reservation(
		8,
		4,
		1,
		reservation_type = /datum/turf_reservation/transit,
	)
	TEST_ASSERT(cutter_reserve, "Failed to reserve block for ert_space_fallback")
	var/turf/origin = cutter_reserve.bottom_left_turfs[1]
	for(var/turf/tile as anything in block(origin.x, origin.y, origin.z, origin.x + 7, origin.y + 3, origin.z))
		tile.ChangeTurf(/turf/open/floor/plating)

	var/obj/docking_port/mobile/occupant = make_sized_mobile(origin, 2, "ert_fallback_occupant")
	var/turf/dest_turf = locate(origin.x + 1, origin.y, origin.z)
	var/obj/docking_port/stationary/dest = make_stationary_port(dest_turf, size = 2)
	var/obj/docking_port/mobile/ert = make_sized_mobile(locate(origin.x + 5, origin.y, origin.z), 2, "ert_test_shuttle")

	TEST_ASSERT(ert.uses_near_station_space_fallback(), "shuttle_id containing ert must use the space fallback.")
	TEST_ASSERT_EQUAL(ert.canDock(dest), SHUTTLE_SOMEONE_ELSE_DOCKED, "ERT must still see the hangar as occupied.")

	var/obj/docking_port/stationary/fallback = ert.maybe_divert_occupied_dock(dest)
	TEST_ASSERT(fallback, "Occupied hangar must rematch an ERT to a near-station landing.")
	TEST_ASSERT(fallback != dest, "Fallback must not be the occupied hangar pad.")
	TEST_ASSERT_EQUAL(ert.canDock(fallback), SHUTTLE_CAN_DOCK, "Fallback dock must be clear for the ERT.")

	var/obj/docking_port/stationary/whiteship = SSshuttle.getDock("whiteship_home")
	if(whiteship && fallback == whiteship)
		var/obj/docking_port/mobile/whiteship_blocker = make_sized_mobile(get_turf(whiteship), 1, "whiteship_blocker")
		TEST_ASSERT_EQUAL(ert.canDock(whiteship), SHUTTLE_SOMEONE_ELSE_DOCKED, "Occupied whiteship_home must reject docking.")
		var/obj/docking_port/stationary/space_dock = ert.resolve_near_station_space_fallback(whiteship, SHUTTLE_SOMEONE_ELSE_DOCKED)
		TEST_ASSERT(space_dock, "ERT must stamp a space dock when whiteship_home is also occupied.")
		TEST_ASSERT(space_dock != whiteship, "Space fallback must not reuse the occupied whiteship dock.")
		TEST_ASSERT_EQUAL(ert.canDock(space_dock), SHUTTLE_CAN_DOCK, "Stamped space dock must accept the ERT.")
		if(space_dock.delete_after)
			qdel(space_dock, force = TRUE)
		qdel(whiteship_blocker, force = TRUE)
	else if(fallback?.delete_after)
		qdel(fallback, force = TRUE)

	var/turf/space_origin = cutter_reserve.bottom_left_turfs[1]
	var/turf/space_tile = locate(space_origin.x + 6, space_origin.y, space_origin.z)
	space_tile.ChangeTurf(/turf/open/space/basic)
	var/turf/space_tile_b = locate(space_origin.x + 7, space_origin.y, space_origin.z)
	space_tile_b.ChangeTurf(/turf/open/space/basic)
	var/turf/space_tile_c = locate(space_origin.x + 6, space_origin.y + 1, space_origin.z)
	space_tile_c.ChangeTurf(/turf/open/space/basic)
	var/turf/space_tile_d = locate(space_origin.x + 7, space_origin.y + 1, space_origin.z)
	space_tile_d.ChangeTurf(/turf/open/space/basic)
	TEST_ASSERT(ert.space_anchor_is_clear(space_tile, NORTH), "A 2x2 of real space must pass space_anchor_is_clear.")
	TEST_ASSERT(!ert.space_anchor_is_clear(origin, NORTH), "Plating must fail space_anchor_is_clear.")
	var/obj/structure/lattice/blocker = allocate(/obj/structure/lattice, space_tile)
	TEST_ASSERT(!ert.space_anchor_is_clear(space_tile, NORTH), "Lattice on a space tile must fail space_anchor_is_clear.")
	qdel(blocker)

	qdel(occupant, force = TRUE)
