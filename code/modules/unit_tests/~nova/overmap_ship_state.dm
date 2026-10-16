// MODULE ID: OVERMAP
// The runtime state a filed ship keeps: savers resolving by type, item state
// through the lockbox roster, fixture state, and what stays on the deck.
//
// Assertions stay on one physical line each, for the reason given at the top of
// overmap_ship_persistence.dm.

/// An item taken through the roster and the database encoding, and built again.
/datum/unit_test/overmap_ship_persistence/proc/ferry(obj/item/source)
	var/list/roster = shipyard_decode_roster(json_decode(json_encode(list(shipyard_roster_entry(source)))))
	TEST_ASSERT_EQUAL(length(roster), 1, "[source.type] should survive the roster encoding.")
	var/obj/item/restored = shipyard_restore_roster_entry(roster[1], run_loc_floor_top_right)
	TEST_ASSERT(restored, "[source.type] should build back from its roster entry.")
	allocated += restored
	return restored

/// A fixture's state captured, put through the database encoding, and applied to a fresh one.
/datum/unit_test/overmap_ship_persistence/proc/carry_state(atom/source, atom/target)
	var/list/state = shipyard_capture_state(source)
	TEST_ASSERT(islist(state), "[source.type] should have state to capture.")
	shipyard_apply_state(target, json_decode(json_encode(state)))

/datum/unit_test/overmap_ship_persistence/proc/written_paper(text, atom/destination)
	var/obj/item/paper/sheet = allocate(/obj/item/paper, destination)
	sheet.add_raw_text(text)
	return sheet

/datum/unit_test/overmap_ship_persistence/proc/paper_says(obj/item/paper/sheet, text)
	return istype(sheet) && findtext(sheet.get_raw_text(), text)

/// Savers resolve to the nearest registered ancestor, as routes do.
/datum/unit_test/overmap_ship_persistence/serdes_registry

/datum/unit_test/overmap_ship_persistence/serdes_registry/Run()
	var/registered = 0
	for(var/serdes_type in subtypesof(/datum/shipyard_serdes))
		var/datum/shipyard_serdes/serdes_path = serdes_type
		if(initial(serdes_path.target_type))
			registered++
	TEST_ASSERT_EQUAL(length(GLOB.shipyard_serdes), registered, "Every saver should own a distinct target type.")
	var/list/expected = list(
		/obj/item/paper/fluff = /datum/shipyard_serdes/item/paper,
		/obj/item/stock_parts/power_store/cell/high = /datum/shipyard_serdes/item/power_store,
		/obj/item/pen = /datum/shipyard_serdes/item,
		/obj/item/gun/ballistic/automatic/pistol = /datum/shipyard_serdes/item/ballistic_gun,
		/obj/machinery/portable_atmospherics/canister/plasma = /datum/shipyard_serdes/portable_atmospherics/canister,
		/obj/structure/reagent_dispensers/fueltank = /datum/shipyard_serdes/reagent_dispenser,
	)
	for(var/target_path in expected)
		var/datum/shipyard_serdes/found = get_shipyard_serdes(target_path)
		TEST_ASSERT_EQUAL(found?.type, expected[target_path], "[target_path] should resolve to its nearest saver.")
	TEST_ASSERT_NULL(get_shipyard_serdes(/obj/structure/chair), "A type with no saver above it should resolve to nothing.")
	TEST_ASSERT(shipyard_keeps_aboard(allocate(/obj/item/paper)), "Paper should stay aboard a filed ship.")
	TEST_ASSERT(!shipyard_keeps_aboard(allocate(/obj/item/pen)), "A loose pen should not stay aboard a filed ship.")

/// Paperwork keeps what is written on it, in the order it was kept.
/datum/unit_test/overmap_ship_persistence/paperwork_state

/datum/unit_test/overmap_ship_persistence/paperwork_state/Run()
	var/obj/item/paper/restored_paper = ferry(written_paper("Ship's log, day one", null))
	TEST_ASSERT(paper_says(restored_paper, "Ship's log, day one"), "A paper should keep its writing.")

	var/obj/item/folder/folder = allocate(/obj/item/folder)
	written_paper("Manifest", folder)
	var/obj/item/folder/restored_folder = ferry(folder)
	var/folder_count = length(restored_folder.contents)
	TEST_ASSERT_EQUAL(folder_count, 1, "A folder should hold what it held.")
	TEST_ASSERT(paper_says(locate(/obj/item/paper) in restored_folder, "Manifest"), "A folder's paper should keep its writing.")

	var/obj/item/clipboard/clipboard = allocate(/obj/item/clipboard)
	written_paper("Bottom sheet", clipboard)
	clipboard.top_paper = written_paper("Top sheet", clipboard)
	var/obj/item/clipboard/restored_clipboard = ferry(clipboard)
	var/list/restored_sheets = list()
	for(var/obj/item/paper/sheet in restored_clipboard)
		restored_sheets += sheet
	TEST_ASSERT_EQUAL(length(restored_sheets), 2, "A clipboard should hold both its papers.")
	TEST_ASSERT(paper_says(restored_clipboard.top_paper, "Top sheet"), "A clipboard should keep which paper is on top.")

	var/obj/item/paper_bin/bin = allocate(/obj/item/paper_bin)
	QDEL_LIST(bin.paper_stack)
	var/obj/item/paper/stacked = written_paper("Scrap", bin)
	bin.paper_stack += stacked
	bin.total_paper = 7
	var/obj/item/paper_bin/restored_bin = ferry(bin)
	TEST_ASSERT_EQUAL(restored_bin.total_paper, 7, "A paper bin should keep its count of sheets.")
	var/stack_count = length(restored_bin.paper_stack)
	TEST_ASSERT_EQUAL(stack_count, 1, "A paper bin should keep its written sheets.")
	TEST_ASSERT(paper_says(stack_count ? restored_bin.paper_stack[1] : null, "Scrap"), "A paper bin's written sheet should keep its writing.")

	var/obj/item/book/book = allocate(/obj/item/book)
	book.book_data.set_title("Logbook", trusted = TRUE)
	book.book_data.set_content("Departed at dawn.", trusted = TRUE)
	var/obj/item/book/restored_book = ferry(book)
	TEST_ASSERT_EQUAL(restored_book.book_data?.title, "Logbook", "A book should keep its title.")
	TEST_ASSERT_EQUAL(restored_book.book_data?.content, "Departed at dawn.", "A book should keep its content.")

	var/obj/item/photo/photo = allocate(/obj/item/photo)
	var/datum/picture/picture = new("Crew photo", "Everyone aboard.", image = icon('icons/obj/art/camera.dmi', "photo"), size_x = 1, size_y = 1)
	photo.set_picture(picture, TRUE, TRUE)
	var/obj/item/photo/restored_photo = ferry(photo)
	var/image_path = restored_photo.picture?.logpath
	if(image_path)
		written_files += image_path
	TEST_ASSERT(restored_photo.picture?.picture_image, "A photo should keep its picture.")
	TEST_ASSERT(findtext(image_path, "data/player_ships/photos/") == 1, "A photo's image should be kept with the ships, got [image_path].")
	TEST_ASSERT_EQUAL(restored_photo.name, photo.name, "A photo should keep its name.")

/// A lockbox is not a refill: charge, reagents, gas and rounds come back as they went in.
/datum/unit_test/overmap_ship_persistence/item_state

/datum/unit_test/overmap_ship_persistence/item_state/Run()
	var/obj/item/stock_parts/power_store/cell/high/cell = allocate(/obj/item/stock_parts/power_store/cell/high)
	cell.charge = cell.maxcharge / 2
	var/obj/item/stock_parts/power_store/cell/high/restored_cell = ferry(cell)
	TEST_ASSERT_EQUAL(restored_cell.charge, cell.maxcharge / 2, "A half-charged cell should come back half charged.")

	var/obj/item/gun/energy/laser/laser = allocate(/obj/item/gun/energy/laser)
	laser.cell.charge = 0
	var/obj/item/gun/energy/laser/restored_laser = ferry(laser)
	TEST_ASSERT_EQUAL(restored_laser.cell?.charge, 0, "A drained energy gun should come back drained.")

	var/obj/item/extinguisher/extinguisher = allocate(/obj/item/extinguisher)
	extinguisher.reagents.remove_all(extinguisher.reagents.total_volume / 2)
	var/expected_volume = extinguisher.reagents.total_volume
	var/obj/item/extinguisher/restored_extinguisher = ferry(extinguisher)
	TEST_ASSERT_EQUAL(restored_extinguisher.reagents.total_volume, expected_volume, "A half-empty extinguisher should come back half empty.")

	var/obj/item/reagent_containers/cup/beaker/beaker = allocate(/obj/item/reagent_containers/cup/beaker)
	beaker.reagents.add_reagent(/datum/reagent/water, 30, reagtemp = 350)
	var/obj/item/reagent_containers/cup/beaker/restored_beaker = ferry(beaker)
	TEST_ASSERT_EQUAL(restored_beaker.reagents.get_reagent_amount(/datum/reagent/water), 30, "A beaker should keep its reagents.")
	TEST_ASSERT_EQUAL(round(restored_beaker.reagents.chem_temp), 350, "A beaker should keep its temperature.")

	var/obj/item/tank/internals/oxygen/tank = allocate(/obj/item/tank/internals/oxygen)
	tank.air_contents.remove_ratio(0.5)
	var/expected_moles = tank.air_contents.total_moles()
	var/obj/item/tank/internals/oxygen/restored_tank = ferry(tank)
	var/restored_moles = restored_tank.air_contents.total_moles()
	TEST_ASSERT(abs(restored_moles - expected_moles) < 0.01, "A half-empty tank should come back half empty, holding [restored_moles] of [expected_moles] mol.")

	var/obj/item/ammo_box/magazine/m9mm/magazine = allocate(/obj/item/ammo_box/magazine/m9mm)
	for(var/i in 1 to 3)
		qdel(magazine.get_round())
	var/obj/item/ammo_box/magazine/m9mm/restored_magazine = ferry(magazine)
	TEST_ASSERT_EQUAL(restored_magazine.ammo_count(), magazine.ammo_count(), "A part-spent magazine should come back part spent.")

	var/obj/item/gun/ballistic/automatic/pistol/pistol = allocate(/obj/item/gun/ballistic/automatic/pistol)
	for(var/i in 1 to 2)
		qdel(pistol.magazine.get_round())
	var/obj/item/gun/ballistic/automatic/pistol/restored_pistol = ferry(pistol)
	TEST_ASSERT_EQUAL(restored_pistol.get_ammo(TRUE), pistol.get_ammo(TRUE), "A pistol should come back with the rounds it had, chamber included.")

	var/obj/item/gun/ballistic/revolver/revolver = allocate(/obj/item/gun/ballistic/revolver)
	qdel(revolver.magazine.get_round())
	var/obj/item/gun/ballistic/revolver/restored_revolver = ferry(revolver)
	TEST_ASSERT_EQUAL(restored_revolver.get_ammo(FALSE, FALSE), revolver.get_ammo(FALSE, FALSE), "A revolver should come back with the rounds it had.")

/// Fixtures keep their charge, gas and reagents, and a canister keeps the tank in it.
/datum/unit_test/overmap_ship_persistence/fixture_state

/datum/unit_test/overmap_ship_persistence/fixture_state/Run()
	var/obj/machinery/power/smes/smes = allocate(/obj/machinery/power/smes, run_loc_floor_bottom_left)
	var/obj/machinery/power/smes/other_smes = allocate(/obj/machinery/power/smes, run_loc_floor_top_right)
	var/list/smes_state = shipyard_capture_state(smes)
	var/capacity = 0
	for(var/obj/item/stock_parts/power_store/power_cell in smes.component_parts)
		capacity += power_cell.max_charge()
	TEST_ASSERT(capacity > 0, "The fixture SMES should be built with cells.")
	smes_state["charge"] = round(capacity / 3)
	smes_state["output_level"] = 0
	shipyard_apply_state(other_smes, json_decode(json_encode(smes_state)))
	var/list/carried_smes = shipyard_capture_state(other_smes)
	TEST_ASSERT_EQUAL(carried_smes["charge"], round(capacity / 3), "An SMES should keep its stored charge.")
	TEST_ASSERT_EQUAL(other_smes.output_level, 0, "An SMES should keep its output setting.")

	var/obj/machinery/power/apc/apc = allocate(/obj/machinery/power/apc, run_loc_floor_bottom_left)
	QDEL_NULL(apc.cell)
	apc.cell = allocate(/obj/item/stock_parts/power_store/battery/high, apc)
	var/half_charge = apc.cell.maxcharge / 2
	apc.cell.charge = half_charge
	var/list/apc_state = json_decode(json_encode(shipyard_capture_state(apc)))
	apc.cell.charge = apc.cell.maxcharge
	shipyard_apply_state(apc, apc_state)
	TEST_ASSERT_EQUAL(apc.cell.charge, half_charge, "An APC should keep its cell's charge.")

	var/obj/machinery/portable_atmospherics/canister/plasma/drained = allocate(/obj/machinery/portable_atmospherics/canister/plasma, run_loc_floor_bottom_left)
	var/obj/machinery/portable_atmospherics/canister/plasma/full = allocate(/obj/machinery/portable_atmospherics/canister/plasma, run_loc_floor_top_right)
	shipyard_apply_gas(drained.air_contents, list())
	drained.release_pressure = 200
	var/list/canister_state = shipyard_capture_state(drained)
	canister_state["holding"] = shipyard_roster_entry(allocate(/obj/item/tank/internals/oxygen))
	shipyard_apply_state(full, json_decode(json_encode(canister_state)))
	var/carried_moles = full.air_contents.total_moles()
	TEST_ASSERT_EQUAL(carried_moles, 0, "A drained canister should come back drained.")
	TEST_ASSERT_EQUAL(full.release_pressure, 200, "A canister should keep its release pressure.")
	TEST_ASSERT(istype(full.holding, /obj/item/tank/internals/oxygen), "A canister should keep the tank in it.")
	TEST_ASSERT_EQUAL(full.holding?.loc, full, "A canister's tank should be inside it.")

	var/obj/structure/reagent_dispensers/fueltank/used_tank = allocate(/obj/structure/reagent_dispensers/fueltank, run_loc_floor_bottom_left)
	var/obj/structure/reagent_dispensers/fueltank/fresh_tank = allocate(/obj/structure/reagent_dispensers/fueltank, run_loc_floor_top_right)
	used_tank.reagents.remove_all(used_tank.reagents.total_volume - 100)
	carry_state(used_tank, fresh_tank)
	TEST_ASSERT_EQUAL(fresh_tank.reagents.total_volume, 100, "A fuel tank should keep how much it holds.")

/**
 * Filing keeps paperwork where it lay and fixture state on the right fixture,
 * and retrieval puts both back.
 */
/datum/unit_test/overmap_ship_persistence/deck_state_retrieval

/datum/unit_test/overmap_ship_persistence/deck_state_retrieval/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Deck State Test Hull", owner_uuid)
	var/turf/corner = locate(zone.x + 2, zone.y + 2, zone.z)

	var/obj/item/paper/loose = written_paper("Left on the deck", locate(corner.x + 1, corner.y + 1, corner.z))
	loose.pixel_x = 5
	loose.pixel_y = -3
	allocate(/obj/item/pen, locate(corner.x + 1, corner.y + 1, corner.z))
	var/obj/structure/closet/locker = allocate(/obj/structure/closet, locate(corner.x + 2, corner.y + 1, corner.z))
	var/obj/item/folder/folder = allocate(/obj/item/folder, locker)
	written_paper("Filed away", folder)
	allocate(/obj/item/pen, locker)
	locker.close()
	var/turf/gas_tile = locate(corner.x + 2, corner.y + 2, corner.z)
	var/obj/machinery/portable_atmospherics/canister/plasma/first = allocate(/obj/machinery/portable_atmospherics/canister/plasma, gas_tile)
	var/obj/machinery/portable_atmospherics/canister/plasma/second = allocate(/obj/machinery/portable_atmospherics/canister/plasma, gas_tile)
	shipyard_apply_gas(first.air_contents, list())
	second.release_pressure = 300

	TEST_ASSERT(console.run_survey(hull, zone), "The deck state hull should survey: [console_says(console)]")
	TEST_ASSERT(console.file_hull(hull, zone, null), "The deck state hull should file: [console_says(console)]")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT(record, "The deck state hull should be in the garage.")
	var/deck_count = length(record.deck_state["items"])
	TEST_ASSERT_EQUAL(deck_count, 2, "Only the loose paper and the folder should be kept on deck.")
	var/fixture_count = length(record.deck_state["fixtures"])
	TEST_ASSERT_EQUAL(fixture_count, 2, "Both canisters should keep their state.")
	var/list/decoded = shipyard_decode_deck_state(json_decode(json_encode(record.deck_state)))
	TEST_ASSERT_EQUAL(length(decoded["items"]), deck_count, "Deck items should survive the database encoding.")
	TEST_ASSERT_EQUAL(length(decoded["fixtures"]), fixture_count, "Fixture state should survive the database encoding.")

	var/obj/docking_port/mobile/retrieved = console.retrieve_record(record.id, FALSE, zone, null)
	TEST_ASSERT(retrieved, "The deck state hull should retrieve: [console_says(console)]")
	hulls += retrieved
	var/obj/item/paper/found_paper
	var/obj/structure/closet/found_locker
	var/list/found_canisters = list()
	var/pens_aboard = 0
	for(var/turf/deck as anything in retrieved.return_turfs())
		for(var/atom/movable/thing in deck)
			if(istype(thing, /obj/item/paper))
				found_paper = thing
			else if(istype(thing, /obj/item/pen))
				pens_aboard++
			else if(thing.type == /obj/structure/closet)
				found_locker = thing
			else if(istype(thing, /obj/machinery/portable_atmospherics/canister/plasma))
				found_canisters += thing
	TEST_ASSERT(paper_says(found_paper, "Left on the deck"), "The loose paper should be back on the deck.")
	TEST_ASSERT_EQUAL(found_paper?.pixel_x, 5, "The loose paper should keep where it lay on its tile.")
	TEST_ASSERT_EQUAL(found_paper?.pixel_y, -3, "The loose paper should keep where it lay on its tile.")
	TEST_ASSERT(found_locker, "The locker should come back with the hull.")
	var/obj/item/folder/found_folder = locate() in found_locker
	TEST_ASSERT(paper_says(locate(/obj/item/paper) in found_folder, "Filed away"), "The folder should be back in its locker with its paper.")
	TEST_ASSERT(!(locate(/obj/item/pen) in found_locker), "A pen in a locker should not be kept.")
	TEST_ASSERT_EQUAL(pens_aboard, 0, "A loose pen should not be kept.")
	TEST_ASSERT_EQUAL(length(found_canisters), 2, "Both canisters should come back.")
	var/drained_count = 0
	var/high_pressure_count = 0
	for(var/obj/machinery/portable_atmospherics/canister/plasma/canister as anything in found_canisters)
		if(canister.air_contents.total_moles() == 0)
			drained_count++
		if(canister.release_pressure == 300)
			high_pressure_count++
	TEST_ASSERT_EQUAL(drained_count, 1, "Exactly one canister should come back drained.")
	TEST_ASSERT_EQUAL(high_pressure_count, 1, "Exactly one canister should keep its raised release pressure.")

/// Past the deck limit, paperwork is reported lost rather than kept.
/datum/unit_test/overmap_ship_persistence/deck_item_limit

/datum/unit_test/overmap_ship_persistence/deck_item_limit/Run()
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Deck Limit Test Hull", generate_character_uuid())
	var/turf/deck = locate(zone.x + 3, zone.y + 3, zone.z)
	for(var/i in 1 to SHIPYARD_DECK_ITEM_LIMIT + 1)
		allocate(/obj/item/paper, deck)
	var/datum/ship_teardown/teardown = new(hull, TRUE)
	TEST_ASSERT(!teardown.refusal, "The deck limit hull should walk: [teardown.refusal]")
	var/kept = length(teardown.deck_items)
	TEST_ASSERT_EQUAL(kept, SHIPYARD_DECK_ITEM_LIMIT, "No more than the deck limit should be kept.")
	var/over_limit = FALSE
	for(var/line in teardown.lost_detail)
		if(findtext(line, "item limit"))
			over_limit = TRUE
	TEST_ASSERT(over_limit, "The paper past the limit should be reported lost.")
	qdel(teardown)
