// MODULE ID: OVERMAP
// Mapping helpers: helm affiliation pins and landing-zone beacon links.

/datum/unit_test/overmap_mapping_helpers/helm_affiliation

/datum/unit_test/overmap_mapping_helpers/helm_affiliation/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/structure/overmap/ship/simulated/ship = allocate(/obj/structure/overmap/ship/simulated, stage)
	var/obj/machinery/computer/helm/helm = allocate(/obj/machinery/computer/helm, stage)
	helm.current_ship = ship

	var/obj/effect/mapping_helpers/helm/affiliation/ds2/helper = allocate(/obj/effect/mapping_helpers/helm/affiliation/ds2, stage, helm)
	helper.LateInitialize()

	TEST_ASSERT(QDELETED(helper), "Helm affiliation helper should qdel after applying.")
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_DS2, "DS2 helm helper should pin the bound ship as DS2.")

/datum/unit_test/overmap_mapping_helpers/landing_zone_link

/datum/unit_test/overmap_mapping_helpers/landing_zone_link/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/south_east = locate(origin.x + 3, origin.y, origin.z)
	var/turf/north_west = locate(origin.x, origin.y + 3, origin.z)
	var/turf/north_east = locate(origin.x + 3, origin.y + 3, origin.z)
	var/turf/console_turf = locate(origin.x + 1, origin.y + 1, origin.z)
	if(isnull(south_east) || isnull(north_west) || isnull(north_east) || isnull(console_turf))
		TEST_FAIL("Test room is too small to place a 4x4 landing zone rectangle.")
		return

	var/obj/machinery/computer/landing_controller/console = allocate(/obj/machinery/computer/landing_controller, console_turf)
	console.admin_force_operational = TRUE
	console.zone_label = "Test Hangar"
	console.exit_direction = EAST
	allocate(/obj/machinery/landing_corner, origin)
	allocate(/obj/machinery/landing_corner, south_east)
	allocate(/obj/machinery/landing_corner, north_west)
	allocate(/obj/machinery/landing_corner, north_east)

	var/list/link_vars = list("link_id" = "unit_test_lz")
	var/obj/effect/mapping_helpers/landing_zone/link/leader = allocate(/obj/effect/mapping_helpers/landing_zone/link, console_turf, console, link_vars)
	allocate(/obj/effect/mapping_helpers/landing_zone/link, origin, console, link_vars)
	allocate(/obj/effect/mapping_helpers/landing_zone/link, south_east, console, link_vars)
	allocate(/obj/effect/mapping_helpers/landing_zone/link, north_west, console, link_vars)
	allocate(/obj/effect/mapping_helpers/landing_zone/link, north_east, console, link_vars)

	var/obj/effect/mapping_helpers/landing_zone/affiliation/ds2/faction_helper = allocate(/obj/effect/mapping_helpers/landing_zone/affiliation/ds2, console_turf, console)

	TEST_ASSERT(QDELETED(faction_helper), "Landing zone affiliation helper should qdel after applying.")
	TEST_ASSERT_EQUAL(console.dock_affiliation, OVERMAP_AFFILIATION_DS2, "DS2 helper should lock the controller.")
	TEST_ASSERT_EQUAL(length(console.corners), 4, "Link helpers should attach all four corners.")
	TEST_ASSERT(!QDELETED(console.active_zone), "Linked corners should create a managed landing zone.")
	TEST_ASSERT_EQUAL(console.active_zone.zone_width, 4, "Zone width should match the corner rectangle.")
	TEST_ASSERT_EQUAL(console.active_zone.zone_height, 4, "Zone height should match the corner rectangle.")
	TEST_ASSERT_EQUAL(console.active_zone.exit_direction, EAST, "Managed zone should inherit controller exit direction.")
	TEST_ASSERT_EQUAL(console.active_zone.dock_affiliation, OVERMAP_AFFILIATION_DS2, "Managed zone should inherit DS2 lock.")
	TEST_ASSERT_EQUAL(console.active_zone.zone_name, "Test Hangar", "Managed zone should inherit the controller label.")
	TEST_ASSERT(QDELETED(leader), "Link helpers should qdel after resolving.")
