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

	vault.max_entries = 1
	var/obj/item/pen/overflow = allocate(/obj/item/pen)
	TEST_ASSERT(!vault.deposit(overflow), "A full vault should refuse another deposit.")
	TEST_ASSERT(!QDELETED(overflow), "A refused item should be left alone.")

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
	qdel(teardown)
