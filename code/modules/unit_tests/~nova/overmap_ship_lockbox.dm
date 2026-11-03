// MODULE ID: OVERMAP
// The ship lockbox vault: who opens it, how it moves, what it takes, and that
// what it hands back is what went in.
//
// Assertions stay on one physical line each, for the reason given at the top of
// overmap_ship_persistence.dm.

/// A character with a ledger PIN and a personal account, and an ID registered to it.
/datum/unit_test/overmap_ship_persistence/proc/vault_owner(owner_uuid, pin = 1234)
	var/mob/living/carbon/human/consistent/owner = allocate(/mob/living/carbon/human/consistent)
	owner.mind_initialize()
	owner.mind.character_uuid = owner_uuid
	owner.mind.atm_pin = pin
	var/datum/bank_account/account = new(owner.real_name, SSjob.get_job_type(/datum/job/assistant))
	allocated += account
	owner.account_id = account.account_id
	var/obj/item/card/id/advanced/card = allocate(/obj/item/card/id/advanced)
	card.registered_account = account
	return list(owner, card)

/// The fixture hull's vault, with the keypad on whatever power it is standing in.
/datum/unit_test/overmap_ship_persistence/proc/fixture_vault(obj/effect/landmark/overmap_landing_zone/zone)
	var/obj/machinery/ship_lockbox/floor/vault = locate() in locate(zone.x + 2, zone.y + 4, zone.z)
	TEST_ASSERT(vault, "The fixture hull should carry a floor vault.")
	vault.update_use_power(NO_POWER_USE)
	vault.power_change()
	TEST_ASSERT(vault.is_operational, "The fixture vault should be powered for the test.")
	return vault

/// An unowned vault off any hull, open and ready to take things.
/datum/unit_test/overmap_ship_persistence/proc/open_vault()
	var/obj/machinery/ship_lockbox/wall/vault = allocate(/obj/machinery/ship_lockbox/wall, run_loc_floor_bottom_left)
	vault.update_use_power(NO_POWER_USE)
	vault.power_change()
	TEST_ASSERT(!vault.is_locked(), "A vault on no hull should not be locked.")
	TEST_ASSERT(vault.open_door(null), "An unlocked vault should open.")
	vault.finish_door_motion()
	TEST_ASSERT(vault.is_accessible(), "An opened vault should be accessible.")
	return vault

/// Only the owner, with their own ID and their PIN, gets in; three misses lock the keypad.
/datum/unit_test/overmap_ship_persistence/lockbox_unlock

/datum/unit_test/overmap_ship_persistence/lockbox_unlock/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	build_fixture_hull(zone, "Vault Test Hull", owner_uuid)
	var/obj/machinery/ship_lockbox/floor/vault = fixture_vault(zone)
	var/list/owner_kit = vault_owner(owner_uuid)
	var/mob/living/carbon/human/owner = owner_kit[1]
	var/obj/item/card/id/owner_card = owner_kit[2]
	var/list/stranger_kit = vault_owner(generate_character_uuid())
	var/mob/living/carbon/human/stranger = stranger_kit[1]
	var/obj/item/card/id/stranger_card = stranger_kit[2]

	TEST_ASSERT(vault.is_locked(), "A vault on an owned hull should start locked.")
	TEST_ASSERT(!vault.density, "A lowered vault should be walkable.")
	TEST_ASSERT(!vault.attempt_unlock(owner, owner_card, 4321), "A wrong PIN should be refused.")
	TEST_ASSERT(!vault.attempt_unlock(stranger, stranger_card, 1234), "Someone who is not the owner should be refused.")
	TEST_ASSERT(!vault.in_lockout(), "Two failures should not lock the keypad out yet.")
	TEST_ASSERT(!vault.attempt_unlock(owner, stranger_card, 1234), "The owner presenting someone else's ID should be refused.")
	TEST_ASSERT(vault.is_locked(), "Refusals should leave the vault locked.")
	TEST_ASSERT(vault.in_lockout(), "Three failures in a row should lock the keypad out.")
	TEST_ASSERT(!vault.attempt_unlock(owner, owner_card, 1234), "A locked-out keypad should refuse even the owner.")

	vault.lockout_until = 0
	TEST_ASSERT(vault.attempt_unlock(owner, owner_card, 1234), "The owner with their ID and PIN should get in.")
	TEST_ASSERT(!vault.is_locked(), "A successful unlock should unlock the vault.")
	TEST_ASSERT(vault.density, "An unlocked floor vault should rise and become solid.")
	vault.finish_motion()
	TEST_ASSERT(vault.is_raised(), "A floor vault should be raised once it has finished rising.")

/// Closing the door locks the vault and sends a floor vault back down.
/datum/unit_test/overmap_ship_persistence/lockbox_motion

/datum/unit_test/overmap_ship_persistence/lockbox_motion/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	build_fixture_hull(zone, "Vault Motion Test Hull", owner_uuid)
	var/obj/machinery/ship_lockbox/floor/vault = fixture_vault(zone)
	var/list/owner_kit = vault_owner(owner_uuid)
	var/mob/living/carbon/human/owner = owner_kit[1]

	var/obj/structure/table/blocker = allocate(/obj/structure/table, vault.loc)
	vault.locked = FALSE
	TEST_ASSERT(!vault.rise(owner), "A vault should not rise into something solid on its tile.")
	qdel(blocker)
	TEST_ASSERT(vault.rise(owner), "An unlocked vault on a clear tile should rise.")
	vault.finish_motion()
	TEST_ASSERT(vault.open_door(owner), "A raised, unlocked vault should open.")
	vault.finish_door_motion()
	TEST_ASSERT(vault.is_accessible(), "An open vault should be accessible.")
	TEST_ASSERT(vault.close_door(owner), "An open vault should close.")
	TEST_ASSERT(vault.is_locked(), "Closing the door should lock the vault.")
	TEST_ASSERT(!vault.is_accessible(), "A closed vault should not be accessible.")
	TEST_ASSERT_EQUAL(vault.ui_status(owner, GLOB.default_state), UI_CLOSE, "A closed vault should close its storage window.")
	vault.finish_door_motion()
	TEST_ASSERT_EQUAL(vault.motion, "descend", "A closed floor vault should lower itself.")
	vault.finish_motion()
	TEST_ASSERT(!vault.raised, "The floor vault should end up lowered.")
	TEST_ASSERT(!vault.density, "A lowered vault should be walkable again.")
	var/obj/item/pen/pen = allocate(/obj/item/pen)
	owner.put_in_hands(pen)
	vault.item_interaction(owner, pen, list())
	TEST_ASSERT(!QDELETED(pen), "A closed vault should not take deposits.")
	TEST_ASSERT_EQUAL(length(vault.stored_entries), 1, "A closed vault should hold only what the fixture put in it.")

/// A deposit is written down and deleted; a withdrawal builds it in the user's hand.
/datum/unit_test/overmap_ship_persistence/lockbox_storage

/datum/unit_test/overmap_ship_persistence/lockbox_storage/Run()
	var/obj/machinery/ship_lockbox/wall/vault = open_vault()
	var/mob/living/carbon/human/consistent/user = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	var/obj/item/pen/first = allocate(/obj/item/pen)
	user.put_in_hands(first)
	TEST_ASSERT_EQUAL(vault.item_interaction(user, first, list()), ITEM_INTERACT_SUCCESS, "An open vault should take a pen from a hand.")
	TEST_ASSERT(QDELETED(first), "A deposited item should be deleted.")
	TEST_ASSERT(vault.deposit(allocate(/obj/item/pen)), "An open vault should take a second pen.")
	TEST_ASSERT_EQUAL(length(vault.stored_entries), 2, "Each deposit should add one entry.")
	TEST_ASSERT(!length(vault.contents), "A vault should hold entries, not items.")

	var/list/data = vault.ui_data(user)
	var/list/rows = data["contents"]
	TEST_ASSERT_EQUAL(length(rows), 1, "Two identical pens should share a row.")
	var/list/row = rows[rows[1]]
	TEST_ASSERT_EQUAL(row["amount"], 2, "The shared row should count both pens.")

	TEST_ASSERT_EQUAL(vault.withdraw(row["path"], 1, user), 1, "Releasing one pen should release one.")
	TEST_ASSERT(locate(/obj/item/pen) in user.held_items, "A released pen should land in the user's hand.")
	TEST_ASSERT_EQUAL(length(vault.stored_entries), 1, "Releasing should remove its entry.")

/// An item whose name carries a text macro lists cleanly and comes back out through the UI.
/datum/unit_test/overmap_ship_persistence/lockbox_improper_names

/datum/unit_test/overmap_ship_persistence/lockbox_improper_names/Run()
	var/obj/machinery/ship_lockbox/wall/vault = open_vault()
	var/mob/living/carbon/human/consistent/user = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)
	TEST_ASSERT(vault.deposit(allocate(/obj/item/food/cornchips)), "The vault should take a bag of corn chips.")

	var/list/rows = vault.ui_data(user)["contents"]
	var/list/row = rows[rows[1]]
	TEST_ASSERT_EQUAL(row["name"], "Boritos Corn Chips", "A row should be named without its text macro.")
	var/list/sent = json_decode(json_encode(list("path" = row["path"])))
	TEST_ASSERT_EQUAL(vault.withdraw(sent["path"], 1, user), 1, "A row key that has been through the UI should still release its item.")
	TEST_ASSERT(locate(/obj/item/food/cornchips) in user.held_items, "The released chips should land in the user's hand.")

/// Living things, identity, objectives and one-of-a-kind items stay out.
/datum/unit_test/overmap_ship_persistence/lockbox_refusals

/datum/unit_test/overmap_ship_persistence/lockbox_refusals/Run()
	var/obj/machinery/ship_lockbox/wall/vault = open_vault()

	var/obj/item/storage/box/pet_box = allocate(/obj/item/storage/box)
	var/mob/living/basic/mouse/mouse = allocate(/mob/living/basic/mouse)
	mouse.forceMove(pet_box)
	var/obj/item/storage/wallet/wallet = allocate(/obj/item/storage/wallet)
	allocate(/obj/item/card/id/advanced, wallet)
	var/list/refused = list(
		pet_box,
		wallet,
		allocate(/obj/item/modular_computer/pda),
		allocate(/obj/item/uplink),
	)
	var/obj/item/hand_tele/objective = /obj/item/hand_tele
	TEST_ASSERT(lockbox_high_risk_paths()[objective], "The hand teleporter should be a high-risk steal target for this case to mean anything.")
	TEST_ASSERT(!lockbox_high_risk_paths()[/obj/item/bikehorn], "Abstract objectives should not make their placeholder target high risk.")
	TEST_ASSERT(!lockbox_high_risk_paths()[/obj/item/gun/energy/laser], "A spy bounty target should stay storable.")
	refused += allocate(objective)
	for(var/obj/item/item as anything in refused)
		TEST_ASSERT(vault.lockbox_refusal(item), "[item.type] should be refused.")
		TEST_ASSERT(!vault.deposit(item), "[item.type] should not go in.")
		TEST_ASSERT(!QDELETED(item), "A refused [item.type] should be left alone.")
	TEST_ASSERT(!length(vault.stored_entries), "Nothing refused should have gone in.")
	TEST_ASSERT(findtext(vault.lockbox_refusal(wallet), "inside"), "A refusal should name what inside the container is the problem.")

/// What comes out of the vault is in the state it went in, not a refill.
/datum/unit_test/overmap_ship_persistence/lockbox_refill

/datum/unit_test/overmap_ship_persistence/lockbox_refill/Run()
	var/obj/machinery/ship_lockbox/wall/vault = open_vault()

	var/obj/item/stock_parts/power_store/cell/high/cell = allocate(/obj/item/stock_parts/power_store/cell/high)
	cell.charge = cell.maxcharge / 2
	var/half_charge = cell.charge
	var/obj/item/stock_parts/power_store/cell/high/cell_back = cycle_through(vault, cell)
	TEST_ASSERT_EQUAL(cell_back?.charge, half_charge, "A half-drained cell should come back half drained.")

	var/obj/item/extinguisher/extinguisher = allocate(/obj/item/extinguisher)
	extinguisher.reagents.remove_all(extinguisher.reagents.total_volume / 2)
	var/expected_volume = extinguisher.reagents.total_volume
	var/obj/item/extinguisher/extinguisher_back = cycle_through(vault, extinguisher)
	TEST_ASSERT_EQUAL(extinguisher_back?.reagents.total_volume, expected_volume, "A half-empty extinguisher should come back half empty.")

	var/obj/item/ammo_box/magazine/m9mm/magazine = allocate(/obj/item/ammo_box/magazine/m9mm)
	for(var/i in 1 to 3)
		qdel(magazine.get_round())
	var/expected_rounds = magazine.ammo_count()
	var/obj/item/ammo_box/magazine/m9mm/magazine_back = cycle_through(vault, magazine)
	TEST_ASSERT_EQUAL(magazine_back?.ammo_count(), expected_rounds, "A part-fired magazine should come back part fired.")

	var/obj/item/gun/ballistic/automatic/pistol/pistol = allocate(/obj/item/gun/ballistic/automatic/pistol)
	for(var/i in 1 to 2)
		qdel(pistol.magazine.get_round())
	var/expected_ammo = pistol.get_ammo(TRUE)
	var/obj/item/gun/ballistic/automatic/pistol/pistol_back = cycle_through(vault, pistol)
	TEST_ASSERT_EQUAL(pistol_back?.get_ammo(TRUE), expected_ammo, "A pistol with a part-loaded magazine should come back as loaded as it went in.")

	var/obj/item/gun/energy/laser/laser = allocate(/obj/item/gun/energy/laser)
	laser.cell.charge = 0
	var/obj/item/gun/energy/laser/laser_back = cycle_through(vault, laser)
	TEST_ASSERT_EQUAL(laser_back?.cell?.charge, 0, "A drained energy gun should come back drained.")

/// Deposit `item` into `vault` and take it straight back out.
/datum/unit_test/overmap_ship_persistence/proc/cycle_through(obj/machinery/ship_lockbox/vault, obj/item/item)
	TEST_ASSERT(vault.deposit(item), "[item.type] should go into the vault.")
	var/list/entry = vault.stored_entries[length(vault.stored_entries)]
	var/obj/item/built = null
	var/turf/drop = vault.drop_location()
	var/list/before = drop.contents.Copy()
	vault.withdraw(vault.entry_key(entry), 1, null)
	for(var/obj/item/arrived in drop.contents - before)
		built = arrived
	if(built)
		allocated += built
	return built

/// The closet a saved map may still name turns into a floor vault.
/datum/unit_test/overmap_ship_persistence/lockbox_legacy

/datum/unit_test/overmap_ship_persistence/lockbox_legacy/Run()
	var/obj/structure/closet/secure_closet/ship_lockbox/legacy = new(run_loc_floor_bottom_left)
	TEST_ASSERT(QDELETED(legacy), "The legacy closet should remove itself.")
	var/obj/machinery/ship_lockbox/floor/vault = locate() in run_loc_floor_bottom_left
	TEST_ASSERT(vault, "The legacy closet should leave a floor vault in its place.")
	allocated += vault

/**
 * A lockbox shaped like a real filing: snacks, a disk, a full toolbelt, and a
 * waistpack holding a part exchanger full of parts. A survey run before the
 * last deposit is stale; once resurveyed, everything is filed, retrieved, and
 * released through the keys the UI hands back.
 */
/datum/unit_test/overmap_ship_persistence/lockbox_filed_roster

/datum/unit_test/overmap_ship_persistence/lockbox_filed_roster/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Vault Roster Test Hull", owner_uuid)
	var/obj/machinery/ship_lockbox/floor/vault = fixture_vault(zone)
	var/obj/item/storage/backpack/tinypaka/waistpack = allocate(/obj/item/storage/backpack/tinypaka)
	var/obj/item/storage/part_replacer/rped = allocate(/obj/item/storage/part_replacer)
	for(var/i in 1 to 3)
		allocate(/obj/item/stock_parts/matter_bin, rped)
	rped.forceMove(waistpack)
	TEST_ASSERT(vault.deposit(allocate(/obj/item/food/cornchips)), "The vault should take corn chips.")
	TEST_ASSERT(vault.deposit(allocate(/obj/item/disk/bitrunning/item/tier1)), "The vault should take a bitrunning disk.")
	TEST_ASSERT(vault.deposit(allocate(/obj/item/storage/belt/utility/full)), "The vault should take a full toolbelt.")

	TEST_ASSERT(console.run_survey(hull, zone), "The roster hull should survey: [console_says(console)]")
	TEST_ASSERT(console.survey_current(hull), "A fresh survey should be current.")
	TEST_ASSERT(vault.deposit(waistpack), "The vault should take the waistpack.")
	TEST_ASSERT(!console.survey_current(hull), "A deposit after the survey should leave it stale.")
	TEST_ASSERT(!console.file_hull(hull, zone, null), "A stale survey should not let the hull file.")
	TEST_ASSERT(!QDELETED(hull), "A refused filing should leave the hull in place.")

	TEST_ASSERT(console.run_survey(hull, zone), "The roster hull should survey again: [console_says(console)]")
	var/list/line_names = list()
	for(var/list/line in console.survey["lockbox"])
		line_names += line["name"]
	TEST_ASSERT("Boritos corn chips" in line_names, "The survey should list the chips by their plain name, got [english_list(line_names)].")
	TEST_ASSERT("waistpack" in line_names, "The survey should list the waistpack deposited after the first survey.")
	TEST_ASSERT(console.file_hull(hull, zone, null), "The resurveyed hull should file: [console_says(console)]")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT_EQUAL(length(record?.stored_contents), 5, "The fixture pen and four deposits should be filed.")

	var/obj/docking_port/mobile/retrieved = console.retrieve_record(record.id, FALSE, zone, null)
	TEST_ASSERT(retrieved, "The roster hull should retrieve: [console_says(console)]")
	hulls += retrieved
	var/obj/machinery/ship_lockbox/floor/retrieved_vault
	for(var/turf/deck as anything in retrieved.return_turfs())
		retrieved_vault = locate() in deck
		if(retrieved_vault)
			break
	TEST_ASSERT(retrieved_vault, "The retrieved hull should carry its vault.")
	TEST_ASSERT_EQUAL(length(retrieved_vault.stored_entries), 5, "The retrieved vault should hold everything filed.")

	var/turf/drop = retrieved_vault.drop_location()
	var/list/before = drop.contents.Copy()
	var/list/rows = retrieved_vault.ui_data(null)["contents"]
	for(var/key in rows)
		var/list/sent = json_decode(json_encode(list("path" = rows[key]["path"])))
		retrieved_vault.withdraw(sent["path"], rows[key]["amount"], null)
	TEST_ASSERT(!length(retrieved_vault.stored_entries), "Every row should release.")
	var/list/arrived = drop.contents - before
	allocated += arrived
	TEST_ASSERT(locate(/obj/item/food/cornchips) in arrived, "The chips should come back out.")
	var/obj/item/storage/backpack/tinypaka/pack_back = locate() in arrived
	var/obj/item/storage/part_replacer/rped_back = locate() in pack_back
	TEST_ASSERT(rped_back, "The part exchanger should come back inside the waistpack.")
	var/bins_back = 0
	for(var/obj/item/part in rped_back)
		if(istype(part, /obj/item/stock_parts/matter_bin))
			bins_back++
	TEST_ASSERT_EQUAL(bins_back, 3, "The parts should come back inside the part exchanger.")

/// Teardown keeps the entries of every vault aboard, and appraisal reads their cached values.
/datum/unit_test/overmap_ship_persistence/lockbox_teardown

/datum/unit_test/overmap_ship_persistence/lockbox_teardown/Run()
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Vault Teardown Test Hull", generate_character_uuid())
	var/obj/machinery/ship_lockbox/floor/floor_vault = fixture_vault(zone)
	var/obj/machinery/ship_lockbox/wall/wall_vault = allocate(/obj/machinery/ship_lockbox/wall, locate(zone.x + 4, zone.y + 4, zone.z))
	TEST_ASSERT(wall_vault.deposit(allocate(/obj/item/stack/sheet/iron)), "The wall vault should take a stack of iron.")
	var/list/floor_entry = floor_vault.stored_entries[1]
	var/list/wall_entry = wall_vault.stored_entries[1]
	floor_entry["value"] = 500
	wall_entry["value"] = 250

	var/datum/ship_teardown/teardown = new(hull, TRUE)
	TEST_ASSERT(!teardown.refusal, "The vault hull should walk: [teardown.refusal]")
	TEST_ASSERT_EQUAL(length(teardown.stored_contents), 2, "Teardown should keep the entries of both vaults.")
	var/list/appraisal = shipyard_appraise_lockbox(teardown.stored_contents)
	TEST_ASSERT_EQUAL(appraisal["total"], 750, "Appraisal should price entries from their cached values.")
	for(var/list/copied as anything in teardown.stored_contents)
		if(copied["value"] == 500)
			copied["value"] = 0
	appraisal = shipyard_appraise_lockbox(teardown.stored_contents)
	TEST_ASSERT_EQUAL(appraisal["total"], 250, "An entry with no export value should be stored for free.")
	qdel(teardown)

/// An item and everything stored inside it, down every level, as one comparable line.
/proc/shipyard_test_item_tree(obj/item/item)
	var/text = "[item.type]"
	if(isstack(item))
		var/obj/item/stack/stack = item
		text += " x[stack.amount]"
	if(item.reagents?.total_volume)
		text += " [round(item.reagents.total_volume)]u"
	var/atom/held_in = item.atom_storage?.real_location
	if(held_in)
		var/list/children = list()
		for(var/obj/item/held in held_in)
			children += shipyard_test_item_tree(held)
		text += " ([jointext(sortTim(children, GLOBAL_PROC_REF(cmp_text_asc)), ", ")])"
	return text

/**
 * Containers three deep, holding stacks and reagents, come back whole from a
 * filing: from the vault, and from the deck beside it.
 */
/datum/unit_test/overmap_ship_persistence/lockbox_nested_containers

/datum/unit_test/overmap_ship_persistence/lockbox_nested_containers/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Nested Container Test Hull", owner_uuid)
	var/obj/machinery/ship_lockbox/floor/vault = fixture_vault(zone)

	var/obj/item/storage/backpack/tinypaka/waistpack = allocate(/obj/item/storage/backpack/tinypaka)
	allocate(/obj/item/storage/medkit/frontier/stocked, waistpack)
	allocate(/obj/item/storage/box/bandages, waistpack)
	var/list/deposits = list(waistpack, allocate(/obj/item/storage/belt/utility/full))
	var/list/expected = list()
	for(var/obj/item/deposit as anything in deposits)
		expected += shipyard_test_item_tree(deposit)
		TEST_ASSERT(vault.deposit(deposit), "The vault should take [deposit].")
	TEST_ASSERT(findtext(expected[1], "/obj/item/storage/pill_bottle"), "The fixture should nest three deep, got [expected[1]].")
	var/obj/item/storage/photo_album/deck_album = allocate(/obj/item/storage/photo_album, locate(zone.x + 3, zone.y + 3, zone.z))
	for(var/i in 1 to 2)
		allocate(/obj/item/paper, deck_album.atom_storage.real_location)
	var/expected_deck = shipyard_test_item_tree(deck_album)

	TEST_ASSERT(console.run_survey(hull, zone), "The nested hull should survey: [console_says(console)]")
	TEST_ASSERT(console.file_hull(hull, zone, null), "The nested hull should file: [console_says(console)]")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	var/obj/docking_port/mobile/retrieved = console.retrieve_record(record.id, FALSE, zone, null)
	TEST_ASSERT(retrieved, "The nested hull should retrieve: [console_says(console)]")
	hulls += retrieved

	var/obj/machinery/ship_lockbox/floor/retrieved_vault
	var/obj/item/storage/photo_album/album_back
	for(var/turf/deck as anything in retrieved.return_turfs())
		retrieved_vault ||= locate(/obj/machinery/ship_lockbox/floor) in deck
		album_back ||= locate(/obj/item/storage/photo_album) in deck
	TEST_ASSERT(retrieved_vault, "The retrieved hull should carry its vault.")
	TEST_ASSERT(album_back, "The album on the deck should come back.")
	TEST_ASSERT_EQUAL(shipyard_test_item_tree(album_back), expected_deck, "The deck album should come back with what it held.")
	TEST_ASSERT_EQUAL(length(retrieved_vault.stored_entries), length(deposits) + 1, "The vault should come back holding the fixture pen and every deposit.")

	var/turf/drop = retrieved_vault.drop_location()
	var/list/before = drop.contents.Copy()
	var/list/rows = retrieved_vault.ui_data(null)["contents"]
	for(var/key in rows)
		var/list/sent = json_decode(json_encode(list("path" = rows[key]["path"])))
		retrieved_vault.withdraw(sent["path"], rows[key]["amount"], null)
	TEST_ASSERT(!length(retrieved_vault.stored_entries), "Every row should release.")
	var/list/arrived = drop.contents - before
	allocated += arrived
	var/list/released = list()
	for(var/obj/item/item in arrived)
		if(item.atom_storage)
			released += shipyard_test_item_tree(item)
	TEST_ASSERT_EQUAL(jointext(sortTim(released, GLOBAL_PROC_REF(cmp_text_asc)), "\n"), jointext(sortTim(expected, GLOBAL_PROC_REF(cmp_text_asc)), "\n"), "Every container should come back holding what it held, all the way down.")
