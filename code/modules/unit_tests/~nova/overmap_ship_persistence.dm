// MODULE ID: OVERMAP
// Persistent ships, end to end and without a database: the hull walk and its
// export, the load path, and the registrar console that charges for both.
//
// Every assertion below is one physical line, however long that leaves it. A
// macro call cannot be wrapped and still suit both parsers: DM continues a call
// across lines only when the line ends in a comma, and StrongDMM reads that
// comma as an extra empty argument and refuses to open the environment at all.
// Where a message needs to name the value it is judging, the value goes in a
// local first - which also stops the check and the message disagreeing.

/datum/unit_test/overmap_ship_persistence
	abstract_type = /datum/unit_test/overmap_ship_persistence
	priority = TEST_LONGER
	/// Where the landing zone lives, and with it the fixture hull at both ends.
	var/datum/turf_reservation/pad_reservation
	/// Every hull a case stood up, so that a failure part way still cleans up.
	var/list/obj/docking_port/mobile/hulls = list()
	/// Loose files a case wrote outside any owner's directory.
	var/list/written_files = list()
	/// Characters whose ship directories a case wrote into.
	var/list/owner_uuids = list()

/datum/unit_test/overmap_ship_persistence/Destroy()
	for(var/file_path in written_files)
		fdel(file(file_path))
	for(var/owner_uuid in owner_uuids)
		var/owner_key = sanitize_filename("[owner_uuid]")
		fdel("data/player_ships/[copytext(owner_key, 1, 2)]/[owner_key]/")
	// Hand the hull turfs back to the areas they came from before releasing the
	// reservation. Dropping a port on its own leaves its turfs owned by a
	// shuttle area that nothing holds open any more.
	for(var/obj/docking_port/mobile/hull as anything in hulls)
		if(!QDELETED(hull))
			hull.jumpToNullSpace()
	hulls.Cut()
	QDEL_NULL(pad_reservation)
	return ..()

/**
 * A landing zone somewhere nothing else is standing.
 *
 * The reservation keeps this off real station geometry, and its turfs are plain
 * space, which is one of the few types `dock_footprint_is_clear()` accepts. The
 * overmap level makes both ends resolve to somewhere: a ship only reads as
 * docked rather than in flight on a Z that some overmap object owns.
 */
/datum/unit_test/overmap_ship_persistence/proc/stage_landing_zone(zone_width, zone_height, reserve = 9)
	// Reserved generously and independently of the zone, so that a case which
	// widens the zone afterwards is still working inside turfs it owns.
	pad_reservation = SSmapping.request_turf_block_reservation(reserve, reserve, 1)
	TEST_ASSERT(pad_reservation, "The landing pad should reserve an isolated turf block.")
	var/turf/pad_corner = pad_reservation.bottom_left_turfs[1]
	TEST_ASSERT(pad_corner, "The pad reservation should provide a corner turf.")
	allocate(/obj/structure/overmap/level, pad_corner, "ship_persistence_level_[REF(src)]", list(pad_corner.z))
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, pad_corner)
	zone.zone_name = "Persistence Test Pad"
	zone.zone_width = zone_width
	zone.zone_height = zone_height
	zone.dock_affiliation = null
	return zone

/**
 * A three by three hull inside `zone`, owned by `owner_uuid`, with a chair and a
 * lockbox holding one stack of iron.
 *
 * Built inside the landing zone because that is where a printed hull is filed
 * from in practice, and because a hull standing on a Z no overmap object owns
 * binds to a ship that reads as in flight - which filing quite rightly refuses.
 */
/datum/unit_test/overmap_ship_persistence/proc/build_fixture_hull(obj/effect/landmark/overmap_landing_zone/zone, hull_name, owner_uuid)
	var/origin_x = zone.x + 2
	var/origin_y = zone.y + 2
	var/origin_z = zone.z
	var/list/hull_turfs = list()
	for(var/offset_x in 0 to 2)
		for(var/offset_y in 0 to 2)
			// Coordinates rather than the turf itself: ChangeTurf leaves the
			// reference it was called on pointing at a turf that is gone.
			var/turf/tile = locate(origin_x + offset_x, origin_y + offset_y, origin_z)
			hull_turfs += tile.ChangeTurf(/turf/open/floor/plating)
	var/obj/docking_port/mobile/hull = create_shuttle(null, hull_turfs[1], hull_turfs, list(), NORTH, NORTH, area_type = /area/shuttle/custom, name = hull_name, id = "persistence_test_[length(hulls)]_[REF(src)]")
	TEST_ASSERT(hull, "The fixture hull should register as a shuttle.")
	hulls += hull
	hull.ship_ownership = SHIP_OWNERSHIP_PERSONAL
	hull.ship_owner_id = owner_uuid

	var/obj/structure/chair/comfy/shuttle/chair = allocate(/obj/structure/chair/comfy/shuttle, locate(origin_x + 1, origin_y, origin_z))
	chair.setDir(EAST)
	var/obj/structure/closet/secure_closet/ship_lockbox/lockbox = allocate(/obj/structure/closet/secure_closet/ship_lockbox, locate(origin_x, origin_y + 2, origin_z))
	allocate(/obj/item/stack/sheet/iron, lockbox)
	return hull

/// A character with a ledger balance and a registrar session open for them.
/datum/unit_test/overmap_ship_persistence/proc/logged_in_console(owner_uuid, balance)
	owner_uuids += owner_uuid
	if(balance)
		var/datum/character_ledger_result/seed = SScharacter_ledger.try_credit(owner_uuid, balance, LEDGER_CHANNEL_ADMIN_SEED, "ship persistence test seed", "test:ships:seed:[owner_uuid]")
		TEST_ASSERT(seed.success, "Seeding the test ledger should succeed, got '[seed.status]'.")
	var/obj/machinery/computer/ship_registrar/console = allocate(/obj/machinery/computer/ship_registrar)
	console.authenticated = TRUE
	console.operator_uuid = owner_uuid
	console.operator_ckey = "shippersistencetest"
	console.refresh_session()
	return console

/// The registrar's last message, for a failure to quote.
/datum/unit_test/overmap_ship_persistence/proc/console_says(obj/machinery/computer/ship_registrar/console)
	return console.status_message ? console.status_message["text"] : "nothing"

/// The single ship a character owns, or null.
/datum/unit_test/overmap_ship_persistence/proc/only_record(owner_uuid)
	var/list/records = GLOB.ship_registry.list_for_owner(owner_uuid)
	return length(records) == 1 ? records[1] : null

/// What the walk found on one tile, for a failure message to point at.
/datum/unit_test/overmap_ship_persistence/proc/describe_cell(datum/ship_teardown/teardown, rel_x, rel_y)
	var/list/cell = teardown.cells["[rel_x],[rel_y]"]
	if(!cell)
		return "no cell at all"
	var/list/described = list("[cell["turf_path"]]")
	for(var/list/member as anything in cell["objects"])
		described += "[member["path"]]"
	return jointext(described, " + ")

/// Every object path a teardown accounted for, sorted, as a comparable signature.
/datum/unit_test/overmap_ship_persistence/proc/object_signature(datum/ship_teardown/teardown)
	var/list/paths = list()
	for(var/cell_key in teardown.cells)
		var/list/cell = teardown.cells[cell_key]
		for(var/list/member as anything in cell["objects"])
			paths += "[member["path"]]"
	return jointext(sort_list(paths), ", ")

/// Operation to count for everything a manifest would build, commissioning aside:
/// commissioning is registration, which a saved hull by design does not carry.
/datum/unit_test/overmap_ship_persistence/proc/operation_counts(datum/ship_plan/plan)
	var/list/counts = list()
	for(var/datum/ship_plan_op/operation as anything in plan.manifest)
		if(operation.op_type == SHIPYARD_OP_COMMISSION)
			continue
		var/signature = "[operation.op_type] [operation.target_path] at [operation.rel_x],[operation.rel_y]"
		counts[signature] = (counts[signature] || 0) + 1
	return counts

/// Signatures present a different number of times in `left` than in `right`.
/datum/unit_test/overmap_ship_persistence/proc/count_differences(list/left, list/right)
	var/list/differences = list()
	for(var/signature in left | right)
		var/left_count = left[signature] || 0
		var/right_count = right[signature] || 0
		if(left_count != right_count)
			differences += "[signature] ([left_count] vs [right_count])"
	return differences

// --- Serialization ----------------------------------------------------------

/**
 * A hull walked back into a map has to describe the ship that was standing.
 *
 * Byte equality against a source blueprint is not the property: a printed hull
 * filters its variables through what the printer can read back, and orders its
 * key dictionary by where things ended up. What has to hold is that the
 * manifest parsed back out builds the same ship, and that the export is a
 * fixed point - a generation that drifts drifts every time the ship is filed.
 */
/datum/unit_test/overmap_ship_persistence/roundtrip

/datum/unit_test/overmap_ship_persistence/roundtrip/Run()
	pad_reservation = SSmapping.request_turf_block_reservation(5, 5, 1, reservation_type = /datum/turf_reservation/transit)
	TEST_ASSERT(pad_reservation, "Round-trip test should reserve an isolated turf block.")
	var/turf/origin = pad_reservation.bottom_left_turfs[1]
	var/origin_x = origin.x
	var/origin_y = origin.y
	var/origin_z = origin.z

	var/list/hull_turfs = list()
	for(var/offset_x in 0 to 2)
		for(var/offset_y in 0 to 2)
			var/turf/tile = locate(origin_x + offset_x, origin_y + offset_y, origin_z)
			hull_turfs += tile.ChangeTurf(/turf/open/floor/plating)
	var/obj/docking_port/mobile/hull = create_shuttle(null, hull_turfs[1], hull_turfs, list(), NORTH, NORTH, area_type = /area/shuttle/custom, name = "Roundtrip Test Hull", id = "roundtrip_test_[REF(src)]")
	TEST_ASSERT(hull, "The fixture hull should register as a shuttle.")
	hulls += hull

	// One of each thing the walk has to recognise: a deck laid over the hull, an
	// object carrying a mapped variable, a marking that exists only as an
	// appearance on its turf, an upgraded machine, and the one container whose
	// contents come back.
	var/turf/deck_tile = locate(origin_x + 1, origin_y + 1, origin_z)
	deck_tile.place_on_top(/turf/open/floor/mineral/titanium/tiled, flags = CHANGETURF_INHERIT_AIR)
	var/obj/structure/chair/comfy/shuttle/chair = allocate(/obj/structure/chair/comfy/shuttle, locate(origin_x + 1, origin_y, origin_z))
	chair.setDir(EAST)
	new /obj/effect/turf_decal/stripes/line(locate(origin_x + 2, origin_y, origin_z))
	var/obj/machinery/microwave/oven = allocate(/obj/machinery/microwave, locate(origin_x + 2, origin_y + 2, origin_z))
	var/upgraded_bin = FALSE
	for(var/index in 1 to length(oven.component_parts))
		if(!istype(oven.component_parts[index], /datum/stock_part/matter_bin))
			continue
		oven.component_parts[index] = GLOB.stock_part_datums[/datum/stock_part/matter_bin/tier2]
		upgraded_bin = TRUE
	TEST_ASSERT(upgraded_bin, "The fixture machine should have a matter bin to upgrade.")
	oven.RefreshParts()
	var/turf/lockbox_tile = locate(origin_x, origin_y + 2, origin_z)
	var/obj/structure/closet/secure_closet/ship_lockbox/lockbox = allocate(/obj/structure/closet/secure_closet/ship_lockbox, lockbox_tile)
	allocate(/obj/item/stack/sheet/iron, lockbox)
	TEST_ASSERT(lockbox_tile in hull.return_turfs(), "The fixture lockbox should stand on a tile the hull owns.")

	var/datum/ship_teardown/teardown = new(hull)
	TEST_ASSERT(!teardown.refusal, "Teardown should accept a registered hull, got '[teardown.refusal]'.")
	TEST_ASSERT_EQUAL(length(teardown.cells), 9, "Teardown should describe every tile of the fixture hull.")
	TEST_ASSERT_EQUAL(length(teardown.stored_contents), 1, "A lockbox's contents are the only payload a teardown keeps. Its tile described [describe_cell(teardown, 1, 3)].")
	TEST_ASSERT(!length(teardown.lost_detail), "Teardown reported lost detail: [jointext(teardown.lost_detail, "; ")]")
	var/list/lockbox_fate = teardown.tile_fates["1,3"]
	TEST_ASSERT_EQUAL(lockbox_fate?["fate"], SHIPYARD_TILE_LOCKBOX, "The survey footprint should mark the lockbox tile as kept by the lockbox.")

	// A decal is recovered by appearance, and appearances are not unique to a
	// path - several decal types draw exactly the same thing. What has to come
	// back is the marking, not the name the mapper reached for.
	var/list/paint_cell = teardown.cells["3,1"]
	var/list/paint_member = length(paint_cell?["objects"]) ? paint_cell["objects"][1] : null
	var/obj/effect/turf_decal/painted = paint_member?["path"]
	var/obj/effect/turf_decal/stripes/line/as_painted = /obj/effect/turf_decal/stripes/line
	TEST_ASSERT(ispath(painted, /obj/effect/turf_decal), "The walk should resolve the deck marking back to a decal path, but its tile described [describe_cell(teardown, 3, 1)].")
	TEST_ASSERT_EQUAL(initial(painted.icon_state), initial(as_painted.icon_state), "The recovered decal should draw what was painted.")

	var/first_export = teardown.write_ship_tgm()
	TEST_ASSERT(first_export, "A hull that tore down cleanly should render to TGM.")
	TEST_ASSERT(findtext(first_export, "[/obj/structure/chair/comfy/shuttle]"), "The export should name the chair the walk found, but its tile described [describe_cell(teardown, 2, 1)].")
	TEST_ASSERT(findtext(first_export, "[/obj/structure/closet/secure_closet/ship_lockbox]"), "The export should keep the lockbox itself, not just its contents.")
	// Part tiers are objects, and a map holds constants, so an upgraded
	// assembly only survives as a helper carrying what it was closed around.
	TEST_ASSERT(findtext(first_export, "[/datum/stock_part/matter_bin/tier2]"), "The export should record the tier of an upgraded machine's parts, but its tile described [describe_cell(teardown, 3, 3)].")

	var/export_path = "data/unit_test_ship_roundtrip_[REF(src)].dmm"
	written_files += export_path
	TEST_ASSERT(shipyard_write_ship_file(first_export, export_path), "The rendered ship should write to disk.")
	var/datum/parsed_map/parsed = new(file(export_path))
	TEST_ASSERT(parsed?.bounds, "An exported ship should parse as a map.")
	var/datum/ship_teardown/reparsed = shipyard_teardown_from_parsed(parsed)
	TEST_ASSERT(!reparsed.refusal, "A saved ship should read back into cells, got '[reparsed.refusal]'.")
	TEST_ASSERT_EQUAL(reparsed.write_ship_tgm(), first_export, "Re-exporting a saved ship should be a fixed point.")

	// The point of the whole exercise: what came back has to be buildable.
	var/datum/map_template/shuttle/runtime/template = new(export_path)
	TEST_ASSERT_EQUAL(template.mappath, export_path, "A runtime template should keep the path it was handed.")
	var/datum/ship_plan/template/plan = new(template)
	var/plating_operations = 0
	var/list/found = list()
	for(var/datum/ship_plan_op/operation as anything in plan.manifest)
		switch(operation.op_type)
			if(SHIPYARD_OP_PLATING)
				plating_operations++
			if(SHIPYARD_OP_TURF)
				if(ispath(operation.target_path, /turf/open/floor/mineral/titanium/tiled))
					found["the titanium deck"] = TRUE
			if(SHIPYARD_OP_DECAL)
				if(operation.target_path == painted)
					found["the deck marking"] = TRUE
			if(SHIPYARD_OP_MACHINE)
				if(ispath(operation.target_path, /obj/machinery/microwave))
					found["the machine"] = TRUE
			if(SHIPYARD_OP_GENERATED)
				if(ispath(operation.target_path, /obj/structure/chair/comfy/shuttle))
					found["the chair"] = TRUE
					TEST_ASSERT_EQUAL(operation.desired_vars["dir"], EAST, "A saved chair should come back facing the way it was parked.")
				else if(ispath(operation.target_path, /obj/structure/closet/secure_closet/ship_lockbox))
					found["the lockbox"] = TRUE
	TEST_ASSERT_EQUAL(plating_operations, 9, "Every saved tile should be plated again on the way back in.")
	var/list/missing = list("the titanium deck", "the deck marking", "the machine", "the chair", "the lockbox") - found
	if(length(missing))
		TEST_FAIL("A saved ship's manifest omitted [jointext(missing, ", ")]. Skipped entries: [jointext(plan.skipped_report(TRUE), "; ")]")
	TEST_ASSERT(shipyard_salvage_estimate(export_path) > 0, "A saved hull should be worth something as salvage.")
	qdel(plan)
	qdel(template)
	qdel(reparsed)
	qdel(teardown)

/**
 * A stock blueprint, stood up and walked back out, has to describe the same
 * ship its own blueprint does.
 *
 * This is the case a hand-built fixture cannot cover: a mapper's hull, with its
 * spawners, helpers and areas, going through the whole loop. Commissioning is
 * left out because it is registration, which a saved hull does not carry.
 */
/datum/unit_test/overmap_ship_persistence/blueprint_parity

/datum/unit_test/overmap_ship_persistence/blueprint_parity/Run()
	var/datum/map_template/shuttle/source_template = new /datum/map_template/shuttle/overmap/frigate/nt_personal()
	var/datum/ship_plan/template/source_plan = new(source_template)
	var/datum/shipyard_staging/staging = new()
	var/obj/docking_port/mobile/staged = shipyard_stage_hull(source_template, staging)
	TEST_ASSERT(staged, "The stock blueprint should stage into a reservation of its own.")
	hulls += staged

	var/datum/ship_teardown/teardown = new(staged)
	TEST_ASSERT(!teardown.refusal, "A staged stock hull should tear down, got '[teardown.refusal]'.")
	var/export_path = "data/unit_test_ship_parity_[REF(src)].dmm"
	written_files += export_path
	TEST_ASSERT(shipyard_write_ship_file(teardown.write_ship_tgm(), export_path), "The stock hull should export to disk.")
	var/datum/map_template/shuttle/runtime/exported_template = new(export_path)
	var/datum/ship_plan/template/exported_plan = new(exported_template)

	TEST_ASSERT_EQUAL(exported_plan.width, source_plan.width, "An exported stock hull should crop to the width of its blueprint.")
	TEST_ASSERT_EQUAL(exported_plan.height, source_plan.height, "An exported stock hull should crop to the height of its blueprint.")
	var/list/differences = count_differences(operation_counts(source_plan), operation_counts(exported_plan))
	TEST_ASSERT(!length(differences), "An exported stock hull should build what its blueprint builds (blueprint vs export): [jointext(differences, "; ")]")

	staging.abandon()
	hulls -= staged
	qdel(exported_plan)
	qdel(exported_template)
	qdel(teardown)
	qdel(source_plan)
	qdel(source_template)

// --- Registrar --------------------------------------------------------------

/**
 * File a hull, retrieve it insured, and file it again, with every fee landing
 * where it should.
 *
 * The retrieval is priced so its insurance outgrows the next storage fee, which
 * is the case where the surplus has to come back to the owner rather than
 * vanish into the storage charge.
 */
/datum/unit_test/overmap_ship_persistence/registrar

/datum/unit_test/overmap_ship_persistence/registrar/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Registrar Test Hull", owner_uuid)

	TEST_ASSERT(console.run_survey(hull, zone), "Surveying an owned, idle hull should succeed: [console_says(console)]")
	var/list/first_quote = console.survey["quote"]
	var/storage_fee = first_quote["net"]
	TEST_ASSERT(storage_fee > 0, "Filing a hull should cost something.")
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	TEST_ASSERT(console.file_hull(hull, zone, null), "Filing a surveyed hull should succeed: [console_says(console)]")
	TEST_ASSERT(QDELETED(hull), "A filed hull should leave the world.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - storage_fee, "Filing should charge exactly the storage fee the survey quoted.")

	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT(record, "Filing should leave exactly one record in the owner's garage.")
	TEST_ASSERT_EQUAL(record.status, SHIP_STATUS_FILED, "A freshly filed ship should be in storage.")
	TEST_ASSERT_EQUAL(record.revision, 1, "A first filing should be revision 1.")
	TEST_ASSERT(fexists(record.map_path), "A filed ship's revision should exist on disk at [record.map_path].")
	TEST_ASSERT(record.map_checksum, "A filed ship's revision should carry a checksum.")
	TEST_ASSERT_EQUAL(length(record.stored_contents), 1, "The lockbox roster should follow the ship into the registry.")

	// Priced so the insurance refund is certain to exceed the next storage fee.
	var/datum/player_ship_record/row = GLOB.ship_registry.memory_rows["[record.id]"]
	row.salvage_estimate = 10000
	var/insured_fee = shipyard_insurance_fee(10000)
	balance_before = SScharacter_ledger.get_balance(owner_uuid)
	var/obj/docking_port/mobile/retrieved = console.retrieve_record(record.id, TRUE, zone, null)
	TEST_ASSERT(retrieved, "An insured retrieval onto a clear pad should succeed: [console_says(console)]")
	hulls += retrieved
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - insured_fee, "An insured retrieval should charge the insurance fee.")
	TEST_ASSERT(retrieved in SSshuttle.mobile_docking_ports, "A retrieved hull should be a registered mobile port.")
	TEST_ASSERT(length(retrieved.shuttle_areas), "A retrieved hull should own shuttle areas.")
	TEST_ASSERT_EQUAL(retrieved.ship_registry_id, record.id, "A retrieved hull should remember the record it came from.")
	TEST_ASSERT_EQUAL(retrieved.ship_ownership, SHIP_OWNERSHIP_PERSONAL, "A retrieved hull should belong to its owner.")
	TEST_ASSERT_EQUAL(retrieved.ship_owner_id, owner_uuid, "A retrieved hull should belong to the character who retrieved it.")
	var/obj/structure/overmap/ship/simulated/ship = retrieved.current_ship
	TEST_ASSERT_EQUAL(ship?.state, OVERMAP_SHIP_IDLE, "A retrieved hull should read as docked rather than in flight.")
	var/list/landed = retrieved.return_coords()
	var/landed_inside = zone.contains_bbox(min(landed[1], landed[3]), min(landed[2], landed[4]), max(landed[1], landed[3]), max(landed[2], landed[4]), retrieved.z)
	TEST_ASSERT(landed_inside, "A retrieved hull should come down entirely inside its zone.")

	record = GLOB.ship_registry.get_record(record.id, owner_uuid)
	TEST_ASSERT_EQUAL(record.status, SHIP_STATUS_CHECKED_OUT, "A retrieved ship should be checked out.")
	TEST_ASSERT(record.insured, "An insured retrieval should leave the checkout insured.")
	TEST_ASSERT_EQUAL(record.insurance_fee_paid, insured_fee, "The checkout should remember what its insurance cost.")

	TEST_ASSERT(console.run_survey(retrieved, zone), "A retrieved hull should survey again: [console_says(console)]")
	var/list/second_quote = console.survey["quote"]
	TEST_ASSERT_EQUAL(second_quote["insuranceRefund"], insured_fee, "Refiling an insured checkout should quote its insurance back.")
	var/net = second_quote["net"]
	TEST_ASSERT(net < 0, "Insurance this large should outgrow the storage fee, netting [net].")
	balance_before = SScharacter_ledger.get_balance(owner_uuid)
	TEST_ASSERT(console.file_hull(retrieved, zone, null), "Refiling a retrieved hull should succeed: [console_says(console)]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - net, "The insurance surplus over storage should be credited back.")

	record = only_record(owner_uuid)
	TEST_ASSERT(record, "Refiling should update the same record rather than add one.")
	TEST_ASSERT_EQUAL(record.revision, 2, "Refiling should write the next revision.")
	TEST_ASSERT_EQUAL(record.status, SHIP_STATUS_FILED, "A refiled ship should be back in storage.")
	TEST_ASSERT(!record.insured, "Refiling should spend the checkout's insurance.")

/**
 * Only its owner can file a personal hull, and nobody can file anything else.
 *
 * A refusal has to leave the hull where it stands and the ledger untouched,
 * since filing ends by deleting everything aboard.
 */
/datum/unit_test/overmap_ship_persistence/refusals

/datum/unit_test/overmap_ship_persistence/refusals/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Refusal Test Hull", owner_uuid)
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)

	var/list/cases = list(
		SHIPYARD_REFUSAL_STATION_HULL = list(SHIP_OWNERSHIP_STATION, null),
		SHIPYARD_REFUSAL_DEPARTMENT_HULL = list(SHIP_OWNERSHIP_DEPARTMENT, null),
		SHIPYARD_REFUSAL_OTHER_OWNER = list(SHIP_OWNERSHIP_PERSONAL, generate_character_uuid()),
	)
	for(var/expected_code in cases)
		var/list/stamp = cases[expected_code]
		hull.ship_ownership = stamp[1]
		hull.ship_owner_id = stamp[2]
		var/list/refusal = shipyard_file_refusal(hull, zone, owner_uuid)
		TEST_ASSERT_EQUAL(refusal?["code"], expected_code, "A [stamp[1]] hull should be refused as [expected_code].")
		TEST_ASSERT(!console.run_survey(hull, zone), "A [expected_code] hull should not survey.")
		// Forced past the survey gate, so it is the refusal itself being tested.
		console.surveyed_hull = WEAKREF(hull)
		TEST_ASSERT(!console.file_hull(hull, zone, null), "A [expected_code] hull should not file.")
		TEST_ASSERT_EQUAL(console_says(console), refusal["text"], "Filing a [expected_code] hull should explain why.")
		TEST_ASSERT(!QDELETED(hull), "A refused hull should still be standing.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before, "A refused filing should charge nothing.")
	TEST_ASSERT(!length(GLOB.ship_registry.list_for_owner(owner_uuid)), "A refused filing should leave no record behind.")

/**
 * A checkout an earlier round never filed back is settled on the next read.
 *
 * Insurance pays for the last filed revision to come back; without it the ship
 * is gone. Settled lazily so a server crash cannot skip it.
 */
/datum/unit_test/overmap_ship_persistence/lazy_resolution

/datum/unit_test/overmap_ship_persistence/lazy_resolution/Run()
	var/owner_uuid = generate_character_uuid()
	var/insured_id = GLOB.ship_registry.insert_record(owner_uuid, "shippersistencetest", "Insured Hull")
	var/uninsured_id = GLOB.ship_registry.insert_record(owner_uuid, "shippersistencetest", "Uninsured Hull")
	for(var/record_id in list(insured_id, uninsured_id))
		TEST_ASSERT(GLOB.ship_registry.store_revision(record_id, 3, "data/unit_test_ship_[record_id].dmm", null, list(), 9, "Hull [record_id]", 1000), "Storing a revision should succeed.")
	GLOB.ship_registry.checkout(insured_id, TRUE, 1250)
	GLOB.ship_registry.checkout(uninsured_id, FALSE, 0)
	// Make both checkouts belong to a round that is over.
	var/current_round = shipyard_current_round_id()
	for(var/record_id in list(insured_id, uninsured_id))
		var/datum/player_ship_record/row = GLOB.ship_registry.memory_rows["[record_id]"]
		row.filed_round_id = current_round - 2
		row.retrieved_round_id = current_round - 1

	var/datum/player_ship_record/insured = GLOB.ship_registry.get_record(insured_id, owner_uuid)
	TEST_ASSERT_EQUAL(insured.status, SHIP_STATUS_FILED, "An insured ship never filed back should revert to storage.")
	TEST_ASSERT(!insured.insured, "Reverting should spend the insurance.")
	TEST_ASSERT_EQUAL(insured.revision, 3, "Reverting should restore the last filed revision.")
	TEST_ASSERT(insured.reverted_from_loss(), "A reverted ship should read as having come back from a loss.")
	var/datum/player_ship_record/uninsured = GLOB.ship_registry.get_record(uninsured_id, owner_uuid)
	TEST_ASSERT_EQUAL(uninsured.status, SHIP_STATUS_LOST, "An uninsured ship never filed back should be lost.")
	TEST_ASSERT(!uninsured.is_retrievable(), "A lost ship should not be retrievable.")
	// Settled in the store, not just in the copy that was read.
	var/datum/player_ship_record/stored = GLOB.ship_registry.memory_rows["[uninsured_id]"]
	TEST_ASSERT_EQUAL(stored.status, SHIP_STATUS_LOST, "The loss should be written back to the registry.")

/**
 * A retrieval that fails after charging hands the fee back, and a retrieval
 * repeated after success charges nothing.
 *
 * The retry after the refund is the real assertion: it has to be charged again,
 * which only works if the refund moved the idempotency key on.
 */
/datum/unit_test/overmap_ship_persistence/refund_and_idempotency

/datum/unit_test/overmap_ship_persistence/refund_and_idempotency/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Idempotency Test Hull", owner_uuid)
	TEST_ASSERT(console.run_survey(hull, zone), "The fixture hull should survey: [console_says(console)]")
	TEST_ASSERT(console.file_hull(hull, zone, null), "The fixture hull should file: [console_says(console)]")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT(record, "The fixture hull should be in the garage.")
	var/fee = shipyard_uninsured_fee()
	TEST_ASSERT(fee > 0, "The uninsured fee should be a real charge for this case to mean anything.")

	// Two by two cannot hold three by three, and the pad port is where that is
	// discovered - after the fee is taken and the hull is already staged.
	zone.zone_width = 2
	zone.zone_height = 2
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	var/registered_before = length(SSshuttle.mobile_docking_ports)
	TEST_ASSERT(isnull(console.retrieve_record(record.id, FALSE, zone, null)), "A hull too large for the zone should be refused.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before, "A refused retrieval should refund its fee.")
	TEST_ASSERT_EQUAL(length(SSshuttle.mobile_docking_ports), registered_before, "A refused retrieval should register nothing.")
	record = GLOB.ship_registry.get_record(record.id, owner_uuid)
	TEST_ASSERT_EQUAL(record.status, SHIP_STATUS_FILED, "A refused retrieval should leave the ship in storage.")

	zone.zone_width = 7
	zone.zone_height = 7
	var/obj/docking_port/mobile/retrieved = console.retrieve_record(record.id, FALSE, zone, null)
	TEST_ASSERT(retrieved, "The ship should retrieve once it has somewhere to go: [console_says(console)]")
	hulls += retrieved
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - fee, "A retry after a refund should be charged, once.")

	TEST_ASSERT(isnull(console.retrieve_record(record.id, FALSE, zone, null)), "A ship already deployed should not retrieve twice.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - fee, "A second click should charge nothing.")

	// And at the ledger itself: the same charge twice is one charge.
	balance_before = SScharacter_ledger.get_balance(owner_uuid)
	var/datum/character_ledger_result/first = shipyard_charge_fee(owner_uuid, 10, LEDGER_CHANNEL_SHIP_RETRIEVE, "idempotency probe", record.id, record.revision, "probe")
	var/datum/character_ledger_result/second = shipyard_charge_fee(owner_uuid, 10, LEDGER_CHANNEL_SHIP_RETRIEVE, "idempotency probe", record.id, record.revision, "probe")
	TEST_ASSERT(first.success && !first.duplicate, "The first charge should go through.")
	TEST_ASSERT(second.duplicate, "The same charge again should be recognised as a replay.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - 10, "A replayed charge should not be taken twice.")
