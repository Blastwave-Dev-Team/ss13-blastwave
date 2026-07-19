// MODULE ID: OVERMAP
// SSovermap allocates a dedicated Z-level for the overmap grid and is the
// owner of the overmap object registry and helper procs. Per the
// implementation plan, M1 only delivers Z allocation, a programmatic
// 20x20 grid, and a star at the center; static POIs (M2), ship binding
// (M3) and onward extend this subsystem.

SUBSYSTEM_DEF(overmap)
	name = "Overmap"
	wait = OVERMAP_PHYSICS_WAIT
	dependencies = list(
		/datum/controller/subsystem/mapping,
		/datum/controller/subsystem/shuttle,
	)
	ss_flags = SS_BACKGROUND
	runlevels = RUNLEVEL_SETUP | RUNLEVEL_GAME

	/// Width/height of the overmap grid (square).
	var/size = OVERMAP_DIMENSIONS
	/// All overmap objects in the world (stars, levels, ships, events).
	var/list/overmap_objects
	/// All currently registered ship objects (subset of overmap_objects).
	var/list/simulated_ships
	/// Celestial bodies that exert gravitational pull.
	var/static/list/obj/structure/overmap/gravity_wells = list()
	/// All currently registered helm consoles. Used to rebind helms when a
	/// shuttle is loaded after SSovermap init (e.g. the emergency shuttle).
	var/list/helms
	/// All currently registered overmap-aware nav consoles (M6).
	var/list/navs
	/// All active overmap event objects.
	var/list/events
	/// The station-tied overmap object. Set by `/level/main` on init.
	var/obj/structure/overmap/level/main/main
	/// Z-value of the dedicated overmap grid. Looked up via `levels_by_trait`
	/// in case other code needs it post-init.
	var/overmap_z
	/// Generator strategy. Read from config; falls back to RANDOM.
	var/generator_type = OVERMAP_GENERATOR_RANDOM
	/// Orbital ring lookup table (SOLAR mode only). Keyed by string radius
	/// ("3", "4", ...), values are lists of turfs at that euclidean distance
	/// from the star center. "unsorted" key holds remainders.
	var/list/radius_tiles = list()
	/// Global cooldown on dynamic encounter loading.
	COOLDOWN_DECLARE(encounter_cooldown)
	/// Template IDs already placed as named sites — excluded from dynamic picks.
	var/list/placed_site_template_ids = list()
	/// Whether the syndicate beacon has revealed the NT station to DS2.
	var/station_revealed_to_ds2 = FALSE
	/// All registered landing zone landmarks (for nav console zone discovery).
	var/list/landing_zones
	/// Helm-facing reason when dynamic encounter generation last failed.
	var/last_encounter_spawn_error
	/// Soft-cleared content Zs available for reuse by lazy dynamic encounters.
	var/list/reusable_content_zs = list()

/datum/controller/subsystem/overmap/Initialize()
	generator_type = CONFIG_GET(string/overmap_generator_type)
	if(!generator_type || generator_type == "")
		generator_type = OVERMAP_GENERATOR_RANDOM
	allocate_overmap_zlevel()
	build_grid()
	place_star()
	if(generator_type == OVERMAP_GENERATOR_SOLAR)
		calculate_orbital_rings()
	create_map()
	bind_existing_shuttles()
	bind_existing_consoles()
	init_hull_renderer()
	return SS_INIT_SUCCESS

/// Walks helms / navs that registered before SSovermap init (i.e. roundstart
/// shuttle areas) and binds them to their target ship.
/datum/controller/subsystem/overmap/proc/bind_existing_consoles()
	for(var/obj/machinery/computer/helm/helm in helms)
		helm.set_ship()
	for(var/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/nav in navs)
		nav.link_shuttle()

/datum/controller/subsystem/overmap/fire(resumed = FALSE)
	for(var/obj/structure/overmap/event/E as anything in events)
		if(QDELETED(E))
			LAZYREMOVE(events, E)
			continue
		E.apply_effect()
		if(MC_TICK_CHECK)
			return

/// Allocate a fresh Z-level dedicated to the overmap grid. We don't go
/// through `request_turf_block_reservation` because we want a stable,
/// admin-debuggable Z that lives for the round.
/datum/controller/subsystem/overmap/proc/allocate_overmap_zlevel()
	var/datum/space_level/level = SSmapping.add_new_zlevel("Overmap", list(ZTRAIT_OVERMAP = TRUE))
	overmap_z = level.z_value

/// Programmatically fill the overmap Z with a square of `/turf/open/overmap`,
/// surrounded by a one-tile ring of dense `/turf/open/overmap/edge`. The grid
/// is anchored at (1,1) and runs to (size,size).
/datum/controller/subsystem/overmap/proc/build_grid()
	var/area/overmap/area = GLOB.areas_by_type[/area/overmap] || new /area/overmap
	for(var/x in 1 to size)
		for(var/y in 1 to size)
			var/turf/old_turf = locate(x, y, overmap_z)
			if(!old_turf)
				continue
			var/turf/new_turf
			if(x == 1 || y == 1 || x == size || y == size)
				new_turf = old_turf.ChangeTurf(/turf/open/overmap/edge, /turf/open/overmap/edge)
			else
				new_turf = old_turf.ChangeTurf(/turf/open/overmap, /turf/open/overmap)
			if(!new_turf)
				continue
			var/area/old_area = get_area(new_turf)
			if(old_area != area)
				// change_area() handles uncontaining from the old area's turf
				// listing; direct contents += left the turf double-registered.
				new_turf.change_area(old_area, area)

/// Drop the decorative star at the center of the grid.
/datum/controller/subsystem/overmap/proc/place_star()
	var/turf/center = locate(round(size / 2), round(size / 2), overmap_z)
	if(center)
		new /obj/structure/overmap/celestial/star(center)

/// Returns a random unoccupied (non-edge) overmap turf, or null if no slot
/// could be found within `tries`. Tiles within `OVERMAP_STAR_BUFFER` of the
/// grid center are excluded so POIs never visually overlap the star sprite.
/datum/controller/subsystem/overmap/proc/get_unused_overmap_square(thing_to_not_have = /obj/structure/overmap, tries = MAX_OVERMAP_PLACEMENT_ATTEMPTS)
	var/turf/picked
	var/star_x = round(size / 2)
	var/star_y = round(size / 2)
	for(var/i in 1 to tries)
		picked = locate(rand(2, size - 1), rand(2, size - 1), overmap_z)
		if(!picked)
			continue
		if(locate(thing_to_not_have) in picked)
			continue
		if(max(abs(picked.x - star_x), abs(picked.y - star_y)) < OVERMAP_STAR_BUFFER)
			continue
		return picked
	return null

/// Categorize all non-edge overmap turfs into concentric rings by euclidean
/// distance from the star center. Populates `radius_tiles` for orbital placement.
/datum/controller/subsystem/overmap/proc/calculate_orbital_rings()
	var/star_x = round(size / 2)
	var/star_y = round(size / 2)
	var/list/unsorted_turfs = list()
	for(var/x in 2 to size - 1)
		for(var/y in 2 to size - 1)
			var/turf/T = locate(x, y, overmap_z)
			if(T)
				unsorted_turfs += T
	for(var/i in 3 to round((size - 2) / 2))
		radius_tiles["[i]"] = list()
		for(var/turf/T as anything in unsorted_turfs)
			var/dist = round(sqrt((T.x - star_x) ** 2 + (T.y - star_y) ** 2))
			if(dist == i)
				radius_tiles["[i]"] += T
		unsorted_turfs -= radius_tiles["[i]"]
	radius_tiles["unsorted"] = unsorted_turfs.Copy()

/// Returns a random unoccupied turf within the specified orbital ring.
/// Falls back to `get_unused_overmap_square()` if generator is RANDOM or
/// the requested ring is empty/missing.
/datum/controller/subsystem/overmap/proc/get_unused_overmap_square_in_radius(radius, thing_to_not_have = /obj/structure/overmap, tries = MAX_OVERMAP_PLACEMENT_ATTEMPTS)
	if(generator_type != OVERMAP_GENERATOR_SOLAR)
		return get_unused_overmap_square(thing_to_not_have, tries)
	if(!radius)
		var/list/keys = list()
		for(var/key in radius_tiles)
			if(key == "unsorted")
				continue
			keys += key
		if(!length(keys))
			return get_unused_overmap_square(thing_to_not_have, tries)
		radius = pick(keys)
	var/list/ring = radius_tiles["[radius]"]
	if(!length(ring))
		return get_unused_overmap_square(thing_to_not_have, tries)
	for(var/i in 1 to tries)
		var/turf/picked = pick(ring)
		if(locate(thing_to_not_have) in picked)
			continue
		return picked
	return null

/// Finds the closest unoccupied turf within a given orbit to `adjacent`.
/// Used for chaining events along an orbital ring.
/datum/controller/subsystem/overmap/proc/get_nearest_unused_square_in_radius(turf/adjacent, radius, max_range = 3, thing_to_not_have = /obj/structure/overmap)
	var/list/ring = radius_tiles["[radius]"]
	if(!length(ring))
		return null
	var/turf/best
	var/best_dist = INFINITY
	for(var/turf/T as anything in ring)
		if(locate(thing_to_not_have) in T)
			continue
		var/dist = round(sqrt((T.x - adjacent.x) ** 2 + (T.y - adjacent.y) ** 2))
		if(dist <= max_range && dist < best_dist)
			best = T
			best_dist = dist
	return best

/// Returns the overmap object whose `linked_levels` contains `zlevel`,
/// or null. Used by ship binding (M3) and dock resolution (M6).
/// Checks named sites/levels first, then lazy `/dynamic` encounters.
/datum/controller/subsystem/overmap/proc/get_overmap_object_by_z(zlevel)
	for(var/obj/structure/overmap/level/object in overmap_objects)
		if(zlevel in object.linked_levels)
			return object
	for(var/obj/structure/overmap/dynamic/encounter in overmap_objects)
		if(zlevel in encounter.linked_levels)
			return encounter
	return null

/// Lookup helper used by helm consoles binding via `override_id`.
/datum/controller/subsystem/overmap/proc/get_overmap_object_by_id(id)
	if(!id)
		return null
	for(var/obj/structure/overmap/object in overmap_objects)
		if(object.id == id)
			return object
	return null

/// Roundstart placement of POIs and encounters on the grid. Branches on
/// `generator_type` to select placement strategy.
/datum/controller/subsystem/overmap/proc/create_map()
	place_station()
	place_mining()
	if(SSmapping.current_map.overmap_space_ruins)
		seed_space_sites()
	spawn_encounters()
	spawn_events()

/// Locate the station Z-level set and drop a `/level/main` near the star.
/// Prefers a tile in the chebyshev-`OVERMAP_STAR_BUFFER` ring around the
/// star (just outside the star sprite's footprint), falling back to any
/// random non-edge tile if every ring slot is taken.
/datum/controller/subsystem/overmap/proc/place_station()
	var/list/station_zs = SSmapping.levels_by_trait(ZTRAIT_STATION)
	if(!length(station_zs))
		WARNING("No ZTRAIT_STATION levels found - skipping station overmap POI.")
		return
	var/star_x = round(size / 2)
	var/star_y = round(size / 2)
	var/list/candidates = list()
	for(var/dx in -OVERMAP_STAR_BUFFER to OVERMAP_STAR_BUFFER)
		for(var/dy in -OVERMAP_STAR_BUFFER to OVERMAP_STAR_BUFFER)
			if(max(abs(dx), abs(dy)) != OVERMAP_STAR_BUFFER)
				continue
			var/turf/maybe = locate(star_x + dx, star_y + dy, overmap_z)
			if(!istype(maybe, /turf/open/overmap) || istype(maybe, /turf/open/overmap/edge))
				continue
			if(locate(/obj/structure/overmap) in maybe)
				continue
			candidates += maybe
	var/turf/picked
	if(length(candidates))
		picked = pick(candidates)
	if(!picked)
		picked = get_unused_overmap_square()
	if(!picked)
		WARNING("create_map(): could not find an unused tile for the station POI.")
		return
	new /obj/structure/overmap/level/main(picked, null, station_zs.Copy())

/// Locate the mining Z-level set, choose the appropriate flavor by
/// `SSmapping.current_map.minetype`, and drop a single `/level/mining`
/// instance whose `linked_levels` covers all mining Zs (Snowglobe / Icebox
/// stack 3 layers under one body, MetaStation has just one).
/datum/controller/subsystem/overmap/proc/place_mining()
	var/minetype = SSmapping.current_map?.minetype
	if(!minetype || minetype == MINETYPE_NONE)
		return
	var/list/mining_zs = SSmapping.levels_by_trait(ZTRAIT_MINING)
	if(!length(mining_zs))
		return
	var/mining_path
	switch(minetype)
		if(MINETYPE_LAVALAND)
			mining_path = /obj/structure/overmap/level/mining/lavaland
		if(MINETYPE_ICE)
			mining_path = /obj/structure/overmap/level/mining/ice
		else
			mining_path = /obj/structure/overmap/level/mining/lavaland
	var/turf/picked = get_unused_overmap_square()
	if(!picked)
		WARNING("create_map(): could not find an unused tile for the mining POI.")
		return
	new mining_path(picked, null, mining_zs.Copy())

/// Walk every mobile docking port that already exists at SSovermap init time
/// and bind a `/ship/simulated` to each one. Arrivals shuttle is skipped -
/// it's a one-shot transit visualizer, not a player-pilotable craft.
/// Ports created post-init route through the BLASTWAVE EDIT in mobile_port.dm's
/// `Initialize` instead.
/datum/controller/subsystem/overmap/proc/bind_existing_shuttles()
	for(var/obj/docking_port/mobile/port in SSshuttle.mobile_docking_ports)
		setup_shuttle_ship(port)

/// Whether this mobile port should get an overmap ship icon. Transit shuttles
/// (escape, supply, ferry, pods, arrivals, …) must not pollute the map/radar.
/datum/controller/subsystem/overmap/proc/should_bind_shuttle(obj/docking_port/mobile/port)
	if(!port)
		return FALSE
	if(istype(port, /obj/docking_port/mobile/overmap))
		return TRUE
	if(istype(port, /obj/docking_port/mobile/custom))
		return TRUE
	// Oddly typed ports that still use overmap fighter/frigate areas.
	return ship_type_for_port(port) != /obj/structure/overmap/ship/simulated

/// Pick the simulated ship subtype from the port's area_type / shuttle_areas.
/// Frigate and fighter areas map to their control-flag presets; everything
/// else (mining shuttles, etc.) stays on the base /simulated type.
/datum/controller/subsystem/overmap/proc/ship_type_for_port(obj/docking_port/mobile/port)
	if(ispath(port.area_type, /area/shuttle/overmap/fighter))
		return /obj/structure/overmap/ship/simulated/fighter
	if(ispath(port.area_type, /area/shuttle/overmap/frigate))
		return /obj/structure/overmap/ship/simulated/frigate
	for(var/area/shuttle_area as anything in port.shuttle_areas)
		if(istype(shuttle_area, /area/shuttle/overmap/fighter))
			return /obj/structure/overmap/ship/simulated/fighter
		if(istype(shuttle_area, /area/shuttle/overmap/frigate))
			return /obj/structure/overmap/ship/simulated/frigate
	return /obj/structure/overmap/ship/simulated

/// Create an overmap ship icon for a single mobile docking port. Resolves
/// the port's Z to a known POI; if the port lives on a reserved/CentCom
/// Z (e.g. emergency shuttle in transit) the icon is parked off-grid and
/// will resync via `check_loc()` once the port lands somewhere mapped.
/datum/controller/subsystem/overmap/proc/setup_shuttle_ship(obj/docking_port/mobile/port)
	if(!port || port.current_ship)
		return
	if(!should_bind_shuttle(port))
		return
	var/obj/structure/overmap/level/parent_level = get_overmap_object_by_z(port.z)
	var/ship_path = ship_type_for_port(port)
	var/obj/structure/overmap/ship/simulated/ship
	if(parent_level)
		ship = new ship_path(parent_level, port.shuttle_id, port)
		ship.docked = parent_level
		ship.state = OVERMAP_SHIP_IDLE
		ship.home_level_id = parent_level.id
	else if(SSmapping.level_trait(port.z, ZTRAIT_RESERVED))
		// In transit (e.g. Shuttle Manipulator load, or a shuttle that hasn't
		// landed yet). Park the icon on the station's overmap tile and treat
		// the ship as if it had just undocked: state = FLYING, mass / engines
		// / fuel pre-computed so the helm UI is fly-ready without requiring
		// a manual undock. Falls back to a random empty tile if main is unset.
		var/turf/parked = main ? get_turf(main) : get_unused_overmap_square()
		if(parked)
			ship = new ship_path(parked, port.shuttle_id, port)
			ship.state = OVERMAP_SHIP_FLYING
			if(main)
				ship.home_level_id = MAIN_OVERMAP_OBJECT_ID
			ship.prepare_for_flight()
	else if(is_centcom_level(port.z))
		// CentCom is intentionally off-grid. Icon lives in nullspace until
		// the shuttle returns to a known POI.
		ship = new ship_path(null, port.shuttle_id, port)
	else
		// Ruin, away, and other off-grid shuttles are expected here.
		return
	port.current_ship = ship

/// Spawn dynamic encounter objects on the overmap grid. In SOLAR mode,
/// encounters are placed in outer orbits (rings 6-8). In RANDOM mode,
/// they're placed on random tiles.
/datum/controller/subsystem/overmap/proc/spawn_encounters()
	var/max_encounters = CONFIG_GET(number/max_overmap_dynamic_events)
	for(var/i in 1 to max_encounters)
		var/turf/T
		if(generator_type == OVERMAP_GENERATOR_SOLAR)
			var/orbit = "[rand(6, 8)]"
			T = get_unused_overmap_square_in_radius(orbit)
		else
			T = get_unused_overmap_square()
		if(!T)
			continue
		new /obj/structure/overmap/dynamic(T)

/// Spawn overmap event hazard clusters. In SOLAR mode, events are chained
/// along orbital rings. In RANDOM mode, clusters spread via cardinal adjacency.
/datum/controller/subsystem/overmap/proc/spawn_events()
	var/max_clusters = CONFIG_GET(number/max_overmap_event_clusters)
	var/max_events = CONFIG_GET(number/max_overmap_events)
	if(generator_type == OVERMAP_GENERATOR_SOLAR)
		spawn_events_in_orbits(max_clusters, max_events)
	else
		spawn_events_random(max_clusters, max_events)

/// Random-mode event cluster spawning. Picks a random event type and seed
/// tile, then spreads outward via `spawn_event_cluster`.
/datum/controller/subsystem/overmap/proc/spawn_events_random(max_clusters, max_events)
	for(var/i in 1 to max_clusters)
		if(LAZYLEN(events) >= max_events)
			return
		var/event_type = pick(subtypesof(/obj/structure/overmap/event))
		var/turf/seed = get_unused_overmap_square(/obj/structure/overmap/event)
		if(!seed)
			continue
		spawn_event_cluster(event_type, seed, max_events)

/// Solar-mode event spawning. Chains events along orbital rings.
/datum/controller/subsystem/overmap/proc/spawn_events_in_orbits(max_clusters, max_events)
	var/list/orbits = list()
	for(var/key in radius_tiles)
		if(key == "unsorted")
			continue
		orbits += key
	if(!length(orbits))
		return
	for(var/i in 1 to max_clusters)
		if(LAZYLEN(events) >= max_events)
			return
		var/event_type = pick(subtypesof(/obj/structure/overmap/event))
		var/selected_orbit = pick(orbits)
		var/turf/T = get_unused_overmap_square_in_radius(selected_orbit, /obj/structure/overmap/event)
		if(!T)
			continue
		var/obj/structure/overmap/event/E = new event_type(T)
		var/chain_rate = E.chain_rate
		for(var/j in 1 to chain_rate)
			if(LAZYLEN(events) >= max_events)
				return
			var/turf/next = get_nearest_unused_square_in_radius(T, selected_orbit, 3, /obj/structure/overmap/event)
			if(!next)
				break
			new event_type(next)
			T = next

/// Spreads an event cluster outward from a seed tile via cardinal adjacency
/// with decaying probability. Depth-limited to prevent stack overflow.
/datum/controller/subsystem/overmap/proc/spawn_event_cluster(event_type, turf/location, max_events, chance, depth = 0)
	if(LAZYLEN(events) >= max_events)
		return
	if(depth > 8)
		return
	var/obj/structure/overmap/event/E = new event_type(location)
	if(!chance)
		chance = E.spread_chance
	for(var/dir in GLOB.cardinals)
		if(!prob(chance))
			continue
		var/turf/T = get_step(location, dir)
		if(!istype(T, /turf/open/overmap) || istype(T, /turf/open/overmap/edge))
			continue
		if(locate(/obj/structure/overmap/event) in T)
			continue
		spawn_event_cluster(event_type, T, max_events, chance / 2, depth + 1)

/// Dock band width for a named site or dynamic encounter reservation.
/datum/controller/subsystem/overmap/proc/calculate_overmap_dock_size(datum/map_template/ruin/template, obj/docking_port/mobile/visiting_shuttle, default_block_size = 0)
	if(visiting_shuttle)
		return max(visiting_shuttle.width, visiting_shuttle.height) + 3
	if(template)
		return round(max(template.width, template.height) / 2) + 3
	return round(default_block_size / 2)

/// Square reservation side length that fits `template` at the standard west-dock anchor.
/datum/controller/subsystem/overmap/proc/calculate_overmap_site_size(datum/map_template/ruin/template, dock_size, fallback_ruin_pad = 0)
	if(template)
		return dock_size + max(template.width, template.height) + 4
	return dock_size + fallback_ruin_pad

/// Ruin load anchor inside a west-dock reservation, vertically centered with optional right-align.
/datum/controller/subsystem/overmap/proc/calculate_overmap_ruin_anchor(turf/bottom_left, datum/map_template/ruin/template, dock_size, size)
	var/ruin_x = bottom_left.x + dock_size + 2
	var/ruin_y = bottom_left.y + round((size - template.height) / 2)
	var/ruin_width_room = size - dock_size - 2
	if(template.width > ruin_width_room)
		ruin_x = bottom_left.x + size - template.width
	return locate(ruin_x, ruin_y, bottom_left.z)

/// Returns FALSE if any turf in `affected_turfs` lies outside `reserve`.
/datum/controller/subsystem/overmap/proc/validate_ruin_turfs_fit_reservation(datum/turf_reservation/reserve, list/affected_turfs)
	for(var/turf/T as anything in affected_turfs)
		if(!reserve.calculate_turf_bounds_information(T))
			return FALSE
	return TRUE

/// Minimum square side for a west-anchored encounter reservation. Visiting
/// shuttles can be wider than ruin templates, so the dock band alone may need
/// `2 * dock_size` of horizontal runway.
/datum/controller/subsystem/overmap/proc/minimum_encounter_reservation_side(dock_size, datum/map_template/ruin/ruin_type, default_block_size = 0)
	var/ruin_pad = ruin_type ? max(ruin_type.width, ruin_type.height) + 4 : CEILING(default_block_size / 2, 1)
	return max(dock_size + ruin_pad, (dock_size * 2) + 4)

/// Returns FALSE if any turf in the docking port footprint lies outside `reserve`.
/datum/controller/subsystem/overmap/proc/dock_port_fits_reservation(datum/turf_reservation/reserve, obj/docking_port/stationary/dock)
	if(!reserve || !dock)
		return FALSE
	for(var/turf/T in dock.return_turfs())
		if(!reserve.calculate_turf_bounds_information(T))
			return FALSE
	return TRUE

/// Whether a stationary dock's footprint is safe to land on — open space / plating
/// / lava / openspace / misc only, matching the nav console whitelist. Rejects
/// ruin floors, walls, indestructible turfs, and dense anchored obstacles.
/datum/controller/subsystem/overmap/proc/dock_footprint_is_clear(obj/docking_port/stationary/port)
	if(!port)
		return FALSE
	var/static/list/allowed_turfs = typecacheof(list(
		/turf/open/space,
		/turf/open/floor/plating,
		/turf/open/lava,
		/turf/open/openspace,
		/turf/open/misc,
	))
	for(var/turf/T in port.return_turfs())
		if(!is_type_in_typecache(T.type, allowed_turfs))
			return FALSE
		for(var/obj/obstacle in T)
			if(!obstacle.density || !obstacle.anchored)
				continue
			if(istype(obstacle, /obj/machinery/door))
				continue
			if(istype(obstacle, /obj/docking_port))
				continue
			return FALSE
	return TRUE

/// Try to place a stationary encounter dock at `dir`, centered in a rectangle
/// inside `reserve` (same placement math as helm landing-zone ports).
/datum/controller/subsystem/overmap/proc/try_place_encounter_dock(
	datum/turf_reservation/reserve,
	turf/zone_origin,
	zone_width,
	zone_height,
	obj/docking_port/mobile/shuttle,
	shuttle_id,
	dir,
)
	if(!reserve || !zone_origin || !shuttle || !shuttle_id || !dir)
		return null
	var/list/bounds = shuttle.return_coords()
	var/bbox_x1 = min(bounds[1], bounds[3])
	var/bbox_y1 = min(bounds[2], bounds[4])
	var/ship_w = max(bounds[1], bounds[3]) - bbox_x1 + 1
	var/ship_h = max(bounds[2], bounds[4]) - bbox_y1 + 1
	if(ship_w > zone_width || ship_h > zone_height)
		return null
	var/port_off_x = shuttle.x - bbox_x1
	var/port_off_y = shuttle.y - bbox_y1
	var/dest_x = zone_origin.x + round((zone_width - ship_w) / 2) + port_off_x
	var/dest_y = zone_origin.y + round((zone_height - ship_h) / 2) + port_off_y
	var/turf/dest = locate(dest_x, dest_y, zone_origin.z)
	if(!dest)
		return null
	var/obj/docking_port/stationary/port = new(dest)
	port.dir = dir
	port.name = "\improper Uncharted Space"
	port.shuttle_id = shuttle_id
	port.width = shuttle.width
	port.height = shuttle.height
	port.dwidth = shuttle.dwidth
	port.dheight = shuttle.dheight
	if(!dock_port_fits_reservation(reserve, port) || !shuttle.check_dock(port, TRUE) || !dock_footprint_is_clear(port))
		qdel(port)
		return null
	return port

/// Prefer `shuttle.dir` for encounter docks; rotate only when that heading
/// cannot fit inside the surveyed west dock band (ruins occupy the east half).
/datum/controller/subsystem/overmap/proc/place_encounter_primary_dock(
	datum/turf_reservation/reserve,
	turf/bottom_left,
	total_size,
	dock_size,
	obj/docking_port/mobile/visiting_shuttle,
	dock_id,
	list/dir_attempts,
)
	var/turf/zone_origin = locate(bottom_left.x + 1, bottom_left.y + 1, bottom_left.z)
	var/zone_width = dock_size
	var/zone_height = total_size - 2
	var/shuttle_id = "[OVERMAP_DOCK_PREFIX]_[dock_id]"
	for(var/attempt_dir in dir_attempts)
		var/obj/docking_port/stationary/placed = try_place_encounter_dock(
			reserve,
			zone_origin,
			zone_width,
			zone_height,
			visiting_shuttle,
			shuttle_id,
			attempt_dir,
		)
		if(placed)
			return placed
	return null

/// Tear down a partially-built encounter and stash a helm-facing error.
/datum/controller/subsystem/overmap/proc/abort_dynamic_encounter(datum/turf_reservation/reserve, list/cleanup_atoms, message)
	for(var/atom/cleanup as anything in cleanup_atoms)
		if(!QDELETED(cleanup))
			qdel(cleanup)
	QDEL_NULL(reserve)
	last_encounter_spawn_error = message
	return null

/// Load a ruin template, warn on reservation overflow, and claim the footprint.
/datum/controller/subsystem/overmap/proc/load_overmap_ruin_into_reservation(datum/turf_reservation/reserve, datum/map_template/ruin/template, turf/ruin_turf)
	if(!ruin_turf || !template || !reserve)
		return
	template.load(ruin_turf)
	var/list/affected = template.get_affected_turfs(ruin_turf, FALSE)
	if(!validate_ruin_turfs_fit_reservation(reserve, affected))
		WARNING("Overmap ruin [template.name] footprint exceeds reservation at [ruin_turf.x],[ruin_turf.y],[ruin_turf.z]")
	SSmapping.claim_turfs_for_reservation(reserve, affected)

/// Pick a space-ruin batch for a lazy `/dynamic` encounter (site-style packing).
/datum/controller/subsystem/overmap/proc/pick_dynamic_encounter_templates()
	var/list/space_ruins = SSmapping.themed_ruins[ZTRAIT_SPACE_RUINS]
	if(!length(space_ruins))
		return list()

	var/cluster_capacity = CONFIG_GET(number/overmap_cluster_capacity)
	var/list/datum/map_template/ruin/available = list()
	for(var/ruin_name in space_ruins)
		var/datum/map_template/ruin/candidate = space_ruins[ruin_name]
		if(ispath(candidate))
			candidate = new candidate
		if(candidate.unpickable || candidate.always_place)
			continue
		if(candidate.id in placed_site_template_ids)
			continue
		available[candidate] = candidate.placement_weight || 1

	if(!length(available))
		return list()

	var/list/datum/map_template/ruin/batch = list()
	var/list/datum/map_template/ruin/small_pool = list()
	var/list/datum/map_template/ruin/large_pool = list()
	for(var/datum/map_template/ruin/candidate as anything in available)
		if(is_overmap_cluster_ruin(candidate))
			small_pool += candidate
		else
			large_pool += candidate

	if(length(small_pool))
		var/list/small_weights = list()
		for(var/datum/map_template/ruin/small as anything in small_pool)
			small_weights[small] = available[small] || 1
		while(length(batch) < cluster_capacity && length(small_weights))
			var/datum/map_template/ruin/picked = pick_weight(small_weights)
			batch += picked
			small_weights -= picked
	else if(length(large_pool))
		batch += pick(large_pool)

	return batch

/// Generate a full content Z for `encounter` using the shared site generator.
/// Returns TRUE on success; sets last_encounter_spawn_error on failure.
/datum/controller/subsystem/overmap/proc/load_dynamic_encounter(obj/structure/overmap/dynamic/encounter)
	if(!encounter)
		return FALSE
	if(!COOLDOWN_FINISHED(src, encounter_cooldown))
		last_encounter_spawn_error = "WARNING! Stellar interference is restricting local translation fields. Hold position and re-attempt docking in [round(COOLDOWN_TIMELEFT(src, encounter_cooldown) / 10)] seconds."
		return FALSE

	last_encounter_spawn_error = null
	var/list/datum/map_template/ruin/templates = pick_dynamic_encounter_templates()
	if(!length(templates))
		last_encounter_spawn_error = "SURVEY TELEMETRY LOST. No chartable space ruins remain in local catalogs — withdraw and re-approach."
		return FALSE

	var/label = length(templates) > 1 ? "Debris Field" : (templates[1].name || encounter.name)
	var/list/result = generate_overmap_content_z(templates, "Overmap Encounter ([label])")
	if(!result)
		last_encounter_spawn_error = "NAVIGATION BUFFER SATURATED. Local translation fields cannot chart a stable survey footprint — withdraw and re-approach."
		return FALSE

	encounter.linked_levels = list(result["z"])
	encounter.member_templates = result["loaded"]
	encounter.member_template_ids = result["loaded_ids"]
	encounter.ruin_template = length(result["loaded"]) == 1 ? result["loaded"][1] : null
	encounter.name = label
	COOLDOWN_START(src, encounter_cooldown, OVERMAP_ENCOUNTER_COOLDOWN)
	return TRUE

/// Soft-clear a content Z and return it to the reusable pool (never shared while linked).
/datum/controller/subsystem/overmap/proc/recycle_overmap_content_z(z_value)
	if(!z_value)
		return
	// Eject from SSair before empty() so Destroy/KILL_EXCITED cannot re-queue LINDA work.
	SSair.begin_z_eject(z_value)
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in landing_zones?.Copy())
		if(zone.z == z_value)
			qdel(zone)
	for(var/obj/docking_port/stationary/port as anything in SSshuttle.stationary_docking_ports.Copy())
		if(port.z == z_value)
			qdel(port)
	for(var/turf/turf as anything in Z_TURFS(z_value))
		turf.empty(turf_type = /turf/open/space)
		CHECK_TICK
	SSair.end_z_eject(z_value)
	if(!(z_value in reusable_content_zs))
		reusable_content_zs += z_value

// --- Space site seeding (Phase 3) ---

/// Seed named space ruin POIs onto the overmap grid. Priority pass for
/// always_place ruins, then budget fill from the weighted space ruin pool.
/// Small ruins pack onto shared cluster Zs; large ruins get a solo Z each.
/// Only called when `overmap_space_ruins` is TRUE on the map config.
/datum/controller/subsystem/overmap/proc/seed_space_sites()
	var/list/space_ruins = SSmapping.themed_ruins[ZTRAIT_SPACE_RUINS]
	if(!length(space_ruins))
		return

	var/list/datum/map_template/ruin/placed = list()
	var/max_sites = CONFIG_GET(number/max_overmap_named_sites)
	var/cluster_capacity = CONFIG_GET(number/overmap_cluster_capacity)

	// Priority pass: always_place ruins get guaranteed slots.
	for(var/ruin_name in space_ruins)
		var/datum/map_template/ruin/candidate = space_ruins[ruin_name]
		if(ispath(candidate))
			candidate = new candidate
		if(!candidate.always_place)
			continue
		placed += candidate
		placed_site_template_ids += candidate.id

	// Budget fill: pick from remaining weighted pool up to max_sites.
	var/budget = CONFIG_GET(number/space_budget)
	var/list/available = list()
	for(var/ruin_name in space_ruins)
		var/datum/map_template/ruin/candidate = space_ruins[ruin_name]
		if(ispath(candidate))
			candidate = new candidate
		if(candidate.always_place || candidate.unpickable)
			continue
		if(candidate.id in placed_site_template_ids)
			continue
		available[candidate] = candidate.placement_weight

	while(budget > 0 && length(available) && length(placed) < max_sites)
		var/datum/map_template/ruin/picked = pick_weight(available)
		if(!picked)
			break
		if(picked.cost > budget)
			available -= picked
			continue
		placed += picked
		placed_site_template_ids += picked.id
		budget -= picked.cost
		if(!picked.allow_duplicates)
			available -= picked

	var/list/datum/map_template/ruin/small_pool = list()
	var/list/datum/map_template/ruin/large_pool = list()
	for(var/datum/map_template/ruin/template as anything in placed)
		if(is_overmap_cluster_ruin(template))
			small_pool += template
		else
			large_pool += template

	for(var/datum/map_template/ruin/solo as anything in large_pool)
		spawn_overmap_site(list(solo), controlled = solo.always_place)

	var/list/datum/map_template/ruin/batch = list()
	for(var/datum/map_template/ruin/small as anything in small_pool)
		batch += small
		if(length(batch) < cluster_capacity)
			continue
		spawn_overmap_site(batch.Copy(), controlled = FALSE)
		batch.Cut()
	if(length(batch))
		spawn_overmap_site(batch, controlled = FALSE)

/// TRUE when `template` packs onto a shared cluster Z (side ≤ threshold).
/datum/controller/subsystem/overmap/proc/is_overmap_cluster_ruin(datum/map_template/ruin/template)
	if(!template)
		return FALSE
	return max(template.width, template.height) <= OVERMAP_CLUSTER_RUIN_MAX_SIDE

/// Shared content-Z generator used by roundstart sites and lazy dynamics.
/// Allocates (or reuses) a full SELFLOOPING Z, places `templates` with separation,
/// seeds landing zones, and returns an assoc list:
/// `z`, `loaded`, `loaded_ids`, `chained`, `placed_rects` — or null on failure.
/datum/controller/subsystem/overmap/proc/generate_overmap_content_z(list/datum/map_template/ruin/templates, level_name = "Overmap Content", allow_reuse = TRUE)
	if(!length(templates))
		return null

	var/site_z
	if(allow_reuse && length(reusable_content_zs))
		site_z = reusable_content_zs[1]
		reusable_content_zs.Cut(1, 2)
	else
		var/datum/space_level/level = SSmapping.add_new_zlevel(
			level_name,
			ZTRAITS_OVERMAP_SITE,
			contain_turfs = TRUE,
		)
		if(!level)
			WARNING("generate_overmap_content_z: failed to allocate Z for [level_name]")
			return null
		site_z = level.z_value

	var/list/placed_rects = list()
	var/list/datum/map_template/ruin/loaded = list()
	var/list/loaded_ids = list()
	var/list/datum/map_template/ruin/chained = list()

	for(var/datum/map_template/ruin/template as anything in templates)
		var/turf/anchor = find_site_ruin_anchor(site_z, template, placed_rects)
		if(!anchor)
			WARNING("generate_overmap_content_z: could not place [template.name] on Z[site_z]")
			continue
		template.load(anchor, centered = FALSE)
		placed_rects += list(ruin_rect_from_anchor(anchor, template))
		loaded += template
		loaded_ids += template.id

		if(!template.always_spawn_with)
			continue
		for(var/chain_type in template.always_spawn_with)
			if(template.always_spawn_with[chain_type] != PLACE_SAME_Z)
				continue
			for(var/ruin_name in SSmapping.ruins_templates)
				var/datum/map_template/ruin/linked = SSmapping.ruins_templates[ruin_name]
				if(!istype(linked, chain_type))
					continue
				var/turf/chain_anchor = find_site_ruin_anchor(site_z, linked, placed_rects, near_rect = placed_rects[length(placed_rects)])
				if(!chain_anchor)
					WARNING("generate_overmap_content_z: could not place chained [linked.name] near [template.name]")
					continue
				linked.load(chain_anchor, centered = FALSE)
				placed_rects += list(ruin_rect_from_anchor(chain_anchor, linked))
				chained += linked
				loaded_ids += linked.id

	if(!length(loaded))
		WARNING("generate_overmap_content_z: no ruins loaded for [level_name] on Z[site_z]")
		recycle_overmap_content_z(site_z)
		return null

	var/display_name = length(templates) > 1 ? "Debris Field" : (templates[1].name || "Unknown Signal")
	seed_site_landing_zones(site_z, display_name, placed_rects)

	return list(
		"z" = site_z,
		"loaded" = loaded,
		"loaded_ids" = loaded_ids,
		"chained" = chained,
		"placed_rects" = placed_rects,
	)

/// Spawn a named site POI on a dedicated full Z-level via the shared generator,
/// then place one `/level/site` tile on the overmap.
/datum/controller/subsystem/overmap/proc/spawn_overmap_site(list/datum/map_template/ruin/templates, controlled = FALSE)
	if(!length(templates))
		return null

	var/turf/grid_turf = get_unused_overmap_square()
	if(!grid_turf)
		WARNING("spawn_overmap_site: no free overmap tile")
		return null

	var/datum/map_template/ruin/primary = templates[1]
	var/site_id = primary.id || "site_[length(overmap_objects)]"
	var/site_name = primary.name || "Unknown Signal"
	if(length(templates) > 1)
		site_id = "cluster_[length(overmap_objects)]"
		site_name = "Debris Field"

	var/list/result = generate_overmap_content_z(templates, "Overmap Site ([site_name])", allow_reuse = FALSE)
	if(!result)
		WARNING("spawn_overmap_site: generation failed for [site_name]")
		return null

	var/site_z = result["z"]
	var/list/loaded = result["loaded"]
	var/list/loaded_ids = result["loaded_ids"]
	var/list/chained = result["chained"]

	var/obj/structure/overmap/level/site/site = new(grid_turf, site_id, list(site_z), length(loaded) == 1 ? loaded[1] : null)
	site.name = site_name
	site.member_templates = loaded
	site.member_template_ids = loaded_ids
	site.chained_templates = chained
	site.preloaded = TRUE
	site.controlled = controlled
	if(primary.id == DES_TWO_OVERMAP_OBJECT_ID || ("des_two" in loaded_ids))
		site.installation_stealth = TRUE
		site.id = DES_TWO_OVERMAP_OBJECT_ID
	return site

/// Axis-aligned ruin footprint as list(x1, y1, x2, y2).
/datum/controller/subsystem/overmap/proc/ruin_rect_from_anchor(turf/anchor, datum/map_template/ruin/template)
	return list(anchor.x, anchor.y, anchor.x + template.width - 1, anchor.y + template.height - 1)

/// Chebyshev gap between two rects (negative = overlap).
/datum/controller/subsystem/overmap/proc/rect_chebyshev_gap(list/a, list/b)
	var/dx = max(a[1] - b[3], b[1] - a[3], 0)
	var/dy = max(a[2] - b[4], b[2] - a[4], 0)
	return max(dx, dy)

/// Rejection-sample a bottom-left turf for `template` on `site_z`.
/// When `near_rect` is set, prefer anchors near that footprint (chain loads).
/datum/controller/subsystem/overmap/proc/find_site_ruin_anchor(site_z, datum/map_template/ruin/template, list/placed_rects, list/near_rect)
	var/margin = OVERMAP_SITE_EDGE_MARGIN + TRANSITIONEDGE
	var/min_x = margin + 1
	var/min_y = margin + 1
	var/max_x = world.maxx - margin - template.width + 1
	var/max_y = world.maxy - margin - template.height + 1
	if(max_x < min_x || max_y < min_y)
		return null

	for(var/attempt in 1 to OVERMAP_SITE_PLACE_ATTEMPTS)
		var/try_x
		var/try_y
		if(near_rect)
			try_x = clamp(round((near_rect[1] + near_rect[3]) / 2) + rand(-40, 40) - round(template.width / 2), min_x, max_x)
			try_y = clamp(round((near_rect[2] + near_rect[4]) / 2) + rand(-40, 40) - round(template.height / 2), min_y, max_y)
		else
			try_x = rand(min_x, max_x)
			try_y = rand(min_y, max_y)
		var/list/candidate = list(try_x, try_y, try_x + template.width - 1, try_y + template.height - 1)
		var/ok = TRUE
		for(var/list/other as anything in placed_rects)
			if(rect_chebyshev_gap(candidate, other) < OVERMAP_CLUSTER_MIN_SEPARATION)
				ok = FALSE
				break
		if(!ok)
			continue
		var/turf/anchor = locate(try_x, try_y, site_z)
		if(anchor)
			return anchor
	return null

/// TRUE when `candidate` clears ruin / LZ spacing rules for site seeding.
/datum/controller/subsystem/overmap/proc/site_lz_candidate_ok(list/candidate, list/placed_rects, list/lz_rects)
	for(var/list/other as anything in placed_rects)
		if(rect_chebyshev_gap(candidate, other) < OVERMAP_SITE_LZ_RUIN_SEPARATION)
			return FALSE
	for(var/list/other_lz as anything in lz_rects)
		if(rect_chebyshev_gap(candidate, other_lz) < OVERMAP_SITE_LZ_SIDE)
			return FALSE
	return TRUE

/// Seed `overmap_site_lz_count` landing zones on `site_z` clear of ruin rects.
/datum/controller/subsystem/overmap/proc/seed_site_landing_zones(site_z, site_name, list/placed_rects)
	var/lz_count = CONFIG_GET(number/overmap_site_lz_count)
	var/lz_side = OVERMAP_SITE_LZ_SIDE
	var/margin = OVERMAP_SITE_EDGE_MARGIN + TRANSITIONEDGE
	var/min_x = margin + 1
	var/min_y = margin + 1
	var/max_x = world.maxx - margin - lz_side + 1
	var/max_y = world.maxy - margin - lz_side + 1
	if(max_x < min_x || max_y < min_y)
		return

	var/list/lz_rects = list()
	for(var/i in 1 to lz_count)
		var/turf/lz_turf
		// Random rejection sample first.
		for(var/attempt in 1 to OVERMAP_SITE_PLACE_ATTEMPTS)
			var/try_x = rand(min_x, max_x)
			var/try_y = rand(min_y, max_y)
			var/list/candidate = list(try_x, try_y, try_x + lz_side - 1, try_y + lz_side - 1)
			if(!site_lz_candidate_ok(candidate, placed_rects, lz_rects))
				continue
			lz_turf = locate(try_x, try_y, site_z)
			if(lz_turf)
				lz_rects += list(candidate)
				break
		// Deterministic grid sweep if random sampling failed (dense clusters).
		// Step ≥ 2× side so adjacent cells satisfy OVERMAP_SITE_LZ_SIDE gap.
		if(!lz_turf)
			var/step = max(lz_side * 2, 1)
			for(var/try_x = min_x; try_x <= max_x && !lz_turf; try_x += step)
				for(var/try_y = min_y; try_y <= max_y; try_y += step)
					var/list/candidate = list(try_x, try_y, try_x + lz_side - 1, try_y + lz_side - 1)
					if(!site_lz_candidate_ok(candidate, placed_rects, lz_rects))
						continue
					lz_turf = locate(try_x, try_y, site_z)
					if(lz_turf)
						lz_rects += list(candidate)
						break
		if(!lz_turf)
			WARNING("seed_site_landing_zones: failed to place LZ [i] for [site_name] on Z[site_z]")
			continue
		var/obj/effect/landmark/overmap_landing_zone/zone = new(lz_turf)
		zone.zone_name = lz_count > 1 ? "[site_name] LZ [i]" : site_name
		zone.zone_width = lz_side
		zone.zone_height = lz_side

// --- Cross-faction installation stealth (Phase 6) ---

/// Called when a syndicate station beacon is activated. Permanently reveals
/// the NT station to DS2-affiliated viewers for the rest of the round.
/datum/controller/subsystem/overmap/proc/reveal_station_to_ds2()
	if(station_revealed_to_ds2)
		return
	station_revealed_to_ds2 = TRUE
	log_game("OVERMAP: NT station revealed to DS2 via syndicate beacon.")

/// Determine whether `viewer` (a ship or overmap object) is allowed to see
/// `target` (a level with installation_stealth). Returns TRUE if visible.
///
/// Only blocks cross-faction pairs:
/// - DS2 viewer + main target when !station_revealed_to_ds2
/// - NT viewer + des_two target → always FALSE in v1
/datum/controller/subsystem/overmap/proc/can_view_installation(obj/structure/overmap/viewer, obj/structure/overmap/target)
	if(!istype(target, /obj/structure/overmap/level))
		return TRUE
	var/obj/structure/overmap/level/level_target = target
	if(!level_target.installation_stealth)
		return TRUE

	var/viewer_affiliation = get_affiliation(viewer)
	var/target_id = level_target.id

	// Same-faction always sees home
	if(viewer_affiliation == OVERMAP_AFFILIATION_NT && target_id == MAIN_OVERMAP_OBJECT_ID)
		return TRUE
	if(viewer_affiliation == OVERMAP_AFFILIATION_DS2 && target_id == DES_TWO_OVERMAP_OBJECT_ID)
		return TRUE

	// Cross-faction blocks
	if(viewer_affiliation == OVERMAP_AFFILIATION_DS2 && target_id == MAIN_OVERMAP_OBJECT_ID)
		return station_revealed_to_ds2
	if(viewer_affiliation == OVERMAP_AFFILIATION_NT && target_id == DES_TWO_OVERMAP_OBJECT_ID)
		return FALSE

	// Neutral viewers see everything
	return TRUE

/// Resolve the faction affiliation of an overmap object. Ships use their
/// pinned `home_level_id` (set at bind time); levels use their own ID.
/datum/controller/subsystem/overmap/proc/get_affiliation(obj/structure/overmap/thing)
	if(!thing)
		return OVERMAP_AFFILIATION_NEUTRAL
	if(istype(thing, /obj/structure/overmap/level/main))
		return OVERMAP_AFFILIATION_NT
	if(istype(thing, /obj/structure/overmap/level/site))
		var/obj/structure/overmap/level/site/site = thing
		if(site.id == DES_TWO_OVERMAP_OBJECT_ID)
			return OVERMAP_AFFILIATION_DS2
	if(istype(thing, /obj/structure/overmap/ship/simulated))
		var/obj/structure/overmap/ship/simulated/ship = thing
		switch(ship.home_level_id)
			if(DES_TWO_OVERMAP_OBJECT_ID)
				return OVERMAP_AFFILIATION_DS2
			if(MAIN_OVERMAP_OBJECT_ID)
				return OVERMAP_AFFILIATION_NT
	return OVERMAP_AFFILIATION_NEUTRAL
