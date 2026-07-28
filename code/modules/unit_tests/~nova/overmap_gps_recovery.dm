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

	// The teardown cases below reuse the Z this site already took. Asking the
	// subsystem for another would hand them a brand new one: recycling only
	// republishes a Z after sweeping every turf on it, which takes longer than a
	// test should sit and wait. BYOND never gives a Z level back either, so each
	// one is world.maxx * world.maxy turfs resident for the rest of the process
	// - on a large map, the most expensive thing a test can leave behind.
	var/content_z = first.linked_levels[1]
	var/allocated_maxz = world.maxz
	qdel(first)

	// Deleting a site hands its content Z back, and that sweep touches every
	// turf on the level. The handoff has to outlive the site without dragging
	// the site along: INVOKE_ASYNC is spawn(), a spawn inherits src, and one
	// started from the teardown kept the site referenced until the sweep
	// finished. Reference tracking never saw it - the reference lived in an
	// execution context rather than a variable - and it only hard deleted when
	// the sweep outran the collector, which made a real leak look flaky.
	var/turf/deleted_turf = empty_overmap_turf()
	TEST_ASSERT(deleted_turf, "No empty overmap turf available for the deletion case.")
	TEST_ASSERT_EQUAL(refs_after_delete(deleted_turf, content_z), 2, "Deleting an open-space site left it referenced; it will hard delete.")

	// The route a round actually takes: the last ship leaves and the site
	// retires itself. Checked for behaviour rather than reference count - it
	// settles one above the deletion path, and chasing that number here would
	// only make the test brittle when create_and_destroy already proves the
	// site is collected.
	var/turf/retired_turf = empty_overmap_turf()
	TEST_ASSERT(retired_turf, "No empty overmap turf available for the retirement case.")
	var/obj/structure/overmap/level/site/open_space/retiring = new(retired_turf, "open_space_test_retire", list(content_z))
	TEST_ASSERT(retiring, "Retirement case should build a site.")
	retiring.try_cleanup()
	TEST_ASSERT(QDELETED(retiring), "An unoccupied open-space site should retire itself once nothing is aboard.")
	TEST_ASSERT_EQUAL(world.maxz, allocated_maxz, "The open-space cases took new Z levels rather than sharing one.")

/// What is left holding a site once it has been deleted.
///
/// SSgarbage frees an object when nothing but the queue's reference and the
/// caller's own local remain, so a clean teardown reads exactly two and
/// anything higher is a hard delete waiting on the collector to give up. This
/// has to be measured in a frame of its own: locals in the calling proc, and
/// the temporaries the assertion macros declare, all count too.
/datum/unit_test/overmap_open_space_site/proc/refs_after_delete(turf/grid_turf, content_z)
	var/obj/structure/overmap/level/site/open_space/site = new(grid_turf, "open_space_test_delete", list(content_z))
	if(!site)
		return 0
	qdel(site)
	// Settle first. The collector does not judge an object the instant it is
	// queued either, and references belonging to the deleting tick - the timer
	// waiting to fire, the frame that called us - are not what strands it.
	sleep(1 SECONDS)
	return refcount(site)

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
