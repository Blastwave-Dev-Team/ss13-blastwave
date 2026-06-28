/// Anchors shuttle frame rods into existing plating or floor tiles for custom shuttle construction.
/// Returns TRUE if handled, FALSE to fall through to other rod behavior.
/turf/open/proc/build_shuttle_frame_with_rods(obj/item/stack/rods/shuttle/used_rods, mob/user)
	if(!istype(used_rods))
		return FALSE
	if(HAS_TRAIT(src, TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		balloon_alert(user, "already part of a shuttle frame!")
		return TRUE
	if(istype(loc, /area/shuttle))
		return FALSE
	if(!isfloorturf(src))
		return FALSE
	if(istype(src, /turf/open/floor/plating/reinforced) || istype(src, /turf/open/floor/plating/foam))
		return FALSE
	if(locate(/obj/structure/lattice) in src)
		balloon_alert(user, "lattice already here!")
		return TRUE
	if(!used_rods.use(1))
		balloon_alert(user, "need a shuttle frame rod!")
		return TRUE
	playsound(src, 'sound/items/weapons/genhit.ogg', 50, TRUE)
	AddElementTrait(TRAIT_SHUTTLE_CONSTRUCTION_TURF, REF(used_rods), /datum/element/shuttle_construction_turf)
	to_chat(user, span_notice("You anchor shuttle frame rods into the [name]."))
	return TRUE
