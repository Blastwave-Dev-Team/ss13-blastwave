// MODULE ID: OVERMAP
// Overmap hazards only bite ships sharing their tile. close_overmap_objects deliberately reaches
// a tile further than that so helms can see and dock with neighbours, so a hazard that trusts the
// list wholesale chews up ships that correctly flew the lane beside the storm instead of through it.

/// Counts calls rather than dealing damage. The real affect_ship() overrides bail out without a
/// live shuttle, so an integrity-based assertion would pass whether or not the scoping works.
/obj/structure/overmap/event/hazard_scope_probe
	name = "test hazard"
	affect_multiple_times = TRUE
	chance_to_affect = 100
	var/hits = 0

/obj/structure/overmap/event/hazard_scope_probe/affect_ship(obj/structure/overmap/ship/simulated/ship)
	hits++

/datum/unit_test/overmap_hazard_scope

/datum/unit_test/overmap_hazard_scope/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/stage = locate(origin.x + 2, origin.y + 2, origin.z)
	TEST_ASSERT(istype(stage, /turf), "Missing stage turf for the hazard fixture.")
	var/turf/neighbour = get_step(stage, EAST)
	TEST_ASSERT(istype(neighbour, /turf), "Stage turf needs an east neighbour.")

	var/obj/structure/overmap/event/hazard_scope_probe/hazard = allocate(/obj/structure/overmap/event/hazard_scope_probe, stage)
	var/obj/structure/overmap/ship/simulated/ship = allocate(/obj/structure/overmap/ship/simulated, neighbour)

	// The neighbour has to actually be in interaction range, or the loop would skip it however
	// the scoping is written and the test would prove nothing.
	hazard.refresh_close_overmap_objects()
	TEST_ASSERT(ship in hazard.close_overmap_objects, "Fixture needs the adjacent ship in interaction range.")

	hazard.apply_effect()
	TEST_ASSERT_EQUAL(hazard.hits, 0, "A hazard must not affect a ship one tile away.")

	ship.forceMove(stage)
	hazard.refresh_close_overmap_objects()
	TEST_ASSERT(ship in hazard.close_overmap_objects, "A co-located ship must still be in range.")

	// SSovermap ticks apply_effect() on its own, so compare against a reading taken just before
	// our call rather than asserting an absolute count.
	var/before = hazard.hits
	hazard.apply_effect()
	TEST_ASSERT(hazard.hits > before, "A hazard must affect a ship sharing its tile.")
