/**
 * Whether this turf can hold shuttle frame rods.
 *
 * A landing zone is whatever ground the pad happens to cover, so every kind
 * qualifies: station plating, the bare space of an orbital pad, and the dirt, sand,
 * snow, ice, or wading-depth water of a planetary one. None of them are a hull yet
 * - the plating phase is what turns a framed tile into one - so the only surfaces
 * ruled out are the ones that cannot carry plating over them.
 */
/turf/open/proc/can_anchor_shuttle_frame_rods()
	if(istype(src, /turf/open/floor/plating/reinforced) || istype(src, /turf/open/floor/plating/foam))
		return FALSE
	return isfloorturf(src) || is_space_or_openspace(src) || ismiscturf(src)

/// Water you can stand in is ground like any other, but a tile deep enough to swim
/// and drown in is not a surface a hull can be anchored to.
/turf/open/water/can_anchor_shuttle_frame_rods()
	return !is_swimming_tile

/// Anchors shuttle frame rods for custom shuttle construction.
/// Returns TRUE if handled, FALSE to fall through to other rod behavior.
/turf/open/proc/build_shuttle_frame_with_rods(obj/item/stack/rods/shuttle/used_rods, mob/user)
	if(!istype(used_rods))
		return FALSE
	if(HAS_TRAIT(src, TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		balloon_alert(user, "already part of a shuttle frame!")
		return TRUE
	if(istype(loc, /area/shuttle))
		return FALSE
	if(!can_anchor_shuttle_frame_rods())
		return FALSE
	if(locate(/obj/structure/lattice) in src)
		balloon_alert(user, "lattice already here!")
		return TRUE
	// Bare space has no surface to carry an inlaid rod overlay. Preserve the
	// ordinary lattice construction path so it has a real, inspectable support.
	if(is_space_or_openspace(src))
		var/rod_count = used_rods.get_amount()
		build_with_rods(used_rods, user)
		return used_rods.get_amount() < rod_count \
			&& !!(locate(/obj/structure/lattice/ship) in src)
	if(!used_rods.use(1))
		balloon_alert(user, "need a shuttle frame rod!")
		return TRUE
	playsound(src, 'sound/items/weapons/genhit.ogg', 50, TRUE)
	AddElementTrait(TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE, /datum/element/shuttle_construction_turf)
	to_chat(user, span_notice("You anchor shuttle frame rods into the [name]."))
	return TRUE

/// Cuts exposed shuttle frame rods with wirecutters / jaws cutter mode.
/// Returns TRUE if handled (including cancelled do_after), FALSE to fall through.
/turf/open/floor/proc/cut_shuttle_frame_rods(mob/living/user, obj/item/tool)
	if(!HAS_TRAIT_FROM(src, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return FALSE
	balloon_alert(user, "cutting frame rods...")
	if(!tool.use_tool(src, user, 1 SECONDS, volume = 50))
		return TRUE
	if(!HAS_TRAIT_FROM(src, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return TRUE
	REMOVE_TRAIT(src, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE)
	remove_shuttle_frame_overlay(src)
	update_shuttle_frame_neighbor_overlays(src)
	if(depth_to_find_baseturf(/turf/baseturf_skipover/shuttle))
		remove_baseturfs_from_typecache(typecacheof(/turf/baseturf_skipover/shuttle))
	new /obj/item/stack/rods/shuttle(src, 1)
	balloon_alert(user, "frame rods removed")
	return TRUE
