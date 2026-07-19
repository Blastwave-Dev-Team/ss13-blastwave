// MODULE ID: OVERMAP
// Bay-exit validation. Prevents launching a shuttle out of a fully enclosed
// station bay (which would clip through walls). At undock time the shuttle must
// have a clear path to space along at least one edge of its bounding rectangle.
//
// If the shuttle is parked in a player-built landing zone whose controller
// designated an exit direction, only that edge is validated (a per-column
// raycast up to OVERMAP_BAY_EXIT_DEPTH tiles). Otherwise all four faces are
// checked and any fully-clear face passes.

/// How many tiles outward the per-column raycast probes for open space.
#define OVERMAP_BAY_EXIT_DEPTH 10

/// TRUE if `checked_turf` is a hard wall that blocks a launch path. Closed turfs
/// and anchored dense structures block; doors (openable) and open floors do not.
/proc/overmap_bay_tile_is_wall(turf/checked_turf)
	if(isclosedturf(checked_turf))
		return TRUE
	for(var/obj/blocker in checked_turf)
		if(!blocker.density)
			continue
		if(istype(blocker, /obj/machinery/door))
			continue
		if(blocker.anchored)
			return TRUE
	return FALSE

/// TRUE if `checked_turf` currently holds an open (non-dense) poddoor.
/proc/overmap_bay_tile_has_open_poddoor(turf/checked_turf)
	for(var/obj/machinery/door/poddoor/door in checked_turf)
		if(!door.density)
			return TRUE
	return FALSE

/// TRUE if the tile is a valid clear launch path (open space, open floor, or open poddoor).
/proc/overmap_bay_tile_is_clear(turf/checked_turf)
	if(isnull(checked_turf))
		return FALSE
	if(overmap_bay_tile_is_wall(checked_turf))
		return FALSE
	if(isspaceturf(checked_turf) || isopenturf(checked_turf))
		return TRUE
	return overmap_bay_tile_has_open_poddoor(checked_turf)

// Note: enforcement is intentionally scoped to the overmap `undock()` launch gate
// rather than a global COMSIG_SHUTTLE_SHOULD_MOVE handler. A global block risks
// interfering with the overmap ship's own dock()/undock() movement and with
// unrelated station shuttles (arrivals, escape, etc). Player-built ships launch
// exclusively through `undock()`, so that is the correct choke point.

/// Returns an error string if the bound shuttle cannot legally launch from its
/// current dock (no clear exit path), or null if launch is permitted. Admin
/// forced moves and open-space docks are naturally exempt.
/obj/structure/overmap/ship/simulated/proc/check_launch_clearance()
	if(!shuttle)
		return null
	var/obj/effect/landmark/overmap_landing_zone/zone = shuttle.get_overlapping_landing_zone()
	var/exit_dir = zone ? zone.exit_direction : NONE
	if(shuttle.check_bay_exit(exit_dir, zone))
		return null
	if(exit_dir)
		return "Launch path obstructed toward [dir2text(exit_dir)]. Clear a route to open space or open the bay doors before launching."
	return "Launch path obstructed. Clear a route to open space along one edge, or open the bay doors before launching."

/// Returns the landing zone with a designated exit direction overlapping this
/// shuttle's footprint, or null if the shuttle is not parked in a managed zone.
/obj/docking_port/mobile/proc/get_overlapping_landing_zone()
	var/list/bounds = return_coords()
	var/x1 = min(bounds[1], bounds[3])
	var/x2 = max(bounds[1], bounds[3])
	var/y1 = min(bounds[2], bounds[4])
	var/y2 = max(bounds[2], bounds[4])
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in SSovermap.landing_zones)
		if(zone.z != z || !zone.exit_direction)
			continue
		var/zx2 = zone.x + zone.zone_width - 1
		var/zy2 = zone.y + zone.zone_height - 1
		if(x1 <= zx2 && x2 >= zone.x && y1 <= zy2 && y2 >= zone.y)
			return zone
	return null

/// Validates that the shuttle has a clear launch path. Returns TRUE if launch is
/// allowed. `exit_dir` (a cardinal) restricts the check to a single edge; NONE
/// checks all four faces and passes if any one is fully clear. `zone` (the
/// landing zone that designated `exit_dir`) extends the raycast budget so the
/// probe depth is measured from the ZONE's exit edge, not the hull: a ship
/// parked at the far end of a large zone must still see out of the bay.
/obj/docking_port/mobile/proc/check_bay_exit(exit_dir = NONE, obj/effect/landmark/overmap_landing_zone/zone)
	var/list/bounds = return_coords()
	var/x1 = min(bounds[1], bounds[3])
	var/x2 = max(bounds[1], bounds[3])
	var/y1 = min(bounds[2], bounds[4])
	var/y2 = max(bounds[2], bounds[4])
	var/check_z = z

	if(exit_dir)
		// Tiles between the hull's exit edge and the zone's exit edge - still
		// part of the launch path, so the rays cross (and wall-check) them, but
		// they must not eat into the beyond-the-zone probe depth.
		var/interior_run = 0
		if(zone)
			switch(exit_dir)
				if(NORTH)
					interior_run = (zone.y + zone.zone_height - 1) - y2
				if(SOUTH)
					interior_run = y1 - zone.y
				if(EAST)
					interior_run = (zone.x + zone.zone_width - 1) - x2
				if(WEST)
					interior_run = x1 - zone.x
			interior_run = max(interior_run, 0)
		return bay_exit_strip_clear(x1, y1, x2, y2, check_z, exit_dir, interior_run + OVERMAP_BAY_EXIT_DEPTH)

	for(var/cardinal in GLOB.cardinals)
		if(bay_exit_face_clear(x1, y1, x2, y2, check_z, cardinal))
			return TRUE
	return FALSE

/// Per-column raycast for a designated exit direction. Every column (or row) of
/// the exit edge must reach an open turf (space, open floor, or open poddoor)
/// within `max_depth` tiles without first hitting a hard wall.
/obj/docking_port/mobile/proc/bay_exit_strip_clear(x1, y1, x2, y2, check_z, exit_dir, max_depth = OVERMAP_BAY_EXIT_DEPTH)
	var/dx = 0
	var/dy = 0
	switch(exit_dir)
		if(NORTH)
			dy = 1
		if(SOUTH)
			dy = -1
		if(EAST)
			dx = 1
		if(WEST)
			dx = -1
		else
			return TRUE

	// Walk each cell along the exit edge, then raycast outward from it.
	var/vertical = (exit_dir == NORTH || exit_dir == SOUTH)
	var/edge_start = vertical ? x1 : y1
	var/edge_end = vertical ? x2 : y2
	for(var/along in edge_start to edge_end)
		var/base_x = vertical ? along : (exit_dir == EAST ? x2 : x1)
		var/base_y = vertical ? (exit_dir == NORTH ? y2 : y1) : along
		var/column_clear = FALSE
		for(var/depth in 1 to max_depth)
			var/turf/probe = locate(base_x + dx * depth, base_y + dy * depth, check_z)
			if(isnull(probe))
				break
			if(overmap_bay_tile_is_wall(probe))
				break
			if(overmap_bay_tile_is_clear(probe))
				column_clear = TRUE
				break
		if(!column_clear)
			return FALSE
	return TRUE

/// Simple face check used when no exit direction is designated. The adjacent
/// strip (one tile outside the bounds) passes if every tile is open (space,
/// open floor, or open poddoor).
/obj/docking_port/mobile/proc/bay_exit_face_clear(x1, y1, x2, y2, check_z, face_dir)
	var/vertical = (face_dir == NORTH || face_dir == SOUTH)
	var/edge_start = vertical ? x1 : y1
	var/edge_end = vertical ? x2 : y2
	for(var/along in edge_start to edge_end)
		var/probe_x
		var/probe_y
		if(vertical)
			probe_x = along
			probe_y = (face_dir == NORTH ? y2 + 1 : y1 - 1)
		else
			probe_x = (face_dir == EAST ? x2 + 1 : x1 - 1)
			probe_y = along
		var/turf/probe = locate(probe_x, probe_y, check_z)
		if(!overmap_bay_tile_is_clear(probe))
			return FALSE
	return TRUE

#undef OVERMAP_BAY_EXIT_DEPTH
