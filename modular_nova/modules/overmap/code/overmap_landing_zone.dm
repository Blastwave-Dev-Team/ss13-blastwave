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

/// Returns TRUE if the given bounding box (x1,y1 to x2,y2) is entirely within this zone.
/obj/effect/landmark/overmap_landing_zone/proc/contains_bbox(x1, y1, x2, y2, check_z)
	if(check_z != z)
		return FALSE
	var/zone_x1 = x
	var/zone_y1 = y
	var/zone_x2 = x + zone_width - 1
	var/zone_y2 = y + zone_height - 1
	return (x1 >= zone_x1 && y1 >= zone_y1 && x2 <= zone_x2 && y2 <= zone_y2)
