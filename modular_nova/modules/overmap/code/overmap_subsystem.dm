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
			if(new_turf && get_area(new_turf) != area)
				area.contents += new_turf
				LISTASSERTLEN(area.turfs_by_zlevel, new_turf.z, list())
				area.turfs_by_zlevel[new_turf.z] += new_turf

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

/// Returns the level overmap object whose `linked_levels` contains `zlevel`,
/// or null. Used by ship binding (M3) and dock resolution (M6).
/datum/controller/subsystem/overmap/proc/get_overmap_object_by_z(zlevel)
	for(var/obj/structure/overmap/level/object in overmap_objects)
		if(zlevel in object.linked_levels)
			return object
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
/// Ports created post-init route through the NOVA EDIT in mobile_port.dm's
/// `Initialize` instead.
/datum/controller/subsystem/overmap/proc/bind_existing_shuttles()
	for(var/obj/docking_port/mobile/port in SSshuttle.mobile_docking_ports)
		if(istype(port, /obj/docking_port/mobile/arrivals))
			continue
		setup_shuttle_ship(port)

/// Create an overmap ship icon for a single mobile docking port. Resolves
/// the port's Z to a known POI; if the port lives on a reserved/CentCom
/// Z (e.g. emergency shuttle in transit) the icon is parked off-grid and
/// will resync via `check_loc()` once the port lands somewhere mapped.
/datum/controller/subsystem/overmap/proc/setup_shuttle_ship(obj/docking_port/mobile/port)
	if(!port || port.current_ship)
		return
	var/obj/structure/overmap/level/parent_level = get_overmap_object_by_z(port.z)
	var/obj/structure/overmap/ship/simulated/ship
	if(parent_level)
		ship = new(parent_level, port.shuttle_id, port)
		ship.docked = parent_level
		ship.state = OVERMAP_SHIP_IDLE
	else if(SSmapping.level_trait(port.z, ZTRAIT_RESERVED))
		// In transit (e.g. Shuttle Manipulator load, or a shuttle that hasn't
		// landed yet). Park the icon on the station's overmap tile and treat
		// the ship as if it had just undocked: state = FLYING, mass / engines
		// / fuel pre-computed so the helm UI is fly-ready without requiring
		// a manual undock. Falls back to a random empty tile if main is unset.
		var/turf/parked = main ? get_turf(main) : get_unused_overmap_square()
		if(parked)
			ship = new(parked, port.shuttle_id, port)
			ship.state = OVERMAP_SHIP_FLYING
			ship.prepare_for_flight()
	else if(is_centcom_level(port.z))
		// CentCom is intentionally off-grid. Icon lives in nullspace until
		// the shuttle returns to a known POI.
		ship = new(null, port.shuttle_id, port)
	else
		WARNING("setup_shuttle_ship: shuttle [port.shuttle_id] is on an unknown Z [port.z]; skipping.")
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

/// Reserves a turf block, optionally generates terrain and loads a ruin,
/// then creates stationary docking ports for the visiting shuttle.
/datum/controller/subsystem/overmap/proc/spawn_dynamic_encounter(planet_type, ruin = TRUE, dock_id, size, obj/docking_port/mobile/visiting_shuttle)
	if(!COOLDOWN_FINISHED(src, encounter_cooldown))
		return null
	COOLDOWN_START(src, encounter_cooldown, OVERMAP_ENCOUNTER_COOLDOWN)

	if(!dock_id)
		CRASH("spawn_dynamic_encounter called without a dock_id!")

	if(!size)
		size = round(world.maxx / 4)

	var/dock_size = round(size / 2)
	var/ruin_size = CEILING(size / 2, 1)
	if(visiting_shuttle)
		dock_size = max(visiting_shuttle.width, visiting_shuttle.height) + 3

	var/total_size = dock_size + ruin_size

	var/list/ruin_list
	var/datum/map_generator/mapgen
	var/area/target_area

	if(planet_type)
		switch(planet_type)
			if(DYNAMIC_WORLD_LAVA)
				ruin_list = SSmapping.themed_ruins[ZTRAIT_LAVA_RUINS]
				mapgen = new /datum/map_generator/cave_generator/lavaland
				target_area = /area/lavaland/surface/outdoors/unexplored
			if(DYNAMIC_WORLD_ICE)
				ruin_list = SSmapping.themed_ruins[ZTRAIT_ICE_RUINS]
				mapgen = new /datum/map_generator/cave_generator/icemoon/surface
				target_area = /area/icemoon/surface/outdoors/unexplored
			if(DYNAMIC_WORLD_JUNGLE)
				ruin_list = SSmapping.themed_ruins[ZTRAIT_SPACE_RUINS]
				target_area = /area/space
			if(DYNAMIC_WORLD_SAND)
				ruin_list = SSmapping.themed_ruins[ZTRAIT_LAVA_RUINS]
				mapgen = new /datum/map_generator/cave_generator/lavaland
				target_area = /area/lavaland/surface/outdoors/unexplored
	else
		ruin_list = SSmapping.themed_ruins[ZTRAIT_SPACE_RUINS]

	var/datum/map_template/ruin/ruin_type
	if(ruin && length(ruin_list))
		var/max_ruin_dimension = total_size - dock_size - 4
		var/list/viable_ruins = list()
		for(var/ruin_name in ruin_list)
			var/datum/map_template/ruin/candidate = ruin_list[ruin_name]
			if(ispath(candidate))
				candidate = new candidate
			if(max(candidate.width, candidate.height) <= max_ruin_dimension)
				// Skip ruins already placed as named overmap sites
				if(candidate.id in placed_site_template_ids)
					continue
				viable_ruins[ruin_name] = candidate
		if(length(viable_ruins))
			ruin_type = viable_ruins[pick(viable_ruins)]
			ruin_size = max(ruin_type.width, ruin_type.height) + 4
			total_size = dock_size + ruin_size

	var/datum/turf_reservation/encounter_reservation = SSmapping.request_turf_block_reservation(total_size, total_size)
	if(!encounter_reservation)
		return null

	if(mapgen && target_area)
		var/list/gen_turfs = encounter_reservation.reserved_turfs.Copy()
		if(length(gen_turfs))
			mapgen.generate_terrain(gen_turfs)

	var/turf/bottom_left = encounter_reservation.bottom_left_turfs[1]
	if(!bottom_left)
		QDEL_NULL(encounter_reservation)
		return null

	if(ruin_type)
		var/turf/ruin_turf = locate( \
			bottom_left.x + dock_size + 2, \
			bottom_left.y + dock_size, \
			bottom_left.z)
		if(ruin_turf)
			ruin_type.load(ruin_turf)

	// Create primary dock
	var/turf/dock_turf = locate( \
		bottom_left.x + dock_size, \
		bottom_left.y + round(dock_size / 2), \
		bottom_left.z)
	var/obj/docking_port/stationary/primary_dock = new(dock_turf)
	primary_dock.dir = WEST
	primary_dock.name = "\improper Uncharted Space"
	primary_dock.shuttle_id = "[OVERMAP_DOCK_PREFIX]_[dock_id]"
	primary_dock.height = dock_size
	primary_dock.width = dock_size
	if(visiting_shuttle)
		primary_dock.dheight = min(visiting_shuttle.dheight, dock_size)
		primary_dock.dwidth = min(visiting_shuttle.dwidth, dock_size)
	else
		primary_dock.dwidth = round(dock_size / 2)

	// Create secondary dock
	var/turf/secondary_turf = locate( \
		bottom_left.x + dock_size, \
		bottom_left.y + CEILING(dock_size * 1.5, 1), \
		bottom_left.z)
	var/obj/docking_port/stationary/secondary_dock = new(secondary_turf)
	secondary_dock.dir = WEST
	secondary_dock.name = "\improper Uncharted Space"
	secondary_dock.shuttle_id = "[OVERMAP_FERRY_PREFIX]_[dock_id]"
	secondary_dock.height = dock_size
	secondary_dock.width = dock_size
	secondary_dock.dwidth = round(dock_size / 2)

	return encounter_reservation

// --- Space site seeding (Phase 3) ---

/// Seed named space ruin POIs onto the overmap grid. Priority pass for
/// always_place ruins, then budget fill from the weighted space ruin pool.
/// Only called when `overmap_space_ruins` is TRUE on the map config.
/datum/controller/subsystem/overmap/proc/seed_space_sites()
	var/list/space_ruins = SSmapping.themed_ruins[ZTRAIT_SPACE_RUINS]
	if(!length(space_ruins))
		return

	var/list/placed_template_ids = list()
	var/max_sites = CONFIG_GET(number/max_overmap_named_sites)

	// Priority pass: always_place ruins get guaranteed slots.
	for(var/ruin_name in space_ruins)
		var/datum/map_template/ruin/candidate = space_ruins[ruin_name]
		if(ispath(candidate))
			candidate = new candidate
		if(!candidate.always_place)
			continue
		var/obj/structure/overmap/level/site/site = spawn_overmap_site(candidate)
		if(site)
			placed_template_ids += candidate.id
			placed_site_template_ids += candidate.id
			// DS2 gets installation stealth
			if(candidate.id == "des_two")
				site.installation_stealth = TRUE

	// Budget fill: pick from remaining weighted pool up to max_sites.
	var/budget = CONFIG_GET(number/space_budget)
	var/list/available = list()
	for(var/ruin_name in space_ruins)
		var/datum/map_template/ruin/candidate = space_ruins[ruin_name]
		if(ispath(candidate))
			candidate = new candidate
		if(candidate.always_place || candidate.unpickable)
			continue
		if(candidate.id in placed_template_ids)
			continue
		available[candidate] = candidate.placement_weight

	while(budget > 0 && length(available) && length(placed_template_ids) < max_sites)
		var/datum/map_template/ruin/picked = pick_weight(available)
		if(!picked)
			break
		if(picked.cost > budget)
			available -= picked
			continue
		var/obj/structure/overmap/level/site/site = spawn_overmap_site(picked)
		if(!site)
			break
		placed_template_ids += picked.id
		placed_site_template_ids += picked.id
		budget -= picked.cost
		if(!picked.allow_duplicates)
			available -= picked

/// Spawn a single named site POI: reserve a turf block, load the ruin
/// template, create docking ports, and place the `/level/site` on the grid.
/datum/controller/subsystem/overmap/proc/spawn_overmap_site(datum/map_template/ruin/template)
	if(!template)
		return null

	var/turf/grid_turf = get_unused_overmap_square()
	if(!grid_turf)
		WARNING("spawn_overmap_site: no free overmap tile for [template.name]")
		return null

	var/site_id = template.id || "site_[length(overmap_objects)]"
	var/size = max(template.width, template.height) + 8
	var/dock_size = round(size / 2)

	var/datum/turf_reservation/reserve = SSmapping.request_turf_block_reservation(size, size)
	if(!reserve)
		WARNING("spawn_overmap_site: failed to reserve turf block for [template.name]")
		return null

	var/turf/bottom_left = reserve.bottom_left_turfs[1]
	if(!bottom_left)
		QDEL_NULL(reserve)
		return null

	// Load the ruin template
	var/turf/ruin_turf = locate( \
		bottom_left.x + dock_size + 2, \
		bottom_left.y + dock_size, \
		bottom_left.z)
	if(ruin_turf)
		template.load(ruin_turf)

	// Create primary dock
	var/turf/dock_turf = locate( \
		bottom_left.x + dock_size, \
		bottom_left.y + round(dock_size / 2), \
		bottom_left.z)
	var/obj/docking_port/stationary/primary_dock = new(dock_turf)
	primary_dock.dir = WEST
	primary_dock.name = "\improper [template.name]"
	primary_dock.shuttle_id = "[OVERMAP_DOCK_PREFIX]_[site_id]"
	primary_dock.height = dock_size
	primary_dock.width = dock_size
	primary_dock.dwidth = round(dock_size / 2)

	// Create secondary (ferry) dock
	var/turf/secondary_turf = locate( \
		bottom_left.x + dock_size, \
		bottom_left.y + CEILING(dock_size * 1.5, 1), \
		bottom_left.z)
	var/obj/docking_port/stationary/secondary_dock = new(secondary_turf)
	secondary_dock.dir = WEST
	secondary_dock.name = "\improper [template.name]"
	secondary_dock.shuttle_id = "[OVERMAP_FERRY_PREFIX]_[site_id]"
	secondary_dock.height = dock_size
	secondary_dock.width = dock_size
	secondary_dock.dwidth = round(dock_size / 2)

	// Place the site on the overmap grid
	var/list/site_zs = list(bottom_left.z)
	var/obj/structure/overmap/level/site/site = new(grid_turf, site_id, site_zs, template)
	site.reserve = reserve
	site.preloaded = TRUE

	// Handle always_spawn_with chains
	if(template.always_spawn_with)
		for(var/chain_type in template.always_spawn_with)
			if(template.always_spawn_with[chain_type] != PLACE_SAME_Z)
				continue
			for(var/ruin_name in SSmapping.ruins_templates)
				var/datum/map_template/ruin/linked = SSmapping.ruins_templates[ruin_name]
				if(!istype(linked, chain_type))
					continue
				var/turf/chain_turf = locate( \
					bottom_left.x + 2, \
					bottom_left.y + 2, \
					bottom_left.z)
				if(chain_turf)
					linked.load(chain_turf)
				LAZYADD(site.chained_templates, linked)

	return site

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

/// Resolve the faction affiliation of an overmap object. Ships derive
/// affiliation from their home Z; levels use their own ID.
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
		if(ship.shuttle)
			var/home_z = ship.shuttle.z
			var/obj/structure/overmap/level/home_level = get_overmap_object_by_z(home_z)
			if(home_level)
				if(home_level.id == DES_TWO_OVERMAP_OBJECT_ID)
					return OVERMAP_AFFILIATION_DS2
				if(home_level.id == MAIN_OVERMAP_OBJECT_ID)
					return OVERMAP_AFFILIATION_NT
	return OVERMAP_AFFILIATION_NEUTRAL
