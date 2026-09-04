// MODULE ID: OVERMAP
// SSshuttle occupancy is per-port (`get_docked()` on the destination turf).
// Overmap LZ ports sit on a different tile, so a hangar can look empty while a
// hull already covers it. These helpers close that hole and give ERT shuttles
// a space-side fallback next to the station.

#define NEAR_STATION_SPACE_FALLBACK_RADIUS 48

/// TRUE when the axis-aligned bboxes from two `return_coords()` lists overlap.
/proc/docking_bboxes_overlap(list/first, list/second)
	if(length(first) < 4 || length(second) < 4)
		return FALSE
	var/first_x1 = min(first[1], first[3])
	var/first_y1 = min(first[2], first[4])
	var/first_x2 = max(first[1], first[3])
	var/first_y2 = max(first[2], first[4])
	var/second_x1 = min(second[1], second[3])
	var/second_y1 = min(second[2], second[4])
	var/second_x2 = max(second[1], second[3])
	var/second_y2 = max(second[2], second[4])
	return first_x1 <= second_x2 && first_x2 >= second_x1 && first_y1 <= second_y2 && first_y2 >= second_y1

/// TRUE if every tile of a `return_coords()` bbox sits inside the playable map.
/proc/docking_bbox_is_on_map(list/coords)
	if(length(coords) < 4)
		return FALSE
	var/min_x = min(coords[1], coords[3])
	var/min_y = min(coords[2], coords[4])
	var/max_x = max(coords[1], coords[3])
	var/max_y = max(coords[2], coords[4])
	return min_x >= TRANSITIONEDGE && min_y >= TRANSITIONEDGE && max_x <= world.maxx + 1 - TRANSITIONEDGE && max_y <= world.maxy + 1 - TRANSITIONEDGE

/// TRUE if the hull bbox, or the one-tile halo around it, touches `/area/station`.
/proc/docking_bbox_clips_station(list/coords, z_level)
	if(length(coords) < 4 || !z_level)
		return TRUE
	var/min_x = max(1, min(coords[1], coords[3]) - 1)
	var/min_y = max(1, min(coords[2], coords[4]) - 1)
	var/max_x = min(world.maxx, max(coords[1], coords[3]) + 1)
	var/max_y = min(world.maxy, max(coords[2], coords[4]) + 1)
	for(var/turf/tile as anything in block(min_x, min_y, z_level, max_x, max_y, z_level))
		if(istype(tile.loc, /area/station))
			return TRUE
	return FALSE

/// TRUE if `coords` on `z_level` overlaps another registered mobile shuttle.
/proc/docking_bbox_overlaps_other_mobile(list/coords, z_level, obj/docking_port/mobile/ignore)
	if(!length(coords) || !z_level)
		return FALSE
	for(var/obj/docking_port/mobile/other as anything in SSshuttle.mobile_docking_ports)
		if(other == ignore || QDELETED(other) || other.z != z_level)
			continue
		if(docking_bboxes_overlap(coords, other.return_coords()))
			return TRUE
	return FALSE

/// TRUE if this port's footprint overlaps another mobile shuttle on the same Z.
/obj/docking_port/proc/overlaps_other_mobile(obj/docking_port/mobile/ignore, list/our_coords)
	return docking_bbox_overlaps_other_mobile(our_coords || return_coords(), z, ignore)

/// ERT (and SolFed ERT) hulls must still arrive if the hangar is occupied.
/obj/docking_port/mobile/proc/uses_near_station_space_fallback()
	if(findtext(shuttle_id, "ert") || findtext(shuttle_id, "solfed"))
		return TRUE
	for(var/template_id in SSmapping.shuttle_templates)
		var/datum/map_template/shuttle/ert/template = SSmapping.shuttle_templates[template_id]
		if(!istype(template))
			continue
		if(shuttle_id == template_id || shuttle_id == template.suffix || shuttle_id == "[template.port_id]_[template.suffix]")
			return TRUE
	return FALSE

/// If dest is occupied, rematch ERT to whiteship or a stamped space dock.
/obj/docking_port/mobile/proc/maybe_divert_occupied_dock(obj/docking_port/stationary/destination_port)
	if(!destination_port)
		return destination_port
	var/status = canDock(destination_port)
	if(status != SHUTTLE_SOMEONE_ELSE_DOCKED)
		return destination_port
	var/obj/docking_port/stationary/fallback = resolve_near_station_space_fallback(destination_port, status)
	if(!fallback)
		return destination_port
	log_shuttle("Shuttle [src] diverted from [destination_port] ([destination_port.shuttle_id]) to [fallback] ([fallback.shuttle_id]) because the destination was occupied.")
	message_admins("Shuttle [src] diverted to near-station space; [destination_port] was occupied.")
	return fallback

/// When `blocked_port` failed for occupancy, return a clear near-station space
/// dock the shuttle can actually land at, or null.
/obj/docking_port/mobile/proc/resolve_near_station_space_fallback(obj/docking_port/stationary/blocked_port, dock_status)
	if(dock_status != SHUTTLE_SOMEONE_ELSE_DOCKED || !uses_near_station_space_fallback())
		return null
	var/obj/docking_port/stationary/whiteship = SSshuttle.getDock("whiteship_home")
	if(whiteship && whiteship != blocked_port && check_dock(whiteship, TRUE))
		return whiteship
	return create_near_station_space_dock(blocked_port)

/// Search station-adjacent space and stamp a delete_after dock matching this hull.
/obj/docking_port/mobile/proc/create_near_station_space_dock(atom/near)
	var/turf/origin = get_near_station_space_search_origin(near)
	if(!origin)
		return null
	var/turf/anchor = find_space_dock_anchor(origin)
	if(!anchor)
		return null
	return create_space_dock_at(anchor)

/obj/docking_port/mobile/proc/get_near_station_space_search_origin(atom/near)
	var/turf/near_turf = get_turf(near)
	if(near_turf && is_station_level(near_turf.z))
		return near_turf
	var/obj/docking_port/stationary/whiteship = SSshuttle.getDock("whiteship_home")
	if(whiteship && is_station_level(whiteship.z))
		return get_turf(whiteship)
	var/list/station_zs = SSmapping.levels_by_trait(ZTRAIT_STATION)
	if(!length(station_zs))
		return null
	return locate(round(world.maxx / 2), round(world.maxy / 2), station_zs[1])

/// Expanding chebyshev rings around `origin` until a clear space bbox fits.
/obj/docking_port/mobile/proc/find_space_dock_anchor(turf/origin)
	if(!origin)
		return null
	if(space_anchor_is_clear(origin, dir))
		return origin
	for(var/radius in 1 to NEAR_STATION_SPACE_FALLBACK_RADIUS)
		for(var/dx in -radius to radius)
			for(var/dy in -radius to radius)
				if(max(abs(dx), abs(dy)) != radius)
					continue
				var/turf/candidate = locate(origin.x + dx, origin.y + dy, origin.z)
				if(space_anchor_is_clear(candidate, dir))
					return candidate
		CHECK_TICK
	return null

/// TRUE if a dock of this hull's size at `anchor` is all space and unoccupied.
/obj/docking_port/mobile/proc/space_anchor_is_clear(turf/anchor, dock_dir)
	if(!anchor || !is_clear_space_turf(anchor))
		return FALSE
	if(SSovermap?.overmap_z && anchor.z == SSovermap.overmap_z)
		return FALSE
	var/list/coords = return_coords(anchor.x, anchor.y, dock_dir)
	if(!docking_bbox_is_on_map(coords) || docking_bbox_clips_station(coords, anchor.z))
		return FALSE
	var/min_x = min(coords[1], coords[3])
	var/min_y = min(coords[2], coords[4])
	var/max_x = max(coords[1], coords[3])
	var/max_y = max(coords[2], coords[4])
	var/list/tiles = block(min_x, min_y, anchor.z, max_x, max_y, anchor.z)
	if(length(tiles) != (max_x - min_x + 1) * (max_y - min_y + 1))
		return FALSE
	for(var/turf/tile as anything in tiles)
		if(!is_clear_space_turf(tile))
			return FALSE
	return !docking_bbox_overlaps_other_mobile(coords, anchor.z, src)

/proc/is_clear_space_turf(turf/tile)
	if(!isspaceturf(tile) || istype(tile, /turf/open/space/transit) || istype(tile.loc, /area/station))
		return FALSE
	for(var/atom/movable/thing as anything in tile)
		if(iseffect(thing) || istype(thing, /obj/docking_port) || isliving(thing))
			continue
		return FALSE
	return TRUE

/obj/docking_port/mobile/proc/create_space_dock_at(turf/anchor)
	if(!anchor)
		return null
	var/obj/docking_port/stationary/port = new(anchor)
	port.delete_after = TRUE
	port.name = "Near-Station Space"
	port.shuttle_id = "[shuttle_id]_space_fallback"
	port.width = width
	port.height = height
	port.dwidth = dwidth
	port.dheight = dheight
	port.setDir(dir)
	if(!docking_bbox_is_on_map(port.return_coords()) || docking_bbox_clips_station(port.return_coords(), port.z) || !check_dock(port, TRUE))
		qdel(port, force = TRUE)
		return null
	return port

/// Occupied hangars stay selectable on ERT consoles so request() can divert.
/obj/machinery/computer/shuttle/get_valid_destinations()
	. = ..()
	var/obj/docking_port/mobile/mobile = SSshuttle.getShuttle(shuttleId)
	if(!mobile?.uses_near_station_space_fallback())
		return
	var/list/destination_list = params2list(possible_destinations)
	var/list/already = list()
	for(var/list/entry as anything in .)
		already[entry["id"]] = TRUE
	for(var/obj/docking_port/stationary/port as anything in SSshuttle.stationary_docking_ports)
		if(already[port.shuttle_id] || !destination_list.Find(port.port_destinations))
			continue
		if(mobile.canDock(port) != SHUTTLE_SOMEONE_ELSE_DOCKED)
			continue
		. += list(list(id = port.shuttle_id, name = "[port.name] (occupied, nearby landing)"))

#undef NEAR_STATION_SPACE_FALLBACK_RADIUS
