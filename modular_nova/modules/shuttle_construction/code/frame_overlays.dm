/// Smoothed lattice overlays for shuttle frame rods anchored on existing turfs.
GLOBAL_LIST_INIT(shuttle_frame_overlays_by_turf, list())

/// Re-exposes shuttle frame rods after built plating is deconstructed (scraped) back down to
/// the underlying landing-pad turf, restoring the rod source + overlay so it is buildable again.
/// Only fires when a top turf layer was removed and the result is a floor still in the frame;
/// space lattices scrape down to space (non-floor) and are therefore unaffected.
///
/// `previous_type` is the turf type that was scraped away. Scraping a tiled floor onto hull
/// plating must keep rods hidden; scraping hull plating onto a landing-pad (including pad
/// plating) must restore SHUTTLE_ROD_TRAIT_SOURCE.
/proc/shuttle_construction_turf_reexpose_rods(turf/new_turf, list/trait_sources, is_uncovering, previous_type)
	if(!is_uncovering)
		return
	if(!isfloorturf(new_turf))
		return
	if(SHUTTLE_ROD_TRAIT_SOURCE in trait_sources)
		return
	// Tile → hull plating: rods stay hidden under the remaining hull layer.
	if(isplatingturf(new_turf) && previous_type && !ispath(previous_type, /turf/open/floor/plating))
		return
	new_turf.AddElementTrait(TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE, /datum/element/shuttle_construction_turf)
	update_shuttle_frame_overlay(new_turf)
	update_shuttle_frame_neighbor_overlays(new_turf)

/proc/shuttle_construction_turf_overlay_attached(turf/target)
	if(!HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return
	update_shuttle_frame_overlay(target)
	update_shuttle_frame_neighbor_overlays(target)

/proc/shuttle_construction_turf_overlay_detached(turf/target)
	if(HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return
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
	if(!isturf(target) || !HAS_TRAIT_FROM(target, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		remove_shuttle_frame_overlay(target)
		return
	remove_shuttle_frame_overlay(target)
	var/bitmask = calculate_shuttle_frame_lattice_bitmask(target)
	var/mutable_appearance/rod_overlay = mutable_appearance('modular_nova/modules/shuttle_construction/icons/ship_plating.dmi', "lattice-[bitmask]", LATTICE_LAYER, target, FLOOR_PLANE)
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
