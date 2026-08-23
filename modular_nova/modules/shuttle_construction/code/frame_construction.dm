// MODULE ID: SHUTTLE_CONSTRUCTION
// Construction helpers for building plating over shuttle frame rods.
// Handles both hand-tiling and RCD paths, clearing the rod overlay
// after plating is laid while keeping the turf in the shuttle frame.

/// Intercepts iron tile placement on a rod-frame turf to build plating.
/// Returns TRUE if handled, FALSE to fall through to normal tile behavior.
/turf/open/proc/shuttle_frame_build_plating_with_tile(obj/item/stack/tile/used_tile, mob/user)
	var/obj/structure/lattice/ship/ship_lattice = locate() in src
	if(ship_lattice)
		if(!ismetaltile(used_tile))
			return FALSE
		var/tile_count = used_tile.get_amount()
		build_with_floor_tiles(used_tile, user)
		return used_tile.get_amount() < tile_count \
			&& istype(get_turf(src), /turf/open/floor/plating/ship)
	if(!HAS_TRAIT_FROM(src, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return FALSE
	if(!ismetaltile(used_tile))
		return FALSE
	if(!used_tile.use(1))
		balloon_alert(user, "need a floor tile!")
		return TRUE
	playsound(src, 'sound/items/weapons/genhit.ogg', 50, TRUE)
	var/turf/open/floor/plating/new_plating = place_on_top(/turf/open/floor/plating/ship, flags = CHANGETURF_INHERIT_AIR)
	REMOVE_TRAIT(new_plating, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE)
	remove_shuttle_frame_overlay(new_plating)
	to_chat(user, span_notice("You lay plating over the shuttle frame rods."))
	return TRUE

/// Returns RCD vals for building plating on a rod-frame turf.
/// Returns null if this turf shouldn't intercept the RCD.
/turf/open/proc/shuttle_frame_rcd_vals(obj/item/construction/rcd/the_rcd)
	if(!HAS_TRAIT_FROM(src, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return null
	if(the_rcd.mode != RCD_TURF)
		return null
	if(the_rcd.rcd_design_path != /turf/open/floor/plating/rcd)
		return null
	return list("delay" = 0, "cost" = 1)

/// Performs the RCD plating build on a rod-frame turf.
/// Returns TRUE if handled, FALSE to fall through.
/turf/open/proc/shuttle_frame_rcd_act(list/rcd_data)
	if(!HAS_TRAIT_FROM(src, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return FALSE
	if(rcd_data[RCD_DESIGN_MODE] != RCD_TURF)
		return FALSE
	if(rcd_data[RCD_DESIGN_PATH] != /turf/open/floor/plating/rcd)
		return FALSE
	var/turf/open/floor/plating/new_plating = place_on_top(/turf/open/floor/plating/ship, flags = CHANGETURF_INHERIT_AIR)
	REMOVE_TRAIT(new_plating, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE)
	remove_shuttle_frame_overlay(new_plating)
	return TRUE
