// MODULE ID: OVERMAP
// Landing zone landmarks. Mappers place these to define bounded rectangular
// regions where overmap-arriving shuttles may land. The nav console discovers
// zones on the target Z, filters by shuttle fit, and constrains placement.

/obj/effect/landmark/overmap_landing_zone
	name = "landing zone"
	icon = 'icons/effects/docking_ports.dmi'
	icon_state = "static"
	invisibility = INVISIBILITY_ABSTRACT
	resistance_flags = INDESTRUCTIBLE
	anchored = TRUE
	/// Display name shown in the nav console jump menu.
	var/zone_name = "Landing Zone"
	/// Width of the landing region in tiles (X axis).
	var/zone_width = 30
	/// Height of the landing region in tiles (Y axis).
	var/zone_height = 30
	/// Cardinal direction a docked shuttle must have a clear launch path toward.
	/// Read by the bay-exit check at undock time. NONE means "no designated exit"
	/// (bay-exit falls back to checking all four faces).
	var/exit_direction = NONE
	/// Overmap affiliation allowed to land here (`OVERMAP_AFFILIATION_*`).
	/// Null/empty = open to any affiliation (seeded/mapped zones default open).
	var/dock_affiliation
	/// TRUE on zones SSovermap scattered across a site Z, as opposed to one a mapper placed or
	/// a landing controller manages. Lets callers reason about the seeded set on its own.
	var/seeded = FALSE

/obj/effect/landmark/overmap_landing_zone/Initialize(mapload)
	. = ..()
	LAZYADD(SSovermap.landing_zones, src)

/obj/effect/landmark/overmap_landing_zone/Destroy()
	LAZYREMOVE(SSovermap.landing_zones, src)
	return ..()

/// Returns TRUE if a shuttle with the given width/height can fit within this zone
/// in at least one rotation (0 or 90 degrees).
/obj/effect/landmark/overmap_landing_zone/proc/can_fit_shuttle(shuttle_width, shuttle_height)
	if(shuttle_width <= zone_width && shuttle_height <= zone_height)
		return TRUE
	if(shuttle_height <= zone_width && shuttle_width <= zone_height)
		return TRUE
	return FALSE

/// First dir `shuttle` can sit in this zone, preferring the current facing
/// and then ±90. Same order as create_landing_zone_port(). NONE if none fit.
/obj/effect/landmark/overmap_landing_zone/proc/first_fitting_dir(obj/docking_port/mobile/shuttle)
	if(!shuttle)
		return NONE
	for(var/try_dir in list(shuttle.dir, turn(shuttle.dir, 90), turn(shuttle.dir, -90)))
		var/list/rel = shuttle.return_coords(0, 0, try_dir)
		var/ship_w = abs(rel[3] - rel[1]) + 1
		var/ship_h = abs(rel[4] - rel[2]) + 1
		if(ship_w <= zone_width && ship_h <= zone_height)
			return try_dir
	return NONE

/// Returns the center turf of this zone for camera eye placement.
/obj/effect/landmark/overmap_landing_zone/proc/get_center_turf()
	return locate(x + round(zone_width / 2), y + round(zone_height / 2), z)

/// Returns the first mobile shuttle whose footprint overlaps this zone's bbox
/// on the zone's Z, or null if the zone is clear. `ignore_port` is skipped so a
/// navigating shuttle does not count itself as an occupant.
/obj/effect/landmark/overmap_landing_zone/proc/get_occupant(obj/docking_port/mobile/ignore_port)
	var/zone_x2 = x + zone_width - 1
	var/zone_y2 = y + zone_height - 1
	for(var/obj/docking_port/mobile/port as anything in SSshuttle.mobile_docking_ports)
		if(port == ignore_port || port.z != z)
			continue
		var/list/bounds = port.return_coords()
		var/port_x1 = min(bounds[1], bounds[3])
		var/port_x2 = max(bounds[1], bounds[3])
		var/port_y1 = min(bounds[2], bounds[4])
		var/port_y2 = max(bounds[2], bounds[4])
		if(port_x1 <= zone_x2 && port_x2 >= x && port_y1 <= zone_y2 && port_y2 >= y)
			return port
	return null

/**
 * A one-shot stationary port centered in this zone for `shuttle`, facing the
 * zone's `exit_direction` (or the shuttle's current heading when the zone has
 * none), so the hull is rotated to launch out of the bay. The one landing path
 * shared by the helm, the registrar and the broker. Null when the shuttle does
 * not fit, the zone is occupied, or the footprint is blocked. The port deletes
 * itself after the shuttle next departs.
 */
/obj/effect/landmark/overmap_landing_zone/proc/create_landing_port(obj/docking_port/mobile/shuttle)
	if(!shuttle || get_occupant(shuttle))
		return null
	var/obj/docking_port/stationary/port = new()
	port.unregister()
	port.delete_after = TRUE
	port.name = zone_name
	port.shuttle_id = "[shuttle.shuttle_id]_lz"
	port.width = shuttle.width
	port.height = shuttle.height
	port.dwidth = shuttle.dwidth
	port.dheight = shuttle.dheight
	port.register(TRUE)
	port.setDir((exit_direction in GLOB.cardinals) ? exit_direction : shuttle.dir)
	port.forceMove(get_turf(src))
	var/turf/dest = overmap_centered_dock_turf(port, get_turf(src), zone_width, zone_height)
	if(!dest)
		qdel(port)
		return null
	port.forceMove(dest)
	if(!shuttle.check_dock(port, TRUE) || !SSovermap.dock_footprint_is_clear(port))
		qdel(port)
		return null
	return port

/**
 * Where `port` must stand for its footprint, in its current dir, to sit centered
 * in the `width` x `height` rectangle whose bottom-left is `origin`. `port` only
 * has to be on the map somewhere so its footprint can be measured around it.
 * Null when it does not fit.
 */
/proc/overmap_centered_dock_turf(obj/docking_port/port, turf/origin, width, height)
	if(!port || !origin || !port.x)
		return null
	var/list/bounds = port.return_coords()
	var/bbox_x1 = min(bounds[1], bounds[3])
	var/bbox_y1 = min(bounds[2], bounds[4])
	var/ship_w = max(bounds[1], bounds[3]) - bbox_x1 + 1
	var/ship_h = max(bounds[2], bounds[4]) - bbox_y1 + 1
	if(ship_w > width || ship_h > height)
		return null
	return locate(
		origin.x + round((width - ship_w) / 2) + port.x - bbox_x1,
		origin.y + round((height - ship_h) / 2) + port.y - bbox_y1,
		origin.z,
	)

/// Returns TRUE if the given bounding box (x1,y1 to x2,y2) is entirely within this zone.
/obj/effect/landmark/overmap_landing_zone/proc/contains_bbox(x1, y1, x2, y2, check_z)
	if(check_z != z)
		return FALSE
	var/zone_x1 = x
	var/zone_y1 = y
	var/zone_x2 = x + zone_width - 1
	var/zone_y2 = y + zone_height - 1
	return (x1 >= zone_x1 && y1 >= zone_y1 && x2 <= zone_x2 && y2 <= zone_y2)

/// Returns TRUE if the given turf lies within this zone's bounds.
/obj/effect/landmark/overmap_landing_zone/proc/contains_turf(turf/checked_turf)
	if(checked_turf.z != z)
		return FALSE
	return (checked_turf.x >= x && checked_turf.x <= x + zone_width - 1 && checked_turf.y >= y && checked_turf.y <= y + zone_height - 1)

/// Returns TRUE if the given turf lies within any registered overmap landing zone.
/// Landing zones grant implicit shuttle-docking permission, letting shuttle
/// blueprints finalize a frame there without station blueprints toggling
/// `allow_shuttle_docking` on the underlying area.
/proc/turf_in_overmap_landing_zone(turf/checked_turf)
	if(!checked_turf)
		return FALSE
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in SSovermap.landing_zones)
		if(zone.contains_turf(checked_turf))
			return TRUE
	return FALSE
