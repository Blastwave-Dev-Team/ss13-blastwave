// MODULE ID: OVERMAP
// Dynamic encounter objects. These appear on the overmap grid and lazily load
// an explorable Z-level (with terrain generation + ruin templates) when a ship
// docks at them. Once the ship undocks and no living mobs remain, the level is
// unloaded and the encounter relocates to a new random tile.

/obj/structure/overmap/dynamic
	name = "weak energy signature"
	desc = "A very weak energy signal. It may not still be here if you leave it."
	icon_state = "strange_event"
	/// The active turf reservation, if one has been loaded.
	var/datum/turf_reservation/reserve
	/// Primary stationary docking port in the reserve.
	var/obj/docking_port/stationary/reserve_dock
	/// Secondary stationary docking port in the reserve.
	var/obj/docking_port/stationary/reserve_dock_secondary
	/// If TRUE, the level will not be unloaded when the ship undocks.
	var/preserve_level = FALSE
	/// Planet flavor for terrain generation (DYNAMIC_WORLD_* or null for space).
	var/planet

/obj/structure/overmap/dynamic/Initialize(mapload, _id)
	. = ..()
	choose_level_type()

/obj/structure/overmap/dynamic/Destroy()
	QDEL_NULL(reserve)
	reserve_dock = null
	reserve_dock_secondary = null
	return ..()

/// Randomizes the encounter's flavor between planet types and space ruins.
/obj/structure/overmap/dynamic/proc/choose_level_type()
	var/chosen = rand(0, 4)
	switch(chosen)
		if(0)
			name = "weak energy signal"
			desc = "A very weak energy signal emanating from space."
			planet = null
		if(1)
			name = "volcanic signature"
			desc = "Thermal readings suggest volcanic activity."
			planet = DYNAMIC_WORLD_LAVA
		if(2)
			name = "cryogenic anomaly"
			desc = "Subzero temperature readings from this region."
			planet = DYNAMIC_WORLD_ICE
		if(3)
			name = "debris field"
			desc = "Metallic debris detected. Possible wreckage."
			planet = null
		if(4)
			name = "uncharted body"
			desc = "An uncharted planetoid with unknown surface conditions."
			planet = DYNAMIC_WORLD_LAVA

/// Load the explorable Z-level for a visiting ship. Delegates to
/// SSovermap.spawn_dynamic_encounter() for the heavy lifting.
/obj/structure/overmap/dynamic/proc/load_level(obj/docking_port/mobile/visiting_shuttle)
	if(reserve)
		return
	if(!COOLDOWN_FINISHED(SSovermap, encounter_cooldown))
		return "WARNING! Stellar interference is restricting flight in this area. Try again in [round(COOLDOWN_TIMELEFT(SSovermap, encounter_cooldown) / 10)] seconds."
	var/datum/turf_reservation/new_reserve = SSovermap.spawn_dynamic_encounter(planet, TRUE, id, visiting_shuttle = visiting_shuttle)
	if(!new_reserve)
		return "FATAL NAVIGATION ERROR. Please try again later."
	reserve = new_reserve
	reserve_dock = SSshuttle.getDock("[OVERMAP_DOCK_PREFIX]_[id]")
	reserve_dock_secondary = SSshuttle.getDock("[OVERMAP_FERRY_PREFIX]_[id]")

/// Attempt to unload the reserve after a ship undocks. Will not unload if
/// living mobs with minds are still present on the reserved turfs.
/obj/structure/overmap/dynamic/proc/unload_level()
	if(preserve_level)
		return
	if(!reserve)
		return
	for(var/turf/T in reserve.reserved_turfs)
		var/mob/living/L = locate() in T
		if(L?.mind)
			return
	forceMove(SSovermap.get_unused_overmap_square())
	choose_level_type()
	QDEL_NULL(reserve)
	reserve_dock = null
	reserve_dock_secondary = null
