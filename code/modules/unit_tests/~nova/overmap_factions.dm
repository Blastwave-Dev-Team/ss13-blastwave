// MODULE ID: OVERMAP
// Faction registry completeness and ID-rule resolution.

/datum/unit_test/overmap_faction_registry

/datum/unit_test/overmap_faction_registry/Run()
	init_overmap_faction_globals()

	for(var/faction_id in list(OVERMAP_AFFILIATION_NT, OVERMAP_AFFILIATION_DS2, OVERMAP_AFFILIATION_NEUTRAL))
		var/datum/overmap_faction/faction = GLOB.overmap_factions_by_id[faction_id]
		TEST_ASSERT(!isnull(faction), "Faction id [faction_id] must be registered in GLOB.overmap_factions_by_id.")
		TEST_ASSERT_EQUAL(faction.id, faction_id, "Registered faction datum id must match lookup key.")

	TEST_ASSERT(length(GLOB.overmap_faction_id_rules) >= 6, "Expected the full ordered ID rule set.")

	var/list/ui_options = get_overmap_faction_ui_options()
	TEST_ASSERT_EQUAL(length(ui_options), length(GLOB.overmap_factions), "UI options should list every registered faction.")

/datum/unit_test/overmap_faction_id_rules

/datum/unit_test/overmap_faction_id_rules/Run()
	init_overmap_faction_globals()
	var/turf/stage = run_loc_floor_bottom_left

	var/obj/item/card/id/advanced/job_card = allocate(/obj/item/card/id/advanced, stage)
	SSid_access.apply_trim_to_card(job_card, /datum/id_trim/job/assistant)
	TEST_ASSERT_EQUAL(get_id_overmap_faction(job_card), OVERMAP_AFFILIATION_NT, "Station job trim should resolve to NT.")

	var/obj/item/card/id/advanced/ds2_card = allocate(/obj/item/card/id/advanced, stage)
	SSid_access.apply_trim_to_card(ds2_card, /datum/id_trim/syndicom/nova/ds2/syndicatestaff)
	TEST_ASSERT_EQUAL(get_id_overmap_faction(ds2_card), OVERMAP_AFFILIATION_DS2, "DS2 trim/access should resolve to DS2.")

	var/obj/item/card/id/advanced/tarkon = allocate(/obj/item/card/id/advanced/tarkon, stage)
	TEST_ASSERT_EQUAL(get_id_overmap_faction(tarkon), null, "Tarkon IDs should stay open.")

	var/obj/item/card/id/advanced/interdyne = allocate(/obj/item/card/id/advanced, stage)
	SSid_access.apply_trim_to_card(interdyne, /datum/id_trim/syndicom/nova/interdyne/deckofficer)
	TEST_ASSERT_EQUAL(get_id_overmap_faction(interdyne), null, "Interdyne IDs should stay open even with syndicate access.")

	var/obj/item/card/id/advanced/blank = allocate(/obj/item/card/id/advanced, stage)
	TEST_ASSERT_EQUAL(get_id_overmap_faction(blank), null, "Blank IDs should stay open.")

/datum/unit_test/overmap_faction_apply

/datum/unit_test/overmap_faction_apply/Run()
	init_overmap_faction_globals()
	var/turf/stage = run_loc_floor_bottom_left
	var/area/hull_area = get_area(stage)
	var/obj/docking_port/mobile/port = allocate(/obj/docking_port/mobile, stage, list(hull_area))
	var/obj/structure/overmap/ship/simulated/ship = allocate(/obj/structure/overmap/ship/simulated, stage, port.shuttle_id, port)
	port.current_ship = ship

	TEST_ASSERT(SSovermap.apply_ship_affiliation(ship, OVERMAP_AFFILIATION_NT), "Applying NT affiliation should succeed.")
	TEST_ASSERT_EQUAL(ship.home_level_id, MAIN_OVERMAP_OBJECT_ID, "NT faction should set main home_level_id.")
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_NT, "Ship should resolve as NT.")

	TEST_ASSERT(SSovermap.apply_ship_affiliation(ship, OVERMAP_AFFILIATION_DS2), "Applying DS2 affiliation should succeed.")
	TEST_ASSERT_EQUAL(ship.home_level_id, DES_TWO_OVERMAP_OBJECT_ID, "DS2 faction should set des_two home_level_id.")
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_DS2, "Ship should resolve as DS2.")

	TEST_ASSERT(SSovermap.apply_ship_affiliation(ship, OVERMAP_AFFILIATION_NEUTRAL), "Applying neutral affiliation should succeed.")
	TEST_ASSERT_EQUAL(ship.home_level_id, null, "Neutral faction should clear home_level_id.")
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_NEUTRAL, "Ship should resolve as neutral.")

	TEST_ASSERT(!SSovermap.apply_ship_affiliation(ship, "not_a_faction"), "Unknown faction ids should be rejected.")
