// MODULE ID: BLASTWAVE_BLUESPACE
// Interdiction is no longer all-or-nothing per Z. An array covers a radius set by its capacitor, and
// only a tier four one blacks out the level, so the coverage maths is now load-bearing for whether a
// teleport goes through. These pin down the tier ladder, the order the check runs in, and the
// refcounting that stops one array standing down from clearing space another still holds.

/datum/unit_test/teleport_jam_range
	abstract_type = /datum/unit_test/teleport_jam_range

/// A self-powered array at `location` refitted with `capacitor_path`. Self-powered so the fixture
/// does not depend on the test area having an APC behind it, which would make is_operational false
/// and leave every assertion here passing for the wrong reason.
/datum/unit_test/teleport_jam_range/proc/build_jammer(capacitor_path, turf/location)
	var/obj/machinery/teleport_jammer/jammer = allocate(/obj/machinery/teleport_jammer/self_powered, location)

	// The board defaults the capacitor to tier four, so clear whatever it fitted before adding ours.
	var/list/fitted = list()
	for(var/datum/stock_part/capacitor/existing in jammer.component_parts)
		fitted += existing
	jammer.component_parts -= fitted
	jammer.component_parts += GLOB.stock_part_datums[capacitor_path]
	jammer.RefreshParts()

	return jammer

/// The capacitor alone decides coverage, and tier four is the only one that takes the whole level.
/datum/unit_test/teleport_jam_range/tiers_set_coverage

/datum/unit_test/teleport_jam_range/tiers_set_coverage/Run()
	var/list/expected = list(
		/datum/stock_part/capacitor = 20,
		/datum/stock_part/capacitor/tier2 = 40,
		/datum/stock_part/capacitor/tier3 = 100,
		/datum/stock_part/capacitor/tier4 = JAM_RANGE_WHOLE_Z,
	)

	for(var/capacitor_path in expected)
		var/obj/machinery/teleport_jammer/jammer = build_jammer(capacitor_path, run_loc_floor_bottom_left)
		TEST_ASSERT_EQUAL(jammer.jam_range, expected[capacitor_path], "[capacitor_path] should set a coverage of [expected[capacitor_path]].")

/// A ranged array reaches exactly as far as its rating and no further.
/datum/unit_test/teleport_jam_range/short_range_respects_distance

/datum/unit_test/teleport_jam_range/short_range_respects_distance/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/inside = locate(origin.x + 10, origin.y, origin.z)
	var/turf/outside = locate(origin.x + 25, origin.y, origin.z)
	TEST_ASSERT(!isnull(inside) && !isnull(outside), "This test needs 25 tiles of room east of the origin to measure against.")

	build_jammer(/datum/stock_part/capacitor, origin)

	TEST_ASSERT(is_teleport_jammed(origin), "A tier one array must jam the tile it stands on.")
	TEST_ASSERT(is_teleport_jammed(inside), "A tier one array must jam 10 tiles out, well inside its 20 tile rating.")
	TEST_ASSERT(!is_teleport_jammed(outside), "A tier one array must not reach 25 tiles out. Flying around it is the counterplay.")

/// Tier four stops measuring and takes the level, which is what the salvaged derelict arrays do.
/datum/unit_test/teleport_jam_range/whole_z_ignores_distance

/datum/unit_test/teleport_jam_range/whole_z_ignores_distance/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/outside = locate(origin.x + 25, origin.y, origin.z)
	TEST_ASSERT(!isnull(outside), "This test needs 25 tiles of room east of the origin to measure against.")

	build_jammer(/datum/stock_part/capacitor/tier4, origin)

	TEST_ASSERT(is_teleport_jammed(origin), "A tier four array must jam the tile it stands on.")
	TEST_ASSERT(is_teleport_jammed(outside), "A tier four array must jam a tile a tier one demonstrably cannot reach.")

/// The level trait answers on its own, before any source is looked up. A static map that declares
/// itself dark has no machine to interrogate, so it has to read as jammed with the registry empty.
/datum/unit_test/teleport_jam_range/level_trait_answers_first

/datum/unit_test/teleport_jam_range/level_trait_answers_first/Run()
	var/turf/origin = run_loc_floor_bottom_left
	TEST_ASSERT(!is_teleport_jammed(origin), "Nothing should be jamming the test Z before this test touches it.")
	TEST_ASSERT(isnull(GLOB.teleport_jam_zones["[origin.z]"]), "This test only proves anything with no zone datum present.")

	// Read the answer, then put the trait back before asserting. A failed TEST_ASSERT returns early,
	// and a trait left behind would black out bluespace for every test that runs after this one.
	var/datum/space_level/level = SSmapping.z_list[origin.z]
	level.traits[ZTRAIT_NO_TELEPORT] = TRUE
	var/jammed_by_trait = is_teleport_jammed(origin)
	level.traits -= ZTRAIT_NO_TELEPORT

	TEST_ASSERT(jammed_by_trait, "A level declaring ZTRAIT_NO_TELEPORT must read as jammed with no source registered at all.")
	TEST_ASSERT(!is_teleport_jammed(origin), "Clearing the trait must open the level back up.")

/// Cutting a live lead is the quiet way to switch an array off, and mending it is how you undo that.
/datum/unit_test/teleport_jam_range/cut_wire_drops_field

/datum/unit_test/teleport_jam_range/cut_wire_drops_field/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/obj/machinery/teleport_jammer/jammer = build_jammer(/datum/stock_part/capacitor/tier4, origin)
	TEST_ASSERT(is_teleport_jammed(origin), "The fixture should be jamming before anything is cut.")

	// cut() toggles, so each call flips the lead it is handed.
	jammer.wires.cut(WIRE_ACTIVATE)
	TEST_ASSERT(!is_teleport_jammed(origin), "Cutting the activate lead must drop the field.")
	TEST_ASSERT(!jammer.is_jamming(), "A severed array must not still believe it holds a claim.")

	jammer.wires.cut(WIRE_ACTIVATE)
	TEST_ASSERT(is_teleport_jammed(origin), "Mending the activate lead must bring the field back.")

	jammer.wires.cut(WIRE_ACTIVATE)
	jammer.wires.cut(WIRE_POWER)
	jammer.wires.cut(WIRE_ACTIVATE)
	TEST_ASSERT(!is_teleport_jammed(origin), "With both leads cut, mending only one must leave the field down.")

/// Two arrays over the same space each have to release before it opens up.
/datum/unit_test/teleport_jam_range/overlapping_arrays_refcount

/datum/unit_test/teleport_jam_range/overlapping_arrays_refcount/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/obj/machinery/teleport_jammer/first = build_jammer(/datum/stock_part/capacitor/tier4, origin)
	var/obj/machinery/teleport_jammer/second = build_jammer(/datum/stock_part/capacitor/tier4, origin)
	TEST_ASSERT(is_teleport_jammed(origin), "Two arrays over one tile should certainly be jamming it.")

	first.wires.cut(WIRE_POWER)
	TEST_ASSERT(is_teleport_jammed(origin), "One array standing down must not clear space the other still covers.")

	second.wires.cut(WIRE_POWER)
	TEST_ASSERT(!is_teleport_jammed(origin), "The space clears only once every array has released.")
	TEST_ASSERT(isnull(GLOB.teleport_jam_zones["[origin.z]"]), "The zone datum must be dropped once its last claim goes, not left behind empty.")
