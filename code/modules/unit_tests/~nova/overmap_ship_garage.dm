// MODULE ID: OVERMAP
// Garage slots, what the registrar does with ships that are lost or unwanted,
// and the vessel broker that sells new ones. Built on the persistence cases'
// fixtures: the same pad, the same three by three hull, the same console.
//
// As there, every assertion is one physical line.

/// Take `count` slots in `owner_ckey`'s pool with rows that hold a filed map.
/datum/unit_test/overmap_ship_persistence/proc/fill_slots(owner_ckey, count)
	var/filler_uuid = generate_character_uuid()
	for(var/index in 1 to count)
		var/record_id = GLOB.ship_registry.insert_record(filler_uuid, owner_ckey, "Filler [index]")
		TEST_ASSERT(record_id, "A filler record should insert.")
		TEST_ASSERT(GLOB.ship_registry.store_revision(record_id, 1, "data/unit_test_ship_filler_[record_id].dmm", null, list(), 9, "Filler [index]", 100), "A filler record should store a revision.")

/// A broker with a session open for `owner_uuid`, working over `zone`.
/datum/unit_test/overmap_ship_persistence/proc/logged_in_broker(owner_uuid, balance, obj/effect/landmark/overmap_landing_zone/zone)
	owner_uuids += owner_uuid
	if(balance)
		var/datum/character_ledger_result/seed = SScharacter_ledger.try_credit(owner_uuid, balance, LEDGER_CHANNEL_ADMIN_SEED, "ship broker test seed", "test:broker:seed:[owner_uuid]")
		TEST_ASSERT(seed.success, "Seeding the test ledger should succeed, got '[seed.status]'.")
	var/obj/machinery/computer/ship_broker/broker = allocate(/obj/machinery/computer/ship_broker)
	broker.authenticated = TRUE
	broker.session.operator_uuid = owner_uuid
	broker.session.operator_ckey = ckey("spt[owner_uuid]")
	if(zone)
		var/obj/machinery/computer/landing_controller/controller = allocate(/obj/machinery/computer/landing_controller)
		controller.active_zone = zone
		broker.session.linked_controller = WEAKREF(controller)
	broker.refresh_session()
	return broker

/datum/unit_test/overmap_ship_persistence/proc/broker_says(obj/machinery/computer/ship_broker/broker)
	var/list/message = broker.session.status_message
	return message ? message["text"] : "nothing"

// --- Slots ------------------------------------------------------------------

/**
 * The pool is the configured base plus every live grant, and everything with a
 * filed map counts against it, whichever character it belongs to.
 */
/datum/unit_test/overmap_ship_persistence/slot_pool

/datum/unit_test/overmap_ship_persistence/slot_pool/Run()
	var/owner_ckey = ckey("sptpool[REF(src)]")
	var/base = CONFIG_GET(number/ship_garage_base_slots)
	var/list/usage = GLOB.ship_garage_slots.usage(owner_ckey)
	TEST_ASSERT_EQUAL(usage["total"], base, "A player with no grants should have the base slots.")
	TEST_ASSERT_EQUAL(usage["used"], 0, "A player with no ships should use no slots.")

	// A row without a map is a claim in progress, not a ship.
	var/pending_id = GLOB.ship_registry.insert_record(generate_character_uuid(), owner_ckey, "Pending")
	TEST_ASSERT(pending_id, "A bare record should insert.")
	usage = GLOB.ship_garage_slots.usage(owner_ckey)
	TEST_ASSERT_EQUAL(usage["used"], 0, "A record with no filed map should not take a slot.")
	GLOB.ship_registry.discard(pending_id)

	fill_slots(owner_ckey, base)
	TEST_ASSERT(!GLOB.ship_garage_slots.can_add(owner_ckey), "A pool filled to its base should refuse another ship.")
	var/grant_id = GLOB.ship_garage_slots.award_slots(owner_ckey, SHIP_SLOT_GRANT_DONATOR, "Test donation", 2, "tester")
	TEST_ASSERT(grant_id, "Awarding slots should return the grant.")
	usage = GLOB.ship_garage_slots.usage(owner_ckey)
	TEST_ASSERT_EQUAL(usage["total"], base + 2, "A grant should add its count to the pool.")
	TEST_ASSERT(GLOB.ship_garage_slots.can_add(owner_ckey), "A grant should make room.")
	var/datum/ship_slot_grant/grant = GLOB.ship_garage_slots.get_grant(owner_ckey, grant_id)
	TEST_ASSERT_EQUAL(grant?.source, "Test donation", "A grant should remember what it was for.")

	TEST_ASSERT(GLOB.ship_garage_slots.revoke_grant(grant_id), "Revoking a grant should succeed.")
	usage = GLOB.ship_garage_slots.usage(owner_ckey)
	TEST_ASSERT_EQUAL(usage["total"], base, "A revoked grant should stop counting.")
	TEST_ASSERT(!GLOB.ship_garage_slots.award_slots(owner_ckey, "BRIBE", "Not a kind", 1, "tester"), "An unknown grant kind should be refused.")

/// An awarded ship brings the slot it sits in.
/datum/unit_test/overmap_ship_persistence/award_ship

/datum/unit_test/overmap_ship_persistence/award_ship/Run()
	var/owner_uuid = generate_character_uuid()
	owner_uuids += owner_uuid
	var/owner_ckey = ckey("sptaward[REF(src)]")
	var/base = CONFIG_GET(number/ship_garage_base_slots)
	fill_slots(owner_ckey, base)
	var/datum/ship_listing/listing = shipyard_ship_listing("nt_personal")
	TEST_ASSERT(listing, "The open NT listing should exist.")
	var/record_id = shipyard_award_ship(listing, owner_uuid, owner_ckey, "Prize Hull", "Test event", "tester")
	TEST_ASSERT(record_id, "Awarding a ship into a full garage should still succeed.")
	var/list/usage = GLOB.ship_garage_slots.usage(owner_ckey)
	TEST_ASSERT_EQUAL(usage["total"], base + 1, "An awarded ship should bring one slot.")
	TEST_ASSERT_EQUAL(usage["used"], base + 1, "An awarded ship should take the slot it brought.")
	var/datum/player_ship_record/record = GLOB.ship_registry.get_record(record_id, owner_uuid)
	TEST_ASSERT_EQUAL(record?.status, SHIP_STATUS_FILED, "An awarded ship should be waiting in the garage.")
	TEST_ASSERT_EQUAL(record.revision, 1, "An awarded ship should be revision 1.")
	TEST_ASSERT(record.grant_id, "An awarded ship should point at the grant it came with.")
	var/datum/ship_slot_grant/grant = GLOB.ship_garage_slots.get_grant(owner_ckey, record.grant_id)
	TEST_ASSERT_EQUAL(grant?.kind, SHIP_SLOT_GRANT_EVENT, "An awarded ship's slot should be an event grant.")
	TEST_ASSERT(fexists(record.map_path), "An awarded ship's map should be copied to [record.map_path].")

// --- Registrar slot rules ---------------------------------------------------

/// A first filing into a full garage is refused before anything is charged or deleted.
/datum/unit_test/overmap_ship_persistence/full_garage

/datum/unit_test/overmap_ship_persistence/full_garage/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Full Garage Hull", owner_uuid)
	fill_slots(console.session.operator_ckey, CONFIG_GET(number/ship_garage_base_slots))

	TEST_ASSERT(console.run_survey(hull, zone), "A full garage should not stop a survey: [console_says(console)]")
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	TEST_ASSERT(!console.file_hull(hull, zone, null), "A first filing into a full garage should be refused.")
	TEST_ASSERT(findtext(console_says(console), "garage is full"), "The refusal should say the garage is full, said '[console_says(console)]'.")
	TEST_ASSERT(!QDELETED(hull), "A refused filing should leave the hull standing.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before, "A refused filing should charge nothing.")
	TEST_ASSERT(!length(GLOB.ship_registry.list_for_owner(owner_uuid)), "A refused filing should leave no record.")

/**
 * Over the limit, a stored ship still comes out, but one that is out cannot go
 * back in until the garage is under its limit again.
 */
/datum/unit_test/overmap_ship_persistence/over_limit

/datum/unit_test/overmap_ship_persistence/over_limit/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Over Limit Hull", owner_uuid)
	TEST_ASSERT(console.run_survey(hull, zone), "The fixture hull should survey: [console_says(console)]")
	TEST_ASSERT(console.file_hull(hull, zone, null), "The fixture hull should file: [console_says(console)]")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT(record, "The fixture hull should be in the garage.")

	// Pushed over the limit, the way a revoked grant or a lowered base would.
	fill_slots(console.session.operator_ckey, CONFIG_GET(number/ship_garage_base_slots))
	var/list/usage = GLOB.ship_garage_slots.usage(console.session.operator_ckey)
	TEST_ASSERT(usage["used"] > usage["total"], "The garage should now be over its limit.")

	var/obj/docking_port/mobile/retrieved = console.retrieve_record(record.id, FALSE, zone, null)
	TEST_ASSERT(retrieved, "A stored ship should still retrieve over the limit: [console_says(console)]")
	hulls += retrieved
	TEST_ASSERT(console.run_survey(retrieved, zone), "The retrieved hull should survey: [console_says(console)]")
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	TEST_ASSERT(!console.file_hull(retrieved, zone, null), "A ship that is out should not refile over the limit.")
	TEST_ASSERT(findtext(console_says(console), "over its slot limit"), "The refusal should say the garage is over its limit, said '[console_says(console)]'.")
	TEST_ASSERT(!QDELETED(retrieved), "A refused refile should leave the hull standing.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before, "A refused refile should charge nothing.")

// --- Lost ships, scrap and blueprints ---------------------------------------

/// Scrapping pays its share of the hull and lockbox and frees the slot.
/datum/unit_test/overmap_ship_persistence/decommission

/datum/unit_test/overmap_ship_persistence/decommission/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Scrap Hull", owner_uuid)
	TEST_ASSERT(console.run_survey(hull, zone), "The fixture hull should survey: [console_says(console)]")
	TEST_ASSERT(console.file_hull(hull, zone, null), "The fixture hull should file: [console_says(console)]")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT(record, "The fixture hull should be in the garage.")

	var/worth = record.salvage_estimate + shipyard_appraise_roster(record.stored_contents)
	var/expected = round(worth * CONFIG_GET(number/ship_scrap_rate), 10)
	TEST_ASSERT_EQUAL(shipyard_scrap_value(record), expected, "Scrap should pay the configured share of hull and lockbox value.")
	TEST_ASSERT(expected > 0, "The fixture hull should be worth something as scrap.")
	var/used_before = GLOB.ship_garage_slots.usage(console.session.operator_ckey)["used"]
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	TEST_ASSERT(console.decommission_record(record.id, null), "Scrapping a stored ship should succeed: [console_says(console)]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before + expected, "Scrapping should credit the scrap value.")
	TEST_ASSERT(!length(GLOB.ship_registry.list_for_owner(owner_uuid)), "A scrapped ship should leave the garage.")
	TEST_ASSERT_EQUAL(GLOB.ship_garage_slots.usage(console.session.operator_ckey)["used"], used_before - 1, "Scrapping should free the slot.")
	TEST_ASSERT(!console.decommission_record(record.id, null), "A ship cannot be scrapped twice.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before + expected, "A second scrap should pay nothing.")

/**
 * A lost ship holds its slot until it is cleared or built again. Its blueprint
 * costs the storage fee without the lockbox, prints once a shift, and a hull
 * built from it files back into the same row.
 */
/datum/unit_test/overmap_ship_persistence/lost_rebuild

/datum/unit_test/overmap_ship_persistence/lost_rebuild/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 50000)
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/obj/docking_port/mobile/hull = build_fixture_hull(zone, "Lost Hull", owner_uuid)
	TEST_ASSERT(console.run_survey(hull, zone), "The fixture hull should survey: [console_says(console)]")
	TEST_ASSERT(console.file_hull(hull, zone, null), "The fixture hull should file: [console_says(console)]")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT(record, "The fixture hull should be in the garage.")
	var/datum/player_ship_record/row = GLOB.ship_registry.memory_rows["[record.id]"]
	row.status = SHIP_STATUS_LOST
	record = GLOB.ship_registry.get_record(record.id, owner_uuid)
	var/owner_ckey = console.session.operator_ckey
	TEST_ASSERT_EQUAL(GLOB.ship_garage_slots.usage(owner_ckey)["used"], 1, "A lost ship should keep its slot.")
	TEST_ASSERT(!console.decommission_record(record.id, null), "A lost ship cannot be scrapped.")

	var/fee = shipyard_blueprint_fee(record)
	var/list/storage_only = shipyard_storage_quote(record.tile_count, 0)
	TEST_ASSERT_EQUAL(fee, storage_only["storage"], "The blueprint should cost the storage fee without a lockbox.")
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	var/obj/item/ship_blueprint_disk/registry_rebuild/disk = console.print_blueprint(record.id, null)
	TEST_ASSERT(disk, "Printing a lost ship's blueprint should dispense a disk: [console_says(console)]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - fee, "Printing should charge the blueprint fee.")
	TEST_ASSERT_EQUAL(disk.registry_record_id, record.id, "The disk should point at the lost ship's record.")
	TEST_ASSERT(isnull(console.print_blueprint(record.id, null)), "A second print in the same shift should be refused.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - fee, "A refused second print should charge nothing.")
	var/datum/ship_plan/plan = disk.load_ship_plan()
	TEST_ASSERT(plan, "The disk should read its saved survey into a build plan.")
	TEST_ASSERT_EQUAL(plan.width, 3, "The rebuild plan should be as wide as the lost hull.")
	TEST_ASSERT_EQUAL(plan.height, 3, "The rebuild plan should be as tall as the lost hull.")
	qdel(disk)

	// What the fabricator leaves behind when the owner builds from that disk.
	var/obj/docking_port/mobile/rebuilt = build_fixture_hull(zone, "Lost Hull", owner_uuid)
	rebuilt.ship_registry_id = record.id
	TEST_ASSERT(console.run_survey(rebuilt, zone), "The rebuilt hull should survey: [console_says(console)]")
	TEST_ASSERT(console.file_hull(rebuilt, zone, null), "The rebuilt hull should file back in: [console_says(console)]")
	record = only_record(owner_uuid)
	TEST_ASSERT(record, "A rebuild should refile into the same record rather than add one.")
	TEST_ASSERT_EQUAL(record.status, SHIP_STATUS_FILED, "A rebuilt ship should be back in storage.")
	TEST_ASSERT_EQUAL(record.revision, 2, "A rebuilt ship should file as the next revision.")
	TEST_ASSERT_EQUAL(GLOB.ship_garage_slots.usage(owner_ckey)["used"], 1, "A rebuilt ship should use the slot it kept.")

/// Clearing a lost ship is what frees its slot.
/datum/unit_test/overmap_ship_persistence/clear_slot

/datum/unit_test/overmap_ship_persistence/clear_slot/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 0)
	var/owner_ckey = console.session.operator_ckey
	var/record_id = GLOB.ship_registry.insert_record(owner_uuid, owner_ckey, "Lost Hull")
	TEST_ASSERT(GLOB.ship_registry.store_revision(record_id, 1, "data/unit_test_ship_lost_[record_id].dmm", null, list(), 9, "Lost Hull", 100), "Storing a revision should succeed.")
	TEST_ASSERT(!console.clear_slot(record_id, null), "A stored ship cannot be cleared as lost.")
	var/datum/player_ship_record/row = GLOB.ship_registry.memory_rows["[record_id]"]
	row.status = SHIP_STATUS_LOST
	TEST_ASSERT_EQUAL(GLOB.ship_garage_slots.usage(owner_ckey)["used"], 1, "A lost ship should hold its slot.")
	TEST_ASSERT(console.clear_slot(record_id, null), "Clearing a lost ship should succeed: [console_says(console)]")
	TEST_ASSERT_EQUAL(GLOB.ship_garage_slots.usage(owner_ckey)["used"], 0, "Clearing should free the slot.")

// --- Broker -----------------------------------------------------------------

/// Bought for the garage: a revision 1 row, charged the listed price.
/datum/unit_test/overmap_ship_persistence/broker_garage

/datum/unit_test/overmap_ship_persistence/broker_garage/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_broker/broker = logged_in_broker(owner_uuid, 100000, null)
	var/datum/ship_listing/listing = shipyard_ship_listing("nt_personal")
	var/price = listing.purchase_price()
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	TEST_ASSERT(broker.purchase("nt_personal", "Test Purchase", "GARAGE", FALSE, null), "Buying for the garage should succeed: [broker_says(broker)]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - price, "A garage purchase should charge the hull and registration.")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT(record, "A purchase should leave one record.")
	TEST_ASSERT_EQUAL(record.status, SHIP_STATUS_FILED, "A garage purchase should be in storage.")
	TEST_ASSERT_EQUAL(record.revision, 1, "A purchase should be revision 1.")
	TEST_ASSERT_EQUAL(record.ship_name, "Test Purchase", "A purchase should carry the name the buyer chose.")
	TEST_ASSERT(fexists(record.map_path), "A purchase's map should be on disk at [record.map_path].")
	TEST_ASSERT_EQUAL(record.map_checksum, rustg_hash_file(RUSTG_HASH_SHA256, record.map_path), "A purchase's checksum should match its map.")

	// Nothing on offer that the buyer may not buy, and nothing bought through the gap.
	TEST_ASSERT(isnull(broker.purchase("blackmarket_burst", "Contraband", "GARAGE", FALSE, null)), "A restricted hull should not sell to an open buyer.")
	TEST_ASSERT_EQUAL(length(GLOB.ship_registry.list_for_owner(owner_uuid)), 1, "A refused purchase should leave no record.")

/// A listing whose hull never registers, standing in for a failed copy or registry write.
/datum/ship_listing/unit_test_unregistrable

/datum/ship_listing/unit_test_unregistrable/register_new_hull(owner_uuid, owner_ckey, ship_name, grant_id)
	return null

/// A sale that fails after the charge hands the money back, and can be paid again.
/datum/unit_test/overmap_ship_persistence/broker_refund

/datum/unit_test/overmap_ship_persistence/broker_refund/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_broker/broker = logged_in_broker(owner_uuid, 100000, null)
	var/datum/ship_listing/stock = shipyard_ship_listing("nt_personal")
	// No id at compile time, so the catalog never lists it outside this case.
	var/datum/ship_listing/unit_test_unregistrable/broken = new()
	broken.id = "unit_test_unregistrable"
	broken.name = "Unregistrable Hull"
	broken.template_type = stock.template_type
	GLOB.ship_listings[broken.id] = broken
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	var/first = broker.purchase(broken.id, "Doomed Sale", "GARAGE", FALSE, null)
	var/first_message = broker_says(broker)
	var/second = broker.purchase(broken.id, "Doomed Sale", "GARAGE", FALSE, null)
	var/balance_after = SScharacter_ledger.get_balance(owner_uuid)
	GLOB.ship_listings -= broken.id
	qdel(broken)
	TEST_ASSERT(isnull(first), "A sale whose hull cannot register should fail.")
	TEST_ASSERT(findtext(first_message, "refunded"), "A failed sale should say it was refunded, said '[first_message]'.")
	TEST_ASSERT(isnull(second), "The retry should fail the same way.")
	TEST_ASSERT_EQUAL(balance_after, balance_before, "Every failed sale should be refunded in full.")
	TEST_ASSERT(!length(GLOB.ship_registry.list_for_owner(owner_uuid)), "A failed sale should leave no record.")

/// A full garage refuses a sale before charging.
/datum/unit_test/overmap_ship_persistence/broker_full

/datum/unit_test/overmap_ship_persistence/broker_full/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_broker/broker = logged_in_broker(owner_uuid, 100000, null)
	fill_slots(broker.session.operator_ckey, CONFIG_GET(number/ship_garage_base_slots))
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	TEST_ASSERT(isnull(broker.purchase("nt_personal", "Nowhere To Go", "GARAGE", FALSE, null)), "A full garage should refuse a purchase.")
	TEST_ASSERT(findtext(broker_says(broker), "garage is full"), "The refusal should say the garage is full, said '[broker_says(broker)]'.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before, "A refused purchase should charge nothing.")
	TEST_ASSERT(!length(GLOB.ship_registry.list_for_owner(owner_uuid)), "A refused purchase should leave no record.")

/// Bought for the pad: charged, registered, and on the pad as an ordinary checkout.
/datum/unit_test/overmap_ship_persistence/broker_pad

/datum/unit_test/overmap_ship_persistence/broker_pad/Run()
	var/datum/ship_listing/listing = shipyard_ship_listing("nt_personal")
	var/datum/hull_profile/profile = listing.get_profile()
	TEST_ASSERT(profile, "The NT listing should have a hull profile.")
	var/side = max(profile.width, profile.height) + 2
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(side, side, side + 2)
	// The stock hull is mapped facing north, so this pad has to turn it.
	zone.exit_direction = EAST
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_broker/broker = logged_in_broker(owner_uuid, 100000, zone)
	var/price = listing.purchase_price()
	var/insurance = shipyard_insurance_fee(listing.get_salvage_estimate())
	var/balance_before = SScharacter_ledger.get_balance(owner_uuid)
	var/obj/docking_port/mobile/delivered = broker.purchase("nt_personal", "Pad Purchase", "PAD", TRUE, null)
	TEST_ASSERT(istype(delivered), "Buying onto a clear pad should land the hull: [broker_says(broker)]")
	hulls += delivered
	TEST_ASSERT(!broker.session.is_busy(), "The broker should let go of the console once the sale is done.")
	TEST_ASSERT_EQUAL(delivered.dir, EAST, "A hull set down on a pad should face the pad's exit.")
	var/list/bounds = delivered.return_coords()
	TEST_ASSERT(zone.contains_bbox(min(bounds[1], bounds[3]), min(bounds[2], bounds[4]), max(bounds[1], bounds[3]), max(bounds[2], bounds[4]), delivered.z), "A turned hull should still land inside the pad.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before - price - insurance, "An insured pad purchase should charge the price and the insurance.")
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT_EQUAL(record?.status, SHIP_STATUS_CHECKED_OUT, "A pad purchase should be checked out.")
	TEST_ASSERT(record.insured, "An insured pad purchase should leave the checkout insured.")
	TEST_ASSERT_EQUAL(delivered.ship_registry_id, record.id, "The delivered hull should remember its record.")
	TEST_ASSERT_EQUAL(delivered.ship_owner_id, owner_uuid, "The delivered hull should belong to the buyer.")

	// The pad is taken now, which is refused before any money moves.
	balance_before = SScharacter_ledger.get_balance(owner_uuid)
	TEST_ASSERT(isnull(broker.purchase("nt_personal", "Second Hull", "PAD", FALSE, null)), "An occupied pad should refuse a pad purchase.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(owner_uuid), balance_before, "A refused pad purchase should charge nothing.")

/// Every hull on the lot comes out of the garage once bought.
/datum/unit_test/overmap_ship_persistence/every_listing
	/// One pad per listing, released with the hulls standing on them.
	var/list/datum/turf_reservation/lot_reservations = list()

/datum/unit_test/overmap_ship_persistence/every_listing/Destroy()
	. = ..()
	QDEL_LIST(lot_reservations)

/datum/unit_test/overmap_ship_persistence/every_listing/Run()
	var/owner_uuid = generate_character_uuid()
	owner_uuids += owner_uuid
	var/datum/character_ledger_result/seed = SScharacter_ledger.try_credit(owner_uuid, 50000, LEDGER_CHANNEL_ADMIN_SEED, "every listing test seed", "test:lot:seed:[owner_uuid]")
	TEST_ASSERT(seed.success, "Seeding the test ledger should succeed, got '[seed.status]'.")
	var/owner_ckey = ckey("sptlot[REF(src)]")
	GLOB.ship_garage_slots.award_slots(owner_ckey, SHIP_SLOT_GRANT_ADMIN, "Every listing test", length(shipyard_ship_listings()), "tester")
	for(var/listing_id in shipyard_ship_listings())
		var/datum/ship_listing/listing = GLOB.ship_listings[listing_id]
		var/datum/hull_profile/profile = listing.get_profile()
		TEST_ASSERT(profile, "[listing_id] should read into a hull profile.")
		TEST_ASSERT(listing.listing_data(), "[listing_id] should describe itself to the catalog.")
		var/record_id = listing.register_new_hull(owner_uuid, owner_ckey, listing.name)
		TEST_ASSERT(record_id, "[listing_id] should register as a new hull.")
		var/datum/player_ship_record/record = GLOB.ship_registry.get_record(record_id, owner_uuid)

		var/side = max(profile.width, profile.height) + 2
		var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(side, side, side + 2)
		lot_reservations += pad_reservation
		pad_reservation = null
		var/datum/shipyard_delivery/delivery = shipyard_deliver_record(record, zone, FALSE, owner_uuid, null)
		TEST_ASSERT(delivery.success, "A bought [listing_id] should retrieve onto a pad that fits it: [delivery.message]")
		var/obj/docking_port/mobile/delivered = delivery.hull
		hulls += delivered
		TEST_ASSERT_EQUAL(delivered.ship_registry_id, record_id, "A retrieved [listing_id] should remember its record.")

// --- Hull profiles ----------------------------------------------------------

/// A stock map reads into a footprint the catalog can draw.
/datum/unit_test/overmap_ship_persistence/hull_profile

/datum/unit_test/overmap_ship_persistence/hull_profile/Run()
	var/datum/ship_listing/listing = shipyard_ship_listing("nt_personal")
	var/map_path = listing.map_path()
	var/datum/hull_profile/profile = shipyard_hull_profile(map_path)
	TEST_ASSERT(profile, "The NT hull should read into a profile.")
	TEST_ASSERT(profile.width > 0 && profile.height > 0, "A profile should have a footprint.")
	TEST_ASSERT_EQUAL(length(profile.cells), profile.width * profile.height, "A profile should have one cell per footprint tile.")
	TEST_ASSERT(profile.tiles > 0, "A profile should count its hull tiles.")
	TEST_ASSERT(profile.engines > 0, "The NT hull should have engines.")
	TEST_ASSERT_EQUAL(shipyard_hull_profile(map_path), profile, "Profiles should be cached per map.")
	var/list/silhouette = profile.silhouette_data()
	TEST_ASSERT_EQUAL(length(silhouette["cells"]), profile.width * profile.height, "A silhouette should cover the footprint.")
	var/top_filled = FALSE
	var/bottom_filled = FALSE
	var/left_filled = FALSE
	var/right_filled = FALSE
	for(var/index in 1 to length(profile.cells))
		if(!profile.cells[index])
			continue
		var/column = ((index - 1) % profile.width) + 1
		top_filled ||= index <= profile.width
		bottom_filled ||= index > length(profile.cells) - profile.width
		left_filled ||= column == 1
		right_filled ||= column == profile.width
	TEST_ASSERT(top_filled && bottom_filled && left_filled && right_filled, "The footprint should be cropped to the hull, not the map's space padding.")

/// A wrong PIN refuses a purchase; the matching PIN goes through.
/datum/unit_test/overmap_ship_persistence/pin_confirm

/datum/unit_test/overmap_ship_persistence/pin_confirm/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_broker/broker = logged_in_broker(owner_uuid, 100000, null)
	broker.session.operator_pin = 1234
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human/consistent)
	human.mind_initialize()
	TEST_ASSERT(!broker.session.require_pin(human, 9999), "A wrong PIN should be refused.")
	TEST_ASSERT(findtext(broker_says(broker), "Incorrect PIN"), "A wrong PIN should say so, said '[broker_says(broker)]'.")
	TEST_ASSERT(!length(GLOB.ship_registry.list_for_owner(owner_uuid)), "A refused PIN should not have sold anything.")
	TEST_ASSERT(broker.session.require_pin(human, 1234), "The matching PIN should be accepted.")
	TEST_ASSERT(broker.purchase("nt_personal", "Pin Ok", "GARAGE", FALSE, null), "After a matching PIN the sale should go through: [broker_says(broker)]")
	TEST_ASSERT(only_record(owner_uuid), "A matching PIN should leave a record.")

/// Closing the console, or walking out of range, logs the operator out.
/datum/unit_test/overmap_ship_persistence/walk_away

/datum/unit_test/overmap_ship_persistence/walk_away/Run()
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_broker/broker = logged_in_broker(owner_uuid, 100000, null)
	TEST_ASSERT(broker.authenticated, "The broker should start logged in.")
	broker.ui_close(null)
	TEST_ASSERT(!broker.authenticated, "The operator walking away should log the broker out.")

	var/obj/machinery/computer/ship_registrar/console = logged_in_console(generate_character_uuid(), 50000)
	TEST_ASSERT(console.authenticated, "The registrar should start logged in.")
	console.ui_close(null)
	TEST_ASSERT(!console.authenticated, "The operator walking away should log the registrar out.")

/// TRUE when every door button on `hull` still names a door on the same hull.
/datum/unit_test/overmap_ship_persistence/proc/buttons_reach_doors(obj/docking_port/mobile/hull)
	var/matched = 0
	for(var/turf/place as anything in hull.return_turfs())
		for(var/obj/machinery/button/door/button in place)
			if(!button.id)
				continue
			var/obj/item/assembly/control/control = button.device
			if(!istype(control) || !control.id)
				return FALSE
			var/found = FALSE
			for(var/turf/other as anything in hull.return_turfs())
				for(var/obj/machinery/door/airlock/airlock in other)
					if(airlock.id_tag == control.id)
						found = TRUE
						break
				if(found)
					break
				for(var/obj/machinery/door/poddoor/blast in other)
					if(blast.id == control.id)
						found = TRUE
						break
				if(found)
					break
			if(!found)
				return FALSE
			matched++
	return matched > 0

/// Buying, filing and retrieving a stock hull keeps its door buttons wired.
/datum/unit_test/overmap_ship_persistence/button_links

/datum/unit_test/overmap_ship_persistence/button_links/Run()
	var/datum/ship_listing/listing = shipyard_ship_listing("nt_personal")
	var/datum/hull_profile/profile = listing.get_profile()
	TEST_ASSERT(profile, "The NT listing should have a hull profile.")
	var/side = max(profile.width, profile.height) + 2
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(side, side, side + 2)
	var/owner_uuid = generate_character_uuid()
	var/obj/machinery/computer/ship_broker/broker = logged_in_broker(owner_uuid, 100000, zone)
	var/obj/docking_port/mobile/delivered = broker.purchase("nt_personal", "Linked Hull", "PAD", FALSE, null)
	TEST_ASSERT(istype(delivered), "Buying onto a clear pad should land the hull: [broker_says(broker)]")
	hulls += delivered
	TEST_ASSERT(buttons_reach_doors(delivered), "A freshly bought hull's door buttons should find their doors.")

	var/obj/machinery/computer/ship_registrar/console = logged_in_console(owner_uuid, 100000)
	TEST_ASSERT(console.run_survey(delivered, zone), "The bought hull should survey: [console_says(console)]")
	TEST_ASSERT(console.file_hull(delivered, zone, null), "The bought hull should file: [console_says(console)]")
	hulls -= delivered
	var/datum/player_ship_record/record = only_record(owner_uuid)
	TEST_ASSERT(record, "Filing should leave one record.")
	var/obj/docking_port/mobile/retrieved = console.retrieve_record(record.id, FALSE, zone, null)
	TEST_ASSERT(istype(retrieved), "The filed hull should retrieve: [console_says(console)]")
	hulls += retrieved
	TEST_ASSERT(buttons_reach_doors(retrieved), "A retrieved hull's door buttons should still find their doors.")
