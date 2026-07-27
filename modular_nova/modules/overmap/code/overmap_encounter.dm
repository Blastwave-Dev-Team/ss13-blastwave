// MODULE ID: OVERMAP
// Dynamic encounter objects. These appear on the overmap grid and lazily load
// an explorable full Z-level (shared site generator: ruin cluster + LZs) when a
// ship docks at them. Once the ship undocks and no living mobs remain, the level
// is soft-cleared into a reuse pool and the encounter relocates.

/obj/structure/overmap/dynamic
	name = "weak energy signature"
	desc = "A very weak energy signal. It may not still be here if you leave it."
	icon_state = "strange_event"
	/// Full content Z owned by this marker (one marker ↔ one Z).
	var/list/linked_levels
	/// Primary ruin when this encounter loaded a solo; null for clusters.
	var/datum/map_template/ruin/ruin_template
	/// All ruin templates loaded onto this encounter's Z.
	var/list/datum/map_template/ruin/member_templates
	/// Template ids for every ruin on this Z.
	var/list/member_template_ids
	/// If TRUE, the level will not be unloaded when the ship undocks.
	var/preserve_level = FALSE

/obj/structure/overmap/dynamic/Initialize(mapload, _id)
	. = ..()
	choose_level_type()

/obj/structure/overmap/dynamic/Destroy()
	if(length(linked_levels) && !preserve_level)
		for(var/z_value in linked_levels)
			// Timer, not INVOKE_ASYNC: a spawn inherits src and would hold this
			// encounter alive for the length of the Z sweep. See the open-space
			// site's Destroy() for the full explanation.
			addtimer(CALLBACK(SSovermap, TYPE_PROC_REF(/datum/controller/subsystem/overmap, recycle_overmap_content_z), z_value), 0)
	linked_levels = null
	ruin_template = null
	member_templates = null
	member_template_ids = null
	return ..()

/// Space-only encounter flavor (no planetary ruin pools).
/obj/structure/overmap/dynamic/proc/choose_level_type()
	switch(rand(0, 2))
		if(0)
			name = "weak energy signal"
			desc = "A very weak energy signal emanating from space."
		if(1)
			name = "debris field"
			desc = "Metallic debris detected. Possible wreckage."
		if(2)
			name = "uncharted body"
			desc = "An uncharted mass with unknown composition."

/// Load the explorable Z-level for a visiting ship via the shared content generator.
/obj/structure/overmap/dynamic/proc/load_level(obj/docking_port/mobile/visiting_shuttle)
	if(length(linked_levels))
		return
	if(!SSovermap.load_dynamic_encounter(src))
		return SSovermap.last_encounter_spawn_error || "FATAL NAVIGATION ERROR. Astrogation solution collapsed — withdraw and re-approach."
	if(!length(linked_levels))
		return "BEACON LOCK FAILED. Survey telemetry could not confirm a docking corridor on the generated footprint — abort approach."

/// Attempt to unload after a ship undocks. Will not unload if living mobs with
/// minds are still present on the content Z.
/obj/structure/overmap/dynamic/proc/unload_level()
	if(preserve_level)
		return
	if(!length(linked_levels))
		return
	var/content_z = linked_levels[1]
	for(var/mob/living/L as anything in GLOB.mob_living_list)
		if(L.z != content_z || !L.mind)
			continue
		return
	forceMove(SSovermap.get_unused_overmap_square())
	choose_level_type()
	SSovermap.recycle_overmap_content_z(content_z)
	linked_levels = null
	ruin_template = null
	member_templates = null
	member_template_ids = null
