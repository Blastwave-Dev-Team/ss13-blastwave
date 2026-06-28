/// Smoothed lattice overlays for shuttle frame rods anchored on existing turfs.
GLOBAL_LIST_INIT(shuttle_frame_overlays_by_turf, list())

/proc/shuttle_construction_turf_overlay_attached(turf/target)
	update_shuttle_frame_overlay(target)
	update_shuttle_frame_neighbor_overlays(target)

/proc/shuttle_construction_turf_overlay_detached(turf/target)
	remove_shuttle_frame_overlay(target)
	update_shuttle_frame_neighbor_overlays(target)

/proc/calculate_shuttle_frame_lattice_bitmask(turf/center)
	var/bitmask = NONE
	if(HAS_TRAIT(get_step(center, NORTH), TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		bitmask |= NORTH_JUNCTION
	if(HAS_TRAIT(get_step(center, SOUTH), TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		bitmask |= SOUTH_JUNCTION
	if(HAS_TRAIT(get_step(center, EAST), TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		bitmask |= EAST_JUNCTION
	if(HAS_TRAIT(get_step(center, WEST), TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		bitmask |= WEST_JUNCTION
	if(bitmask & NORTH_JUNCTION && bitmask & EAST_JUNCTION)
		bitmask |= NORTHEAST_JUNCTION
	if(bitmask & SOUTH_JUNCTION && bitmask & EAST_JUNCTION)
		bitmask |= SOUTHEAST_JUNCTION
	if(bitmask & SOUTH_JUNCTION && bitmask & WEST_JUNCTION)
		bitmask |= SOUTHWEST_JUNCTION
	if(bitmask & NORTH_JUNCTION && bitmask & WEST_JUNCTION)
		bitmask |= NORTHWEST_JUNCTION
	return bitmask

/proc/update_shuttle_frame_overlay(turf/target)
	if(!isturf(target) || !HAS_TRAIT(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		remove_shuttle_frame_overlay(target)
		return
	remove_shuttle_frame_overlay(target)
	var/bitmask = calculate_shuttle_frame_lattice_bitmask(target)
	var/mutable_appearance/rod_overlay = mutable_appearance('icons/obj/smooth_structures/lattice.dmi', "lattice-[bitmask]", LATTICE_LAYER)
	rod_overlay.plane = FLOOR_PLANE
	target.add_overlay(rod_overlay)
	GLOB.shuttle_frame_overlays_by_turf[target] = rod_overlay

/proc/remove_shuttle_frame_overlay(turf/target)
	var/mutable_appearance/old_overlay = GLOB.shuttle_frame_overlays_by_turf[target]
	if(!old_overlay)
		return
	target.cut_overlay(old_overlay)
	GLOB.shuttle_frame_overlays_by_turf -= target

/proc/update_shuttle_frame_neighbor_overlays(turf/center)
	for(var/dir in GLOB.alldirs)
		var/turf/neighbor = get_step(center, dir)
		if(!neighbor || !HAS_TRAIT(neighbor, TRAIT_SHUTTLE_CONSTRUCTION_TURF))
			continue
		update_shuttle_frame_overlay(neighbor)
