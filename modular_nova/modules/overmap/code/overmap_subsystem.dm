// MODULE ID: OVERMAP
// SSovermap allocates a dedicated Z-level for the overmap grid and is the
// owner of the overmap object registry and helper procs. Per the
// implementation plan, M1 only delivers Z allocation, a programmatic
// 20x20 grid, and a star at the center; static POIs (M2), ship binding
// (M3) and onward extend this subsystem.

SUBSYSTEM_DEF(overmap)
	name = "Overmap"
	wait = 10
	dependencies = list(
		/datum/controller/subsystem/mapping,
		/datum/controller/subsystem/shuttle,
	)
	ss_flags = SS_KEEP_TIMING
	runlevels = RUNLEVEL_SETUP | RUNLEVEL_GAME

	/// Width/height of the overmap grid (square).
	var/size = OVERMAP_DIMENSIONS
	/// All overmap objects in the world (stars, levels, ships, future events).
	var/list/overmap_objects
	/// All currently registered ship objects (subset of overmap_objects).
	var/list/simulated_ships
	/// All currently registered helm consoles. Used to rebind helms when a
	/// shuttle is loaded after SSovermap init (e.g. the emergency shuttle).
	var/list/helms
	/// All currently registered overmap-aware nav consoles (M6).
	var/list/navs
	/// The station-tied overmap object. Set by `/level/main` on init.
	var/obj/structure/overmap/level/main/main
	/// Z-value of the dedicated overmap grid. Looked up via `levels_by_trait`
	/// in case other code needs it post-init.
	var/overmap_z
	/// Generator strategy. Hardcoded RANDOM for the prototype; the SOLAR
	/// branch is deferred to the post-prototype backlog.
	var/generator_type = OVERMAP_GENERATOR_RANDOM

/datum/controller/subsystem/overmap/Initialize()
	allocate_overmap_zlevel()
	build_grid()
	place_star()
	create_map()
	bind_existing_shuttles()
	bind_existing_consoles()
	return SS_INIT_SUCCESS

/// Walks helms / navs that registered before SSovermap init (i.e. roundstart
/// shuttle areas) and binds them to their target ship.
/datum/controller/subsystem/overmap/proc/bind_existing_consoles()
	for(var/obj/machinery/computer/helm/helm in helms)
		helm.set_ship()
	for(var/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/nav in navs)
		nav.link_shuttle()

/datum/controller/subsystem/overmap/fire()
	// Empty for the prototype. Events module will subscribe here.
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
		new /obj/structure/overmap/star(center)

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

/// Roundstart placement of static POIs (station, mining body) on the grid.
/// Reads `SSmapping` for Z-trait grouping. Per the implementation plan,
/// dynamic encounters / events / ruin levels are deferred past prototype.
/datum/controller/subsystem/overmap/proc/create_map()
	place_station()
	place_mining()

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
