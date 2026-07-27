// MODULE ID: OVERMAP

/datum/unit_test/overmap_gps_projection

/datum/unit_test/overmap_gps_projection/proc/empty_overmap_turf()
	for(var/turf/open/overmap/candidate as anything in Z_TURFS(SSovermap.overmap_z))
		if(istype(candidate, /turf/open/overmap/edge))
			continue
		if(locate(/obj/structure/overmap) in candidate)
			continue
		return candidate
	return null

/datum/unit_test/overmap_gps_projection/Run()
	var/turf/grid_turf = empty_overmap_turf()
	TEST_ASSERT(grid_turf, "No empty overmap turf available for GPS projection test.")
	var/turf/source_turf = run_loc_floor_bottom_left
	var/obj/structure/overmap/level/site/source_level = allocate(
		/obj/structure/overmap/level/site,
		grid_turf,
		"unit_test_gps_level",
		list(source_turf.z)
	)
	var/obj/item/pen/first_beacon = allocate(/obj/item/pen, source_turf)
	var/obj/item/pen/second_beacon = allocate(/obj/item/pen, source_turf)
	var/datum/component/gps/first_gps = first_beacon.AddComponent(/datum/component/gps, "ALPHA", TRUE)
	var/datum/component/gps/second_gps = second_beacon.AddComponent(/datum/component/gps, "BRAVO", TRUE)

	TEST_ASSERT_EQUAL(SSovermap.resolve_overmap_object_from_atom(first_beacon), source_level, "GPS source Z should resolve to its owning overmap level.")

	var/obj/machinery/computer/helm/helm = allocate(/obj/machinery/computer/helm, source_turf)
	helm.current_ship = source_level
	var/list/contacts = helm.get_overmap_gps_contacts()
	var/list/source_contact
	for(var/list/contact as anything in contacts)
		if(contact["ref"] == REF(source_level))
			source_contact = contact
			break
	TEST_ASSERT(source_contact, "Active GPS broadcasts should produce an overmap contact.")
	TEST_ASSERT("ALPHA" in source_contact["tags"], "First transponder should appear in its grouped contact.")
	TEST_ASSERT("BRAVO" in source_contact["tags"], "Second transponder should appear in the same grouped contact.")
	TEST_ASSERT(source_contact["local"], "Broadcasts resolved to the helm's object should be classified local.")

	first_gps.tracking = FALSE
	second_gps.emped = TRUE
	contacts = helm.get_overmap_gps_contacts()
	for(var/list/contact as anything in contacts)
		TEST_ASSERT(contact["ref"] != REF(source_level), "Disabled and EMPed broadcasts must be omitted.")

/datum/unit_test/overmap_open_space_site

/datum/unit_test/overmap_open_space_site/proc/empty_overmap_turf()
	for(var/turf/open/overmap/candidate as anything in Z_TURFS(SSovermap.overmap_z))
		if(!istype(candidate, /turf/open/overmap))
			continue
		if(istype(candidate, /turf/open/overmap/edge))
			continue
		if(locate(/obj/structure/overmap) in candidate)
			continue
		return candidate
	return null

/datum/unit_test/overmap_open_space_site/Run()
	var/turf/grid_turf = empty_overmap_turf()
	TEST_ASSERT(grid_turf, "No empty overmap turf available for open-space site test.")
	var/obj/structure/overmap/level/site/open_space/first = SSovermap.get_or_create_open_space_site(grid_turf)
	TEST_ASSERT(first, "Open-space landing should allocate a shared site.")
	TEST_ASSERT(length(first.linked_levels), "Open-space site should own a content Z.")
	var/landing_zone_count = 0
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in SSovermap.landing_zones)
		if(zone.z == first.linked_levels[1])
			landing_zone_count++
	TEST_ASSERT(landing_zone_count > 0, "Open-space content Z should contain landing zones.")
	var/obj/structure/overmap/level/site/open_space/second = SSovermap.get_or_create_open_space_site(grid_turf)
	TEST_ASSERT_EQUAL(first, second, "One shared open-space site should own an overmap tile.")
	qdel(first)

/datum/unit_test/overmap_emergency_brake

/datum/unit_test/overmap_emergency_brake/Run()
	var/turf/grid_turf = locate(2, 3, SSovermap.overmap_z)
	var/turf/machine_turf = run_loc_floor_bottom_left
	TEST_ASSERT(grid_turf && machine_turf, "Missing emergency-brake fixture turfs.")
	var/obj/docking_port/mobile/port = allocate(/obj/docking_port/mobile, machine_turf)
	var/obj/machinery/power/shuttle_engine/overmap/engine = allocate(
		/obj/machinery/power/shuttle_engine/overmap,
		machine_turf
	)
	port.engine_list = list(engine)
	var/obj/structure/overmap/ship/simulated/ship = allocate(
		/obj/structure/overmap/ship/simulated,
		grid_turf,
		"unit_test_recovery_ship",
		port
	)
	port.current_ship = ship
	ship.state = OVERMAP_SHIP_FLYING
	ship.docked = null
	ship.mass = 100
	ship.vel_x = 0.2
	ship.vel_y = 0
	var/engine_integrity_before = engine.get_integrity()
	var/expected_acceleration = (engine.thrust / ship.mass) * OVERMAP_THRUST_ACCEL_SCALE * OVERMAP_EMERGENCY_BRAKE_MULTIPLIER

	TEST_ASSERT(ship.engage_emergency_brake(), "Moving ship should engage its emergency brake.")
	TEST_ASSERT(ship.emergency_braking, "Emergency brake state should remain active until stopped.")
	TEST_ASSERT(abs(ship.emergency_brake_acceleration - expected_acceleration) < 0.0001, "Emergency braking should use three times rated acceleration.")
	TEST_ASSERT(ship.integrity < initial(ship.integrity), "Emergency braking should damage hull integrity once.")
	TEST_ASSERT(engine.get_integrity() < engine_integrity_before, "Emergency braking should physically damage active engines.")
	var/speed_before = ship.get_speed()
	ship.apply_braking(1)
	TEST_ASSERT(abs((speed_before - ship.get_speed()) - expected_acceleration) < 0.0001, "Emergency braking deceleration should match captured authority.")
	var/reference_speed = ship.max_speed > 0 ? ship.max_speed : OVERMAP_MAX_SPEED
	ship.vel_x = reference_speed * 0.01
	ship.emergency_brake_acceleration = 0
	ship.physics_tick(0.1)
	TEST_ASSERT(ship.is_still(), "Emergency braking should settle through Full Stop at one percent.")
	TEST_ASSERT(!ship.emergency_braking, "Emergency braking should disengage after the shared Full Stop path settles the ship.")
