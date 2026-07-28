// MODULE ID: OVERMAP
// Station-keeping autopilot. When engaged, computes the required orbital
// velocity for the ship's current position relative to the nearest gravity
// well, then applies corrective thrust each tick to maintain a circular orbit.

/// Station-keeping logic, invoked from ship's physics_tick when station_keeping is TRUE.
/// Modifies vel_x/vel_y directly to converge on orbital velocity.
/obj/structure/overmap/ship/proc/apply_station_keeping(dt)
	if(!station_keeping)
		return
	var/ship_px = get_overmap_abs_px()
	var/ship_py = get_overmap_abs_py()
	var/obj/structure/overmap/celestial/nearest = null
	var/nearest_dist_sq = INFINITY
	for(var/obj/structure/overmap/celestial/body as anything in SSovermap.gravity_wells)
		var/dx = body.px - ship_px
		var/dy = body.py - ship_py
		var/dist_sq = dx * dx + dy * dy
		if(dist_sq > body.soi_sq)
			continue
		if(dist_sq < nearest_dist_sq)
			nearest_dist_sq = dist_sq
			nearest = body
	if(!nearest)
		return

	var/dx = nearest.px - ship_px
	var/dy = nearest.py - ship_py
	var/dist = sqrt(nearest_dist_sq)
	if(dist < 1)
		return

	// Required orbital velocity: perpendicular to radius, magnitude = sqrt(GM/r)
	var/v_orbital = nearest.orbital_velocity(dist)
	// Convert from pixel-space speed to tiles/second
	var/v_orbital_tiles = v_orbital / ICON_SIZE_ALL

	// Perpendicular direction (counterclockwise)
	var/perp_x = -dy / dist
	var/perp_y = dx / dist

	// Target velocity for circular orbit
	var/target_vx = perp_x * v_orbital_tiles
	var/target_vy = perp_y * v_orbital_tiles

	// Apply corrective thrust (throttled by maneuverability)
	var/correction_rate = OVERMAP_MANEUVERABILITY * dt * 0.5
	vel_x += (target_vx - vel_x) * min(correction_rate, 1)
	vel_y += (target_vy - vel_y) * min(correction_rate, 1)
