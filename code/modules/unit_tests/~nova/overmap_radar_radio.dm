// MODULE ID: OVERMAP
// Radar packet path, shared-powernet gate, antenna cipher copy, keyed intercom craft.

/datum/unit_test/overmap_radar_processor_cleans

/datum/unit_test/overmap_radar_processor_cleans/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/datum/powernet/grid = new
	var/obj/machinery/overmap_radar/dish/dish = allocate(/obj/machinery/overmap_radar/dish, stage)
	var/obj/machinery/overmap_radar/processor/processor = allocate(/obj/machinery/overmap_radar/processor, stage)
	var/obj/machinery/computer/overmap_radar/console = allocate(/obj/machinery/computer/overmap_radar, stage)
	dish.forced_powernet = grid
	processor.forced_powernet = grid
	console.forced_powernet = grid
	dish.on = TRUE
	processor.on = TRUE
	console.on = TRUE
	dish.add_radar_link(processor)
	console.add_radar_link(processor)

	var/datum/signal/overmap_radar/packet = new(dish, SSovermap.main)
	packet.compression = OVERMAP_RADAR_DEFAULT_COMPRESSION
	packet.contacts += list(list(
		"ref" = "test",
		"name" = "Contact Alpha",
		"type" = "ship",
		"x" = 10,
		"y" = 12,
		"bearing" = 90,
		"distance" = 4,
		"affiliation" = OVERMAP_AFFILIATION_NT,
	))
	processor.receive_radar_packet(packet, dish)
	TEST_ASSERT_EQUAL(packet.compression, 0, "Processor should zero packet compression.")
	TEST_ASSERT(console.tracked_contacts["test"], "Console should store the cleaned contact.")
	TEST_ASSERT_EQUAL(console.tracked_contacts["test"]["name"], "Contact Alpha", "Clean packet should keep the contact name.")
	TEST_ASSERT_EQUAL(console.tracked_contacts["test"]["track"], "T1", "New contacts should receive a default track number.")

/datum/unit_test/overmap_radar_powernet_gate

/datum/unit_test/overmap_radar_powernet_gate/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/datum/powernet/dish_net = new
	var/datum/powernet/foc_net = new
	var/obj/machinery/overmap_radar/dish/dish = allocate(/obj/machinery/overmap_radar/dish, stage)
	var/obj/machinery/overmap_radar/processor/processor = allocate(/obj/machinery/overmap_radar/processor, stage)
	dish.forced_powernet = dish_net
	processor.forced_powernet = foc_net
	dish.on = TRUE
	processor.on = TRUE
	dish.add_radar_link(processor)
	TEST_ASSERT(!dish.shares_powernet_with(processor), "Different powernets must not share.")
	var/datum/signal/overmap_radar/packet = new(dish, SSovermap.main)
	packet.compression = OVERMAP_RADAR_DEFAULT_COMPRESSION
	TEST_ASSERT_EQUAL(dish.relay_radar_packet(packet, /obj/machinery/overmap_radar/processor), 0, "Linked machines on different powernets must not relay.")

/datum/unit_test/overmap_radar_uncompressed_without_processor

/datum/unit_test/overmap_radar_uncompressed_without_processor/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/datum/powernet/grid = new
	var/obj/machinery/overmap_radar/dish/dish = allocate(/obj/machinery/overmap_radar/dish, stage)
	var/obj/machinery/computer/overmap_radar/console = allocate(/obj/machinery/computer/overmap_radar, stage)
	dish.forced_powernet = grid
	console.forced_powernet = grid
	dish.on = TRUE
	console.on = TRUE
	console.add_radar_link(dish)
	var/datum/signal/overmap_radar/packet = new(dish, SSovermap.main)
	packet.compression = OVERMAP_RADAR_DEFAULT_COMPRESSION
	packet.contacts += list(list(
		"ref" = "garbled",
		"name" = "Contact Beta",
		"type" = "ship",
		"x" = 8,
		"y" = 8,
		"bearing" = 0,
		"distance" = 2,
		"affiliation" = OVERMAP_AFFILIATION_NT,
	))
	dish.relay_radar_packet(packet, /obj/machinery/computer/overmap_radar)
	TEST_ASSERT(console.tracked_contacts["garbled"], "Console should still receive a compressed packet.")
	TEST_ASSERT(console.tracked_contacts["garbled"]["compression"] > 0, "Missing processor should leave compression in place.")

/datum/unit_test/overmap_radio_cipher_copy

/datum/unit_test/overmap_radio_cipher_copy/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/machinery/overmap_radio/antenna/source = allocate(/obj/machinery/overmap_radio/antenna, stage)
	var/obj/machinery/overmap_radio/antenna/target = allocate(/obj/machinery/overmap_radio/antenna, stage)
	TEST_ASSERT(source.network_cipher, "Source antenna should generate a cipher.")
	TEST_ASSERT(target.network_cipher, "Target antenna should generate a cipher.")
	TEST_ASSERT(source.network_cipher != target.network_cipher, "Fresh antennas should not share a cipher.")
	target.network_cipher = source.network_cipher
	TEST_ASSERT_EQUAL(target.network_cipher, source.network_cipher, "Copied antenna cipher should match.")

	var/obj/item/encryptionkey/overmap/key = allocate(/obj/item/encryptionkey/overmap, stage)
	TEST_ASSERT(key.stamp_from_antenna(source), "Blank key should accept an antenna cipher.")
	TEST_ASSERT_EQUAL(key.network_cipher, source.network_cipher, "Stamped key should carry the antenna cipher.")
	TEST_ASSERT(key.channels[RADIO_CHANNEL_OVERMAP], "Stamped key should grant the overmap channel.")

	var/obj/item/radio/radio = allocate(/obj/item/radio, stage)
	radio.keyslot = key
	radio.recalculateChannels()
	TEST_ASSERT_EQUAL(radio.overmap_cipher, source.network_cipher, "Radio should inherit the key cipher.")

/datum/unit_test/overmap_radio_cipher_hear

/datum/unit_test/overmap_radio_cipher_hear/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/item/radio/open_radio = allocate(/obj/item/radio, stage)
	var/obj/item/radio/cipher_a = allocate(/obj/item/radio, stage)
	var/obj/item/radio/cipher_b = allocate(/obj/item/radio, stage)
	cipher_a.overmap_cipher = "alpha"
	cipher_b.overmap_cipher = "bravo"
	TEST_ASSERT(open_radio.can_hear_overmap_cipher(null), "Unencrypted traffic should be audible to any radio.")
	TEST_ASSERT(cipher_a.can_hear_overmap_cipher(null), "Ciphered radios should still hear unencrypted traffic.")
	TEST_ASSERT(cipher_a.can_hear_overmap_cipher("alpha"), "Matching cipher should hear.")
	TEST_ASSERT(!cipher_a.can_hear_overmap_cipher("bravo"), "Mismatched cipher should not hear.")
	TEST_ASSERT(!cipher_b.can_hear_overmap_cipher("alpha"), "Mismatched cipher should not hear.")

/datum/unit_test/overmap_keyed_intercom_craft

/datum/unit_test/overmap_keyed_intercom_craft/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/item/wallframe/intercom/frame = allocate(/obj/item/wallframe/intercom, stage)
	var/obj/item/encryptionkey/overmap/key = allocate(/obj/item/encryptionkey/overmap, stage)
	key.channels = list(RADIO_CHANNEL_OVERMAP = 1)
	key.programmed = TRUE
	var/obj/item/radio/intercom/unscrewed/intercom = allocate(/obj/item/radio/intercom/unscrewed, stage)
	intercom.on_craft_completion(list(frame, key), new /datum/crafting_recipe/keyed_intercom, null)
	TEST_ASSERT(intercom.keyslot == key, "Crafted intercom should install the supplied encryption key.")
	TEST_ASSERT(intercom.channels[RADIO_CHANNEL_OVERMAP], "Crafted intercom should expose the overmap channel.")

/// Console aim (0=north, clockwise) must persist, scale range, and select the matching cone.
/datum/unit_test/overmap_radar_console_sweep_aim

/datum/unit_test/overmap_radar_console_sweep_aim/Run()
	var/obj/structure/overmap/origin = SSovermap.main
	TEST_ASSERT(origin, "Station overmap object should exist.")
	var/turf/north_turf = locate(origin.x, origin.y + 3, origin.z)
	var/turf/east_turf = locate(origin.x + 3, origin.y, origin.z)
	TEST_ASSERT(north_turf, "Missing north test turf.")
	TEST_ASSERT(east_turf, "Missing east test turf.")

	var/obj/structure/overmap/ship/north_ship = allocate(/obj/structure/overmap/ship, north_turf)
	var/obj/structure/overmap/ship/east_ship = allocate(/obj/structure/overmap/ship, east_turf)
	north_ship.name = "Radar North Probe"
	east_ship.name = "Radar East Probe"

	TEST_ASSERT_EQUAL(get_bearing_to(origin, north_ship), 0, "North contact must be bearing 0 (0=north, clockwise).")
	TEST_ASSERT_EQUAL(get_bearing_to(origin, east_ship), 90, "East contact must be bearing 90 (0=north, clockwise).")

	TEST_ASSERT_EQUAL(overmap_radar_range_for_arc(OVERMAP_RADAR_MIN_ARC), OVERMAP_RADAR_NARROW_RANGE, "Narrowest arc should use long range.")
	TEST_ASSERT_EQUAL(overmap_radar_range_for_arc(360), OVERMAP_RADAR_WIDE_RANGE, "Full sweep should use short range.")
	TEST_ASSERT(overmap_radar_range_for_arc(OVERMAP_RADAR_MIN_ARC) > overmap_radar_range_for_arc(180), "Narrower arc should reach farther.")

	var/turf/stage = run_loc_floor_bottom_left
	var/datum/powernet/grid = new
	var/obj/machinery/overmap_radar/dish/dish = allocate(/obj/machinery/overmap_radar/dish, stage)
	var/obj/machinery/computer/overmap_radar/console = allocate(/obj/machinery/computer/overmap_radar, stage)
	dish.forced_powernet = grid
	console.forced_powernet = grid
	dish.on = TRUE
	console.on = TRUE
	console.add_radar_link(dish)

	TEST_ASSERT_EQUAL(console.ui_number(list("bearing" = 90), "bearing"), 90, "Numeric slider payload should parse.")
	TEST_ASSERT_EQUAL(console.ui_number(list("bearing" = "45"), "bearing"), 45, "String slider payload should parse.")
	TEST_ASSERT_NULL(console.ui_number(list("bearing" = "nope"), "bearing"), "Non-numeric payload should be rejected.")

	console.sweep_bearing = SIMPLIFY_DEGREES(console.ui_number(list("bearing" = 0), "bearing"))
	console.sweep_arc = clamp(console.ui_number(list("arc" = 60), "arc"), OVERMAP_RADAR_MIN_ARC, 360)
	var/list/ui = console.ui_data(null)
	TEST_ASSERT_EQUAL(ui["bearing"], 0, "ui_data should echo the aimed bearing.")
	TEST_ASSERT_EQUAL(ui["arcWidth"], 60, "ui_data should echo the aimed arc.")
	TEST_ASSERT_EQUAL(ui["range"], overmap_radar_range_for_arc(60), "ui_data range should follow the aimed arc.")
	TEST_ASSERT(ui["hasDish"], "Linked dish on the same powernet should be visible to the console.")

	var/list/aimed = origin.gather_radar_contacts(10, console.sweep_bearing, console.sweep_arc)
	TEST_ASSERT(north_ship in aimed, "Bearing 0 / arc 60 must include the north probe.")
	TEST_ASSERT(!(east_ship in aimed), "Bearing 0 / arc 60 must exclude the east probe.")

	var/datum/signal/overmap_radar/packet = dish.sweep(console.sweep_bearing, console.sweep_arc)
	TEST_ASSERT(packet, "Dish sweep should emit a packet.")
	TEST_ASSERT_EQUAL(packet.bearing, 0, "Sweep packet should keep the console bearing.")
	TEST_ASSERT_EQUAL(packet.arc_width, 60, "Sweep packet should keep the console arc.")
	var/found_north = FALSE
	var/found_east = FALSE
	for(var/list/contact as anything in packet.contacts)
		if(contact["ref"] == REF(north_ship))
			found_north = TRUE
		if(contact["ref"] == REF(east_ship))
			found_east = TRUE
	TEST_ASSERT(found_north, "Dish sweep at bearing 0 must report the north probe.")
	TEST_ASSERT(!found_east, "Dish sweep at bearing 0 must not report the east probe.")
	TEST_ASSERT(console.tracked_contacts[REF(north_ship)], "Console should store the north probe after sweep.")

/// Each console keeps its own tracks and only receives sweeps it requested.
/datum/unit_test/overmap_radar_console_independent_tracks

/datum/unit_test/overmap_radar_console_independent_tracks/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/datum/powernet/grid = new
	var/obj/machinery/overmap_radar/dish/dish = allocate(/obj/machinery/overmap_radar/dish, stage)
	var/obj/machinery/overmap_radar/processor/processor = allocate(/obj/machinery/overmap_radar/processor, stage)
	var/obj/machinery/computer/overmap_radar/console_a = allocate(/obj/machinery/computer/overmap_radar, stage)
	var/obj/machinery/computer/overmap_radar/console_b = allocate(/obj/machinery/computer/overmap_radar, stage)
	dish.forced_powernet = grid
	processor.forced_powernet = grid
	console_a.forced_powernet = grid
	console_b.forced_powernet = grid
	dish.on = TRUE
	processor.on = TRUE
	console_a.on = TRUE
	console_b.on = TRUE
	dish.add_radar_link(processor)
	console_a.add_radar_link(processor)
	console_b.add_radar_link(processor)

	var/datum/signal/overmap_radar/packet = new(dish, SSovermap.main)
	packet.dest_console = console_a
	packet.contacts += list(list(
		"ref" = "alpha",
		"name" = "Contact Alpha",
		"type" = "ship",
		"x" = 10,
		"y" = 12,
		"bearing" = 90,
		"distance" = 4,
		"affiliation" = OVERMAP_AFFILIATION_NT,
	))
	processor.receive_radar_packet(packet, dish)
	TEST_ASSERT(console_a.tracked_contacts["alpha"], "Requesting console should receive its own sweep.")
	TEST_ASSERT_EQUAL(console_a.tracked_contacts["alpha"]["track"], "T1", "First contact should be tagged T1.")
	TEST_ASSERT(!console_b.tracked_contacts["alpha"], "A second console must not inherit another console's sweep.")

	TEST_ASSERT(console_a.track_label_in_use("T1", "other"), "Assigned track labels should count as in use.")
	console_a.manual_tracks["alpha"] = "BANDIT"
	console_a.track_labels["alpha"] = "BANDIT"
	console_a.tracked_contacts["alpha"]["track"] = "BANDIT"
	var/list/ui = console_a.ui_data(null)
	var/list/rows = ui["contacts"]
	TEST_ASSERT(length(rows), "ui_data should list tracked contacts.")
	TEST_ASSERT_EQUAL(rows[1]["track"], "BANDIT", "Operator track edits should appear in ui_data.")
	TEST_ASSERT(console_a.track_label_in_use("BANDIT", "bravo"), "Renamed tracks should stay unique.")
	TEST_ASSERT(!console_a.track_label_in_use("BANDIT", "alpha"), "A contact may keep its own track label.")

/// Auto track serials keep incrementing across sweeps; operator names persist.
/datum/unit_test/overmap_radar_track_serial_cumulative

/datum/unit_test/overmap_radar_track_serial_cumulative/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/datum/powernet/grid = new
	var/obj/machinery/overmap_radar/dish/dish = allocate(/obj/machinery/overmap_radar/dish, stage)
	var/obj/machinery/overmap_radar/processor/processor = allocate(/obj/machinery/overmap_radar/processor, stage)
	var/obj/machinery/computer/overmap_radar/console = allocate(/obj/machinery/computer/overmap_radar, stage)
	dish.forced_powernet = grid
	processor.forced_powernet = grid
	console.forced_powernet = grid
	dish.on = TRUE
	processor.on = TRUE
	console.on = TRUE
	dish.add_radar_link(processor)
	console.add_radar_link(processor)

	var/datum/signal/overmap_radar/first = new(dish, SSovermap.main)
	first.dest_console = console
	first.contacts += list(list(
		"ref" = "alpha",
		"name" = "Contact Alpha",
		"type" = "ship",
		"x" = 10,
		"y" = 12,
		"bearing" = 90,
		"distance" = 4,
		"affiliation" = OVERMAP_AFFILIATION_NT,
	))
	processor.receive_radar_packet(first, dish)
	TEST_ASSERT_EQUAL(console.tracked_contacts["alpha"]["track"], "T1", "First sweep should mint T1.")

	var/datum/signal/overmap_radar/second = new(dish, SSovermap.main)
	second.dest_console = console
	second.contacts += list(list(
		"ref" = "alpha",
		"name" = "Contact Alpha",
		"type" = "ship",
		"x" = 11,
		"y" = 12,
		"bearing" = 90,
		"distance" = 5,
		"affiliation" = OVERMAP_AFFILIATION_NT,
	))
	processor.receive_radar_packet(second, dish)
	TEST_ASSERT_EQUAL(console.tracked_contacts["alpha"]["track"], "T2", "A later sweep should mint T2, not reuse T1.")
	TEST_ASSERT_EQUAL(console.next_track_index, 3, "The auto-track serial should only move forward.")

	console.manual_tracks["alpha"] = "BANDIT"
	console.track_labels["alpha"] = "BANDIT"
	var/datum/signal/overmap_radar/third = new(dish, SSovermap.main)
	third.dest_console = console
	third.contacts += list(
		list(
			"ref" = "alpha",
			"name" = "Contact Alpha",
			"type" = "ship",
			"x" = 11,
			"y" = 12,
			"bearing" = 90,
			"distance" = 5,
			"affiliation" = OVERMAP_AFFILIATION_NT,
		),
		list(
			"ref" = "bravo",
			"name" = "Contact Bravo",
			"type" = "ship",
			"x" = 14,
			"y" = 8,
			"bearing" = 120,
			"distance" = 7,
			"affiliation" = OVERMAP_AFFILIATION_NT,
		),
	)
	processor.receive_radar_packet(third, dish)
	TEST_ASSERT_EQUAL(console.tracked_contacts["alpha"]["track"], "BANDIT", "Operator track names should survive later sweeps.")
	TEST_ASSERT_EQUAL(console.tracked_contacts["bravo"]["track"], "T3", "A new contact on a later sweep should continue the serial.")
