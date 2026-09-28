// MODULE ID: OVERMAP
// Radar console payload cost.
//
// The console pushes its contact list to TGUI on autoupdate, and tgui_window.send_message() url-encodes
// the whole thing into a single `client << output(...)`. There is no server-to-client chunking, so one
// large payload is one large blocking write to the game client. Playtesting turned up client hitches as
// sweeps accumulated contacts, which is exactly the shape that failure would take.
//
// These measure the bytes that actually cross that pipe. The point is to make the cost a number that
// moves in CI rather than something only a playtest can feel.

/**
 * Encoded bytes a single push is allowed to reach, at any contact count.
 *
 * One batch of contacts plus the fixed keys. url_encode() turns every quote, colon and comma into
 * three bytes, so on a ten field entry the JSON punctuation costs more than the values do, which is
 * why a contact runs to a few hundred bytes and this budget looks generous for fifteen of them.
 */
#define RADAR_PUSH_BYTES_MAX 5000

/// Encoded bytes an update may spend on everything that is not the contact list. Anything that never
/// changes belongs in ui_static_data(), which is sent once, rather than in here, which is sent forever.
#define RADAR_FIXED_BYTES_MAX 400

/datum/unit_test/overmap_radar_payload
	abstract_type = /datum/unit_test/overmap_radar_payload

/// A powered console wired to a powered dish, which is the minimum that makes find_linked_dish() answer.
/datum/unit_test/overmap_radar_payload/proc/build_console(turf/stage)
	var/datum/powernet/grid = new
	var/obj/machinery/overmap_radar/dish/dish = allocate(/obj/machinery/overmap_radar/dish, stage)
	var/obj/machinery/computer/overmap_radar/console = allocate(/obj/machinery/computer/overmap_radar, stage)
	dish.forced_powernet = grid
	console.forced_powernet = grid
	dish.on = TRUE
	console.on = TRUE
	console.add_radar_link(dish)
	return console

/**
 * Drives `count` contacts onto `console` through the real packet path.
 *
 * Going through receive_radar_packet() rather than writing tracked_contacts directly is deliberate: it
 * is what applies the track labels, the last_seen stamps and the compression fields, so the payload we
 * then measure is the one an operator would actually be sent.
 */
/datum/unit_test/overmap_radar_payload/proc/feed_contacts(obj/machinery/computer/overmap_radar/console, count)
	var/datum/signal/overmap_radar/packet = new(null, SSovermap.main)
	packet.dest_console = console
	for(var/i in 1 to count)
		packet.contacts += list(list(
			"ref" = "contact_[i]",
			// Names and affiliations are the widest fields on a real contact, so keep them plausibly
			// wide here. Measuring with "a" would flatter the payload.
			"name" = "NTV Indefatigable [i]",
			"type" = "ship",
			"type_label" = "Frigate",
			"x" = 20 + (i % 40),
			"y" = 30 + (i % 30),
			"bearing" = (i * 7) % 360,
			"distance" = 4 + (i % 28),
			"affiliation" = OVERMAP_AFFILIATION_NT,
		))
	console.receive_radar_packet(packet, null)

/// Encoded size of an update for `console`, matching what TGUI_CREATE_MESSAGE() puts on the wire.
/datum/unit_test/overmap_radar_payload/proc/payload_bytes(obj/machinery/computer/overmap_radar/console)
	return length(url_encode(json_encode(console.ui_data(null))))

/// Encoded size of just the contact entries in an update, which is the part that scales with traffic.
/datum/unit_test/overmap_radar_payload/proc/contacts_bytes(obj/machinery/computer/overmap_radar/console)
	var/list/data = console.ui_data(null)
	return length(url_encode(json_encode(data["contacts"])))

/**
 * A single push stays small no matter how crowded the sector is.
 *
 * This is the property the whole design rests on. tgui_window writes a payload to the game client in
 * one blocking call, so what an operator feels is the largest single push, not the total traffic. The
 * console pays its contacts out a batch at a time precisely so this number stops tracking the contact
 * count. If it starts scaling again, batching has been bypassed somewhere.
 */
/datum/unit_test/overmap_radar_payload/push_size_is_bounded

/datum/unit_test/overmap_radar_payload/push_size_is_bounded/Run()
	var/turf/stage = run_loc_floor_bottom_left

	// An empty console still sends its whole non-contact key set, so this is the fixed floor.
	var/obj/machinery/computer/overmap_radar/empty_console = build_console(stage)
	var/fixed_bytes = payload_bytes(empty_console)
	log_test("[type]: fixed payload is [fixed_bytes] bytes with no contacts.")
	TEST_ASSERT(fixed_bytes <= RADAR_FIXED_BYTES_MAX, "An update with no contacts spends [fixed_bytes] bytes, over the [RADAR_FIXED_BYTES_MAX] budget. Values that do not change between updates belong in ui_static_data().")

	// Well past anything a sector should hold, to prove the ceiling is the batch and not the count.
	for(var/count in list(1, 10, 25, 50, 100, 200))
		// A console per count, so each measurement is independent rather than cumulative.
		var/obj/machinery/computer/overmap_radar/console = build_console(stage)
		feed_contacts(console, count)
		var/bytes = payload_bytes(console)
		var/sent = length(console.current_batch_ids())
		log_test("[type]: [count] contacts tracked -> [bytes] bytes carrying [sent] of them.")

		TEST_ASSERT(sent <= OVERMAP_RADAR_DRAIN_BATCH, "A push carried [sent] contacts, over the batch size of [OVERMAP_RADAR_DRAIN_BATCH].")
		TEST_ASSERT(bytes <= RADAR_PUSH_BYTES_MAX, "With [count] contacts tracked a single push was [bytes] bytes, over the [RADAR_PUSH_BYTES_MAX] budget. A push should carry one batch regardless of how many contacts exist.")

/**
 * Paying out in batches still has to deliver the whole picture, once.
 *
 * The saving is worthless if it loses or duplicates contacts. A dropped contact is an operator not
 * seeing a ship; a duplicated one would mean the interface is staging the same entry under two cycles
 * and could retire it at the wrong moment.
 *
 * Cursor advance is driven directly rather than through its timer, so this tests the payout logic
 * without depending on timer subsystem scheduling inside a unit test.
 */
/datum/unit_test/overmap_radar_payload/drain_delivers_every_contact_once

/datum/unit_test/overmap_radar_payload/drain_delivers_every_contact_once/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/machinery/computer/overmap_radar/console = build_console(stage)

	var/expected = 100
	feed_contacts(console, expected)
	TEST_ASSERT_EQUAL(length(console.tracked_contacts), expected, "The fixture should be holding all [expected] contacts before the payout is walked.")

	var/list/seen = list()
	var/batches = 0
	// Generous bound purely so a cursor bug fails the assertions below instead of hanging the suite.
	while(batches++ <= expected)
		for(var/contact_id in console.current_batch_ids())
			TEST_ASSERT(!seen[contact_id], "Contact [contact_id] was delivered in more than one batch.")
			seen[contact_id] = TRUE
		if(console.drain_complete())
			break
		console.advance_drain()

	log_test("[type]: [expected] contacts were paid out in [batches] batches.")
	TEST_ASSERT_EQUAL(length(seen), expected, "The payout delivered [length(seen)] of [expected] contacts. Every tracked contact has to appear in exactly one batch.")
	for(var/contact_id in console.tracked_contacts)
		TEST_ASSERT(seen[contact_id], "Tracked contact [contact_id] was never delivered by the payout.")

/**
 * Re-sweeping a sector the console already knows must not make its updates any bigger.
 *
 * This is the playtested symptom. Successive sweeps over the same contacts change nothing an operator
 * can see, so if the payload grows anyway then something is being re-minted or accumulated per sweep
 * and every subsequent update pays for it.
 */
/datum/unit_test/overmap_radar_payload/resweep_does_not_grow_payload

/datum/unit_test/overmap_radar_payload/resweep_does_not_grow_payload/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/machinery/computer/overmap_radar/console = build_console(stage)

	feed_contacts(console, 25)
	// The contact entries only, because the payout cycle counter legitimately widens as it climbs and
	// that has nothing to do with whether contacts are costing more to describe.
	var/first_bytes = contacts_bytes(console)
	var/first_contacts = length(console.tracked_contacts)

	// Twenty more sweeps of the identical sector, which is a couple of minutes of station time.
	for(var/i in 1 to 20)
		feed_contacts(console, 25)

	var/settled_bytes = contacts_bytes(console)
	log_test("[type]: 25 contacts cost [first_bytes] contact bytes on the first sweep and [settled_bytes] after 21 sweeps.")

	TEST_ASSERT_EQUAL(length(console.tracked_contacts), first_contacts, "Re-sweeping the same sector must not add tracked contacts; the same refs should be updated in place.")
	TEST_ASSERT_EQUAL(settled_bytes, first_bytes, "Re-sweeping the same sector grew the contact payload from [first_bytes] to [settled_bytes] bytes. Nothing an operator can see changed, so nothing on the wire should have either.")

/**
 * Building an update must not drop contacts.
 *
 * The payout order is a snapshot taken when the cycle opens, so anything that removes a contact has
 * to reopen the cycle or the order is left pointing at an id with nothing behind it. ui_data() is not
 * in a position to do that — it runs on every push, including ones the drain did not ask for — so it
 * has no business pruning. Decay belongs to process(), which restarts the cycle when it takes one.
 */
/datum/unit_test/overmap_radar_payload/update_does_not_prune

/datum/unit_test/overmap_radar_payload/update_does_not_prune/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/machinery/computer/overmap_radar/console = build_console(stage)

	feed_contacts(console, 25)
	var/contact_id = console.current_batch_ids()[1]
	console.tracked_contacts[contact_id]["last_seen"] = world.time - OVERMAP_SCAN_DECAY - 1

	console.ui_data(null)

	TEST_ASSERT(console.tracked_contacts[contact_id], "Building an update dropped decayed contact [contact_id]. Removing a contact desyncs the payout order from the contact list, and an update is in no position to reopen the cycle.")

/**
 * A contact that goes away mid-cycle costs a dot, not the console.
 *
 * Whatever reopens the cycle cannot do so before the contact is already gone, so there is always a
 * moment where the payout order names something no longer tracked. The interface stages its batches
 * inside a state update, which means a null in the contact array is not a missing contact — it is an
 * unhandled throw during render, and the operator gets a fatal exception in place of their radar.
 */
/datum/unit_test/overmap_radar_payload/payout_survives_a_dropped_contact

/datum/unit_test/overmap_radar_payload/payout_survives_a_dropped_contact/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/machinery/computer/overmap_radar/console = build_console(stage)

	feed_contacts(console, 25)
	var/list/batch = console.current_batch_ids()
	var/expected = length(batch)
	TEST_ASSERT(expected > 1, "The fixture needs a batch of more than one contact for a dropped one to be distinguishable.")

	// Decay a contact the open cycle has already promised to deliver, then take it the way process()
	// would, leaving the order naming an id the console no longer holds.
	var/contact_id = batch[1]
	console.tracked_contacts[contact_id]["last_seen"] = world.time - OVERMAP_SCAN_DECAY - 1
	TEST_ASSERT(console.prune_contacts(), "Ageing a contact past the decay window should have let prune_contacts() drop it.")
	TEST_ASSERT(contact_id in console.drain_order, "The payout order should still name the dropped contact; this test is meaningless if it does not.")

	var/list/data = console.ui_data(null)
	var/list/contacts = data["contacts"]

	TEST_ASSERT_EQUAL(length(contacts), expected - 1, "The push carried [length(contacts)] contacts where [expected - 1] survive the drop. A dropped contact should leave the batch one short, not leave a placeholder behind.")
	for(var/list/entry as anything in contacts)
		TEST_ASSERT(!isnull(entry), "A push carried a null contact entry, which is a fatal exception in the interface rather than a missing contact.")
		TEST_ASSERT(entry["id"] != contact_id, "The push carried dropped contact [contact_id].")

#undef RADAR_PUSH_BYTES_MAX
#undef RADAR_FIXED_BYTES_MAX
