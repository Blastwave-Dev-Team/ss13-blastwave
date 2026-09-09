// MODULE ID: OVERMAP
// Bay-exit validation. Prevents launching a shuttle out of a fully enclosed
// station bay (which would clip through walls). At undock time the shuttle must
// have a clear path to space along at least one edge of its bounding rectangle.
//
// If the shuttle is parked in a player-built landing zone whose controller
// designated an exit direction, only that edge is validated. Otherwise all four
// faces are tried and any one clear face passes. Both cases run the same
// per-column raycast: a column is clear if it travels OVERMAP_BAY_EXIT_DEPTH
// tiles without hitting a wall or closed blast door, or reaches space sooner.
//
// Interior open floor is traversed rather than counted as arrival. Treating it as
// arrival is what previously let a ship launch out of a sealed hangar, since the
// tile beside the hull is always open floor.

/// How many tiles outward the per-column raycast probes before declaring a column clear.
#define OVERMAP_BAY_EXIT_DEPTH 10

/// Dense decor typepaths ignored by takeoff corridor / bay-exit checks.
/// Subtypes match. Append at runtime or in a module init to extend:
/// `GLOB.overmap_bay_exit_ignore += /obj/structure/foo`
GLOBAL_LIST_INIT(overmap_bay_exit_ignore, list(
	/obj/structure/fence,
	/obj/structure/railing,
))

/// TRUE if `thing` is planetary/decorative clutter that should not block launch paths.
/proc/overmap_bay_exit_ignores(atom/thing)
	return is_type_in_list(thing, GLOB.overmap_bay_exit_ignore)

/// TRUE if `checked_turf` is a hard wall that blocks a launch path. Closed turfs,
/// closed blast doors, and anchored dense structures block; ordinary doors
/// (openable by hand), open floors, and whitelisted decor
/// (`GLOB.overmap_bay_exit_ignore`) do not.
/proc/overmap_bay_tile_is_wall(turf/checked_turf)
	if(isclosedturf(checked_turf))
		return TRUE
	for(var/obj/blocker in checked_turf)
		if(!blocker.density)
			continue
		// A closed blast door is a wall for launch purposes: it cannot be opened by hand, so a ship
		// parked behind one genuinely cannot leave. The helm has always claimed as much ("open the bay
		// doors before launching"); without this the raycast walks straight through it and the claim
		// is a lie. Ordinary airlocks stay passable, since anyone aboard can just open them.
		if(istype(blocker, /obj/machinery/door/poddoor))
			return TRUE
		if(istype(blocker, /obj/machinery/door))
			continue
		if(overmap_bay_exit_ignores(blocker))
			continue
		if(blocker.anchored)
			return TRUE
	return FALSE

/// TRUE if reaching `checked_turf` means the raycast is definitively outside and
/// can stop early. Only space qualifies: interior floor is something a ray must
/// travel *through*, not a destination, or a sealed bay reads as open at depth 1.
/// Planetary pads have no space turf nearby and instead pass by clearing the
/// full depth budget.
/proc/overmap_bay_tile_is_outside(turf/checked_turf)
	return isspaceturf(checked_turf)

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

	// No designated exit: any one face that raycasts clear is good enough. Same per-column
	// probe as the designated case, so an enclosed bay fails in every direction.
	for(var/cardinal in GLOB.cardinals)
		if(bay_exit_strip_clear(x1, y1, x2, y2, check_z, cardinal))
			return TRUE
	return FALSE

/// Per-column raycast. Every column (or row) of the exit edge must get `max_depth`
/// tiles out without hitting a hard wall, or reach space sooner. Interior floor and
/// open blast doors are traversed, not treated as arrival: that is what makes a
/// sealed bay fail while an open pad or planet surface passes.
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
		var/column_clear = TRUE
		for(var/depth in 1 to max_depth)
			var/turf/probe = locate(base_x + dx * depth, base_y + dy * depth, check_z)
			if(isnull(probe)) // Ran off the edge of the z-level with nothing in the way.
				break
			if(overmap_bay_tile_is_wall(probe))
				column_clear = FALSE
				break
			if(overmap_bay_tile_is_outside(probe))
				break
		if(!column_clear)
			return FALSE
	return TRUE

#undef OVERMAP_BAY_EXIT_DEPTH
