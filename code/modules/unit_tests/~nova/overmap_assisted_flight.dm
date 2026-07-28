/// Flight-assisted thrust/mass envelope and 64×64 grid coverage.

/datum/unit_test/overmap_assisted_flight

/datum/unit_test/overmap_assisted_flight/proc/configure_ship(
	obj/structure/overmap/ship/unit_test_thrust/ship,
	live_thrust,
	available_thrust,
	mass,
)
	ship.test_thrust = live_thrust
	ship.test_available_thrust = available_thrust
	ship.test_mass = mass
	ship.vel_x = 0
	ship.vel_y = 0
	ship.desired_angle = 0
	ship.desired_throttle = 1
	ship.has_heading = TRUE
	ship.refresh_flight_envelope()

/datum/unit_test/overmap_assisted_flight/Run()
	// Use a real overmap turf outside the central star's sphere of influence so
	// the fixture measures propulsion without gravity perturbing velocity.
	var/turf/stage = locate(2, 2, SSovermap.overmap_z)
	TEST_ASSERT(stage, "Missing overmap test stage.")
	var/obj/structure/overmap/ship/unit_test_thrust/ship = allocate(/obj/structure/overmap/ship/unit_test_thrust, stage)

	configure_ship(ship, 30, 30, 100)
	var/reference_speed = ship.max_speed
	var/reference_acceleration = (30 / 100) * OVERMAP_THRUST_ACCEL_SCALE
	var/expected_reference_speed = sqrt(
		2 * reference_acceleration * OVERMAP_ASSIST_BRAKING_DISTANCE,
	)
	TEST_ASSERT(abs(reference_speed - expected_reference_speed) < 0.0001, "Reference assisted speed should follow sqrt(2*a*d). Expected [expected_reference_speed], got [reference_speed].")

	configure_ship(ship, 90, 90, 100)
	TEST_ASSERT(abs((ship.max_speed / reference_speed) - sqrt(3)) < 0.001, "Three engines should raise assisted speed by sqrt(3).")

	configure_ship(ship, 4.5, 4.5, 100)
	TEST_ASSERT(abs((ship.max_speed / reference_speed) - sqrt(0.15)) < 0.001, "Hall-only thrust should scale assisted speed by sqrt(0.15).")

	configure_ship(ship, 30, 30, 250)
	TEST_ASSERT(abs((ship.max_speed / reference_speed) - sqrt(100 / 250)) < 0.001, "Assisted speed should scale with inverse square root of mass.")

	// Partial throttle retains the full-output envelope but selects half its speed.
	configure_ship(ship, 15, 30, 100)
	ship.desired_throttle = 0.5
	for(var/i in 1 to 1000)
		ship.physics_tick(0.2)
		if(abs(ship.get_speed() - ship.max_speed * 0.5) < OVERMAP_VELOCITY_EPSILON)
			break
	TEST_ASSERT(abs(ship.get_speed() - ship.max_speed * 0.5) < 0.002, "Half throttle should converge on half the assisted envelope; speed=[ship.get_speed()], max=[ship.max_speed], desired=[ship.desired_throttle].")

	// Losing capability lowers the target but must decelerate physically, not snap.
	configure_ship(ship, 30, 30, 100)
	ship.vel_x = ship.max_speed
	var/pre_loss_speed = ship.get_speed()
	ship.test_thrust = 4.5
	ship.test_available_thrust = 4.5
	ship.physics_tick(0.2)
	TEST_ASSERT(ship.max_speed < pre_loss_speed, "Engine loss should lower the assisted envelope.")
	TEST_ASSERT(ship.get_speed() > ship.max_speed, "Engine loss must not truncate existing velocity directly to the new envelope.")
	TEST_ASSERT(ship.get_speed() < pre_loss_speed, "Remaining authority should begin decelerating toward the new target.")

	// Full automatic braking from the envelope must stop within the configured horizon.
	configure_ship(ship, 30, 30, 100)
	ship.vel_x = ship.max_speed
	ship.all_stop()
	var/braking_distance = 0
	for(var/i in 1 to 1000)
		ship.physics_tick(0.2)
		braking_distance += ship.get_speed() * 0.2
		if(ship.is_still())
			break
	TEST_ASSERT(ship.is_still(), "All Stop should reach zero velocity.")
	TEST_ASSERT(braking_distance <= OVERMAP_ASSIST_BRAKING_DISTANCE + 0.1, "All Stop exceeded the assisted braking horizon: [braking_distance] tiles.")
	TEST_ASSERT(braking_distance >= OVERMAP_ASSIST_BRAKING_DISTANCE - 0.2, "All Stop stopped unexpectedly early: [braking_distance] tiles.")

	// Helm Full Stop snaps one-percent residual drift, but keeps meaningful
	// velocity on the normal physical braking path.
	configure_ship(ship, 30, 30, 100)
	ship.vel_x = ship.max_speed * 0.01
	ship.full_stop()
	TEST_ASSERT(ship.is_still(), "Full Stop should settle velocity at one percent of the flight envelope.")
	configure_ship(ship, 30, 30, 100)
	ship.vel_x = ship.max_speed * 0.02
	ship.full_stop()
	TEST_ASSERT(!ship.is_still(), "Full Stop should not instantly erase velocity above one percent.")

	// Integrate a full diagonal trip: accelerate, cruise, then All Stop.
	configure_ship(ship, 30, 30, 100)
	var/diagonal_distance = (OVERMAP_DIMENSIONS - 3) * sqrt(2)
	var/traveled = 0
	var/elapsed = 0
	var/braking = FALSE
	for(var/i in 1 to 3000)
		var/available_acceleration = ship.get_available_acceleration()
		var/stopping_distance = available_acceleration > 0 \
			? (ship.get_speed() ** 2) / (2 * available_acceleration) \
			: INFINITY
		if(!braking && diagonal_distance - traveled <= stopping_distance)
			ship.all_stop()
			braking = TRUE
		ship.physics_tick(0.2)
		traveled += ship.get_speed() * 0.2
		elapsed += 0.2
		if(braking && ship.is_still())
			break
	TEST_ASSERT(ship.is_still(), "Reference diagonal traversal should finish braking.")
	TEST_ASSERT(elapsed >= 330 && elapsed <= 390, "Reference diagonal traversal should take about six minutes, got [elapsed / 60] minutes.")
	TEST_ASSERT(abs(traveled - diagonal_distance) < 0.25, "Reference diagonal traversal should end near its target distance; error [traveled - diagonal_distance] tiles.")

/datum/unit_test/overmap_grid_dimensions

/datum/unit_test/overmap_grid_dimensions/Run()
	TEST_ASSERT_EQUAL(SSovermap.size, OVERMAP_DIMENSIONS, "Subsystem size must use OVERMAP_DIMENSIONS.")
	TEST_ASSERT_EQUAL(SSovermap.size, 64, "Core overmap grid should be 64×64.")

	var/center_coord = round(SSovermap.size / 2)
	var/turf/center = locate(center_coord, center_coord, SSovermap.overmap_z)
	TEST_ASSERT(center, "Missing center overmap turf.")
	TEST_ASSERT(locate(/obj/structure/overmap/celestial/star) in center, "Overmap star should remain centered after grid expansion.")

	var/turf/corner = locate(1, 1, SSovermap.overmap_z)
	var/turf/interior = locate(2, 2, SSovermap.overmap_z)
	TEST_ASSERT(istype(corner, /turf/open/overmap/edge), "Grid border must use overmap edge turfs.")
	TEST_ASSERT(istype(interior, /turf/open/overmap), "Grid interior must use open overmap turfs.")
	TEST_ASSERT(!istype(interior, /turf/open/overmap/edge), "Interior turf must not be an edge turf.")
