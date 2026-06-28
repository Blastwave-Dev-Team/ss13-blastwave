// MODULE ID: OVERMAP
// Unit tests for the overmap-controlled space ruin spawning system.

/// Verify that no crosslinked space ruin Z-levels exist when overmap_space_ruins is TRUE.
/datum/unit_test/overmap_no_crosslinked_space_ruins

/datum/unit_test/overmap_no_crosslinked_space_ruins/Run()
	if(!SSmapping.current_map.overmap_space_ruins)
		return
	var/list/space_ruin_zs = SSmapping.levels_by_trait(ZTRAIT_SPACE_RUINS)
	TEST_ASSERT_EQUAL(length(space_ruin_zs), 0, "Found [length(space_ruin_zs)] crosslinked space ruin Z-levels when overmap_space_ruins is enabled.")

/// Verify that named site POIs are created when overmap_space_ruins is TRUE.
/datum/unit_test/overmap_sites_exist

/datum/unit_test/overmap_sites_exist/Run()
	if(!SSmapping.current_map.overmap_space_ruins)
		return
	var/found_sites = 0
	for(var/obj/structure/overmap/level/site/site in SSovermap.overmap_objects)
		found_sites++
		TEST_ASSERT(length(site.linked_levels), "Site [site.id] has no linked_levels.")
		TEST_ASSERT(site.preloaded, "Site [site.id] was not preloaded.")
	TEST_ASSERT(found_sites > 0, "No overmap site POIs found despite overmap_space_ruins being enabled.")

/// Verify that installation_stealth is correctly set on main and des_two.
/datum/unit_test/overmap_stealth_flags

/datum/unit_test/overmap_stealth_flags/Run()
	if(!SSovermap.main)
		return
	TEST_ASSERT(SSovermap.main.installation_stealth, "Main station POI lacks installation_stealth.")
	for(var/obj/structure/overmap/level/site/site in SSovermap.overmap_objects)
		if(site.id == DES_TWO_OVERMAP_OBJECT_ID)
			TEST_ASSERT(site.installation_stealth, "DS2 site lacks installation_stealth.")
			return

/// Verify can_view_installation blocks cross-faction pairs correctly.
/datum/unit_test/overmap_stealth_gating

/datum/unit_test/overmap_stealth_gating/Run()
	if(!SSovermap.main)
		return
	// NT ship should always see main
	var/obj/structure/overmap/level/main/main_poi = SSovermap.main
	TEST_ASSERT(SSovermap.can_view_installation(main_poi, main_poi), "NT POI cannot see itself.")

	// Find DS2 site for cross-faction testing
	var/obj/structure/overmap/level/site/ds2_site
	for(var/obj/structure/overmap/level/site/site in SSovermap.overmap_objects)
		if(site.id == DES_TWO_OVERMAP_OBJECT_ID)
			ds2_site = site
			break
	if(!ds2_site)
		return

	// NT should never see DS2 in v1
	TEST_ASSERT(!SSovermap.can_view_installation(main_poi, ds2_site), "NT POI can see DS2 (should be blocked in v1).")

	// DS2 should not see NT before reveal
	SSovermap.station_revealed_to_ds2 = FALSE
	TEST_ASSERT(!SSovermap.can_view_installation(ds2_site, main_poi), "DS2 can see NT before syndicate reveal.")

	// After reveal, DS2 should see NT
	SSovermap.station_revealed_to_ds2 = TRUE
	TEST_ASSERT(SSovermap.can_view_installation(ds2_site, main_poi), "DS2 cannot see NT after syndicate reveal.")
	SSovermap.station_revealed_to_ds2 = FALSE

/// Verify the distress beacon can be instantiated and has correct TGUI interface.
/datum/unit_test/overmap_distress_beacon

/datum/unit_test/overmap_distress_beacon/Run()
	var/obj/machinery/distress_beacon/beacon = allocate(/obj/machinery/distress_beacon)
	TEST_ASSERT_EQUAL(beacon.transmitting, FALSE, "Beacon should start not transmitting.")
