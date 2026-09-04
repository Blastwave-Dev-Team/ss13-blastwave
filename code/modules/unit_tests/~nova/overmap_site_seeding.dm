// MODULE ID: OVERMAP
// Unit tests for full-Z cluster / solo site seeding and LZ docking.

/// Cluster partition: ruins ≤ OVERMAP_CLUSTER_RUIN_MAX_SIDE are cluster-sized.
/datum/unit_test/overmap_cluster_partition

/datum/unit_test/overmap_cluster_partition/Run()
	var/datum/map_template/ruin/small = new
	small.width = 20
	small.height = 15
	TEST_ASSERT(SSovermap.is_overmap_cluster_ruin(small), "20x15 should be cluster-sized.")

	var/datum/map_template/ruin/edge = new
	edge.width = OVERMAP_CLUSTER_RUIN_MAX_SIDE
	edge.height = OVERMAP_CLUSTER_RUIN_MAX_SIDE
	TEST_ASSERT(SSovermap.is_overmap_cluster_ruin(edge), "Exact max side should be cluster-sized.")

	var/datum/map_template/ruin/large = new
	large.width = OVERMAP_CLUSTER_RUIN_MAX_SIDE + 1
	large.height = 10
	TEST_ASSERT(!SSovermap.is_overmap_cluster_ruin(large), "Side above max should be solo-sized.")

/// Station-relative site placement stays inside the requested chebyshev band.
/datum/unit_test/overmap_site_distance_band

/datum/unit_test/overmap_site_distance_band/Run()
	if(!SSovermap.main || !SSovermap.overmap_z)
		return
	var/turf/station = get_turf(SSovermap.main)
	TEST_ASSERT(station, "Station overmap POI has no turf.")
	var/turf/picked = SSovermap.get_unused_overmap_square_near(SSovermap.main, 6, 10)
	TEST_ASSERT(picked, "Distance-banded placement should find a free tile.")
	var/dist = get_dist(station, picked)
	TEST_ASSERT(dist >= 6, "Banded tile [AREACOORD(picked)] is [dist] from station, expected >= 6.")
	TEST_ASSERT(dist <= 10, "Banded tile [AREACOORD(picked)] is [dist] from station, expected <= 10.")

	for(var/obj/structure/overmap/poi in SSovermap.overmap_objects)
		var/list/band = SSovermap.get_site_distance_band(poi.id)
		if(!band)
			continue
		var/site_dist = get_dist(station, get_turf(poi))
		if(band[1])
			TEST_ASSERT(site_dist >= band[1], "POI [poi.id] is [site_dist] from station, expected >= [band[1]].")
		if(band[2])
			TEST_ASSERT(site_dist <= band[2], "POI [poi.id] is [site_dist] from station, expected <= [band[2]].")

/// Site Zs seed landing zones and have no premapped OVERMAP_DOCK ports.
/datum/unit_test/overmap_site_lz_seeding

/datum/unit_test/overmap_site_lz_seeding/Run()
	if(!SSmapping.current_map.overmap_space_ruins)
		return

	var/lz_count = CONFIG_GET(number/overmap_site_lz_count)
	var/checked = 0
	for(var/obj/structure/overmap/level/site/site in SSovermap.overmap_objects)
		var/site_z = site.linked_levels?[1]
		TEST_ASSERT(site_z, "Site [site.id] missing linked Z.")
		var/zones_on_z = 0
		for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in SSovermap.landing_zones)
			if(zone.z == site_z)
				zones_on_z++
		TEST_ASSERT_EQUAL(zones_on_z, lz_count, "Site [site.id] Z[site_z] expected [lz_count] LZs, got [zones_on_z].")

		for(var/obj/docking_port/stationary/port as anything in SSshuttle.stationary_docking_ports)
			if(port.z != site_z)
				continue
			TEST_ASSERT(!findtext(port.shuttle_id, OVERMAP_DOCK_PREFIX), "Site Z[site_z] still has premapped dock [port.shuttle_id].")
			TEST_ASSERT(!findtext(port.shuttle_id, OVERMAP_FERRY_PREFIX), "Site Z[site_z] still has ferry dock [port.shuttle_id].")
		checked++
	TEST_ASSERT(checked > 0, "No sites to check for LZ seeding.")

/// Uncontrolled sites pin a single LZ; controlled sites expose all free LZs.
/datum/unit_test/overmap_site_lz_pinning

/datum/unit_test/overmap_site_lz_pinning/Run()
	if(!SSmapping.current_map.overmap_space_ruins)
		return

	var/obj/structure/overmap/ship/simulated/ship
	for(var/obj/structure/overmap/ship/simulated/candidate in SSovermap.simulated_ships)
		if(candidate.shuttle)
			ship = candidate
			break
	if(!ship)
		return

	var/obj/structure/overmap/level/site/uncontrolled
	var/obj/structure/overmap/level/site/controlled_site
	for(var/obj/structure/overmap/level/site/site in SSovermap.overmap_objects)
		if(!site.controlled && !uncontrolled)
			uncontrolled = site
		if(site.controlled && !controlled_site)
			controlled_site = site
		if(uncontrolled && controlled_site)
			break

	if(uncontrolled)
		var/list/first = ship.get_landing_zones_for(uncontrolled)
		TEST_ASSERT_EQUAL(length(first), 1, "Uncontrolled site should expose exactly one LZ.")
		var/list/second = ship.get_landing_zones_for(uncontrolled)
		TEST_ASSERT_EQUAL(length(second), 1, "Pinned uncontrolled LZ should remain a single entry.")
		TEST_ASSERT_EQUAL(first[1], second[1], "Uncontrolled LZ pin should be stable across calls.")

	if(controlled_site)
		var/list/zones = ship.get_landing_zones_for(controlled_site)
		var/expected = CONFIG_GET(number/overmap_site_lz_count)
		TEST_ASSERT(length(zones) >= 1, "Controlled site should expose at least one LZ.")
		TEST_ASSERT(length(zones) <= expected, "Controlled site exposed more LZs than seeded.")

/// dock() auto-assigns an LZ port when no premapped pad exists on a site.
/datum/unit_test/overmap_site_dock_auto_lz

/datum/unit_test/overmap_site_dock_auto_lz/Run()
	if(!SSmapping.current_map.overmap_space_ruins)
		return

	var/obj/structure/overmap/level/site/site
	for(var/obj/structure/overmap/level/site/candidate in SSovermap.overmap_objects)
		site = candidate
		break
	if(!site)
		return

	var/obj/structure/overmap/ship/simulated/ship
	for(var/obj/structure/overmap/ship/simulated/candidate in SSovermap.simulated_ships)
		if(candidate.shuttle)
			ship = candidate
			break
	if(!ship?.shuttle)
		return

	var/prior_state = ship.state
	var/prior_docked = ship.docked
	ship.state = OVERMAP_SHIP_FLYING
	ship.docked = null
	ship.vel_x = 0
	ship.vel_y = 0

	var/list/zones = ship.get_landing_zones_for(site)
	if(!length(zones))
		ship.state = prior_state
		ship.docked = prior_docked
		return

	var/obj/docking_port/stationary/port = ship.create_landing_zone_port(zones[1])
	TEST_ASSERT(port, "create_landing_zone_port should succeed for site LZ.")
	TEST_ASSERT(SSovermap.dock_footprint_is_clear(port), "Auto LZ port footprint should be clear.")
	qdel(port)

	ship.state = prior_state
	ship.docked = prior_docked

/// Camera clamp rejects turfs outside the allowed LZ union.
/datum/unit_test/overmap_nav_camera_clamp

/datum/unit_test/overmap_nav_camera_clamp/Run()
	var/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/nav = allocate(/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav)
	var/turf/origin = run_loc_floor_bottom_left
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, origin)
	zone.zone_width = 10
	zone.zone_height = 10
	nav.target_zones = list(zone)

	var/turf/inside = locate(origin.x + 2, origin.y + 2, origin.z)
	TEST_ASSERT(nav.turf_in_camera_bounds(inside), "Turf inside LZ should be in camera bounds.")

	var/turf/outside = locate(origin.x + 50, origin.y + 50, origin.z)
	if(outside)
		TEST_ASSERT(!nav.turf_in_camera_bounds(outside), "Turf far outside LZ should be rejected.")
		var/turf/clamped = nav.clamp_eye_turf(outside)
		TEST_ASSERT(nav.turf_in_camera_bounds(clamped), "clamp_eye_turf should return an in-bounds turf.")
