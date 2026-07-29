/**
 * The whole persistent-ship loop, end to end and without a database.
 *
 * The registry is deliberately not part of this. Filing and retrieval are the
 * halves that can be quietly wrong - a hull that comes back missing a room, or
 * one that lands unregistered and unflyable - and both are exercisable with
 * nothing but a file path, which is why they take paths rather than records.
 *
 * The load path here is also the reason this test exists at all: it is a
 * deliberate parallel of `SSshuttle.action_load()`, and a parallel that nothing
 * drives will rot silently the next time upstream reorders that proc.
 *
 * Every assertion below is one physical line, however long that leaves it. A
 * macro call cannot be wrapped and still suit both parsers: DM continues a call
 * across lines only when the line ends in a comma, and StrongDMM reads that
 * comma as an extra empty argument and refuses to open the environment at all.
 * Where a message needs to name the value it is judging, the value goes in a
 * local first - which also stops the check and the message disagreeing.
 */
/datum/unit_test/overmap_shipyard_registrar
	priority = TEST_LONGER
	/// Where the landing zone lives, and with it the fixture hull at both ends.
	var/datum/turf_reservation/pad_reservation
	var/obj/docking_port/mobile/built_port
	var/obj/docking_port/mobile/retrieved_port
	var/export_path

/datum/unit_test/overmap_shipyard_registrar/Destroy()
	if(export_path)
		fdel(file(export_path))
	// Hand the hull turfs back to the areas they came from before releasing the
	// reservation. Dropping a port on its own leaves its turfs owned by a
	// shuttle area that nothing holds open any more.
	if(!QDELETED(built_port))
		built_port.jumpToNullSpace()
	if(!QDELETED(retrieved_port))
		retrieved_port.jumpToNullSpace()
	built_port = null
	retrieved_port = null
	QDEL_NULL(pad_reservation)
	return ..()

/**
 * Build a small hull with one of everything filing has to carry, then file it.
 *
 * Built inside the landing zone it will later be retrieved onto, because that is
 * where a printed hull is filed from in practice, and because a hull standing on
 * a Z no overmap object owns binds to a ship that reads as in flight - which
 * filing quite rightly refuses.
 *
 * Returns the teardown that described it, which is also the manifest the
 * retrieved hull is later compared against.
 */
/datum/unit_test/overmap_shipyard_registrar/proc/build_and_file_hull(
	obj/effect/landmark/overmap_landing_zone/zone,
	hull_name = "Registry Test Hull",
)
	// Inset from the zone corner, which is where the landmark and the overmap
	// level that owns this Z are both standing.
	var/origin_x = zone.x + 2
	var/origin_y = zone.y + 2
	var/origin_z = zone.z

	var/list/hull = list()
	for(var/offset_x in 0 to 2)
		for(var/offset_y in 0 to 2)
			var/turf/tile = locate(origin_x + offset_x, origin_y + offset_y, origin_z)
			hull += tile.ChangeTurf(/turf/open/floor/plating)
	built_port = create_shuttle(
		null,
		hull[1],
		hull,
		list(),
		NORTH,
		NORTH,
		area_type = /area/shuttle/custom,
		name = hull_name,
		id = "registrar_test_[REF(src)]",
	)
	TEST_ASSERT(built_port, "The fixture hull should register as a shuttle.")

	var/turf/chair_tile = locate(origin_x + 1, origin_y, origin_z)
	var/obj/structure/chair/comfy/shuttle/chair = allocate(/obj/structure/chair/comfy/shuttle, chair_tile)
	chair.setDir(EAST)
	var/turf/lockbox_tile = locate(origin_x, origin_y + 2, origin_z)
	var/obj/structure/closet/secure_closet/ship_lockbox/lockbox = allocate(/obj/structure/closet/secure_closet/ship_lockbox, lockbox_tile)
	allocate(/obj/item/stack/sheet/iron, lockbox)

	var/datum/ship_teardown/teardown = new(built_port)
	TEST_ASSERT(!teardown.refusal, "Teardown should accept the fixture hull, got '[teardown.refusal]'.")
	TEST_ASSERT_EQUAL(length(teardown.cells), 9, "Teardown should describe every tile of the fixture hull.")
	TEST_ASSERT_EQUAL(length(teardown.stored_contents), 1, "The lockbox payload is the only thing filing keeps.")
	var/file_refusal = shipyard_file_refusal(built_port, zone)
	TEST_ASSERT(!file_refusal, "An empty, idle, unclaimed hull sitting in its zone should be filable, got '[file_refusal]'.")

	export_path = "data/unit_test_ship_registrar_[REF(src)].dmm"
	var/written_to = shipyard_write_and_release(built_port, teardown, export_path)
	TEST_ASSERT_EQUAL(written_to, export_path, "Filing should write the hull to the path it was given.")
	TEST_ASSERT(fexists(export_path), "A filed hull should leave a map file behind.")
	TEST_ASSERT(QDELETED(built_port), "Filing a hull should take it out of the world.")
	built_port = null
	return teardown

/**
 * A landing zone big enough for the hull, somewhere nothing else is standing.
 *
 * The reservation is what keeps this off real station geometry, and its turfs are
 * plain space, which is one of the few types `dock_footprint_is_clear()` accepts.
 * The overmap level is what makes both ends resolve to somewhere: a ship only
 * reads as docked rather than in flight on a Z that some overmap object owns.
 */
/datum/unit_test/overmap_shipyard_registrar/proc/stage_landing_zone(zone_width, zone_height, reserve = 9)
	// Reserved generously and independently of the zone, so that a case which
	// widens the zone afterwards is still working inside turfs it owns.
	pad_reservation = SSmapping.request_turf_block_reservation(reserve, reserve, 1)
	TEST_ASSERT(pad_reservation, "The landing pad should reserve an isolated turf block.")
	var/turf/pad_corner = pad_reservation.bottom_left_turfs[1]
	TEST_ASSERT(pad_corner, "The pad reservation should provide a corner turf.")
	allocate(/obj/structure/overmap/level, pad_corner, "registrar_test_level_[REF(src)]", list(pad_corner.z))
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, pad_corner)
	zone.zone_name = "Registrar Test Pad"
	zone.zone_width = zone_width
	zone.zone_height = zone_height
	zone.dock_affiliation = null
	return zone

/// Every object path a teardown accounted for, sorted, as a comparable signature.
/datum/unit_test/overmap_shipyard_registrar/proc/manifest_signature(datum/ship_teardown/teardown)
	var/list/paths = list()
	for(var/cell_key in teardown.cells)
		var/list/cell = teardown.cells[cell_key]
		for(var/list/member as anything in cell["objects"])
			paths += "[member["path"]]"
	return jointext(sort_list(paths), ", ")

/datum/unit_test/overmap_shipyard_registrar/Run()
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/datum/ship_teardown/filed = build_and_file_hull(zone)
	TEST_ASSERT(filed, "The fixture hull should file before there is anything to retrieve.")

	var/registered_before = length(SSshuttle.mobile_docking_ports)
	retrieved_port = shipyard_retrieve_hull(export_path, "Registry Test Hull", zone, filed.stored_contents)
	TEST_ASSERT(retrieved_port, "A filed hull should be retrievable onto a zone that can contain it.")

	// Registered, and registered as what it was: a /custom port that never reaches
	// custom_shuttles has dead blueprints and does not count against the cap.
	TEST_ASSERT(retrieved_port in SSshuttle.mobile_docking_ports, "A retrieved hull should be a registered mobile port.")
	TEST_ASSERT_EQUAL(length(SSshuttle.mobile_docking_ports), registered_before + 1, "Retrieval should register exactly one port.")
	TEST_ASSERT(retrieved_port in SSshuttle.custom_shuttles, "A retrieved custom port should be listed as a custom shuttle.")
	TEST_ASSERT(length(retrieved_port.shuttle_areas), "A retrieved hull should own shuttle areas.")

	// The saved map carries no identity of its own, so the template's has to be
	// the one that stuck - otherwise a typed hull re-registers as a second copy
	// of whatever mapped ship its port type came from.
	TEST_ASSERT(findtext(retrieved_port.shuttle_id, "retrieved_"), "A retrieved hull should carry the id its template stamped on, got '[retrieved_port.shuttle_id]'.")
	TEST_ASSERT_EQUAL(retrieved_port.name, "Registry Test Hull", "A retrieved hull should carry its registered name.")

	var/list/landed = retrieved_port.return_coords()
	var/landed_x1 = min(landed[1], landed[3])
	var/landed_y1 = min(landed[2], landed[4])
	var/landed_x2 = max(landed[1], landed[3])
	var/landed_y2 = max(landed[2], landed[4])
	var/landed_inside = zone.contains_bbox(landed_x1, landed_y1, landed_x2, landed_y2, retrieved_port.z)
	var/landed_where = "landed across ([landed_x1],[landed_y1]) to ([landed_x2],[landed_y2]) on z [retrieved_port.z]"
	var/zone_where = "zone spans ([zone.x],[zone.y]) to ([zone.x + zone.zone_width - 1],[zone.y + zone.zone_height - 1]) on z [zone.z]"
	TEST_ASSERT(landed_inside, "A retrieved hull should come down entirely inside the zone it was called to: [landed_where], [zone_where].")

	// Asserted directly because a refused dock is quiet: the hull stays registered
	// and readable, just sitting in the staging reservation, and every check that
	// does not look at where it is standing still passes.
	var/obj/docking_port/stationary/landed_on = retrieved_port.get_docked()
	TEST_ASSERT(landed_on, "A retrieved hull should be docked to the pad it was called onto.")
	TEST_ASSERT_EQUAL(landed_on.name, zone.zone_name, "A retrieved hull should be docked to its zone's pad, not to '[landed_on.name]'.")

	// Flyable from the helm, which means bound to an overmap ship that knows it
	// has landed. `check_loc()` off the back of the docking move is what does it.
	var/obj/structure/overmap/ship/simulated/ship = retrieved_port.current_ship
	TEST_ASSERT(ship, "A retrieved hull should be bound to an overmap ship.")
	TEST_ASSERT_EQUAL(ship.state, OVERMAP_SHIP_IDLE, "A retrieved hull should read as docked rather than in flight, got '[ship.state]'.")

	var/obj/structure/closet/secure_closet/ship_lockbox/restored_lockbox
	for(var/turf/deck as anything in retrieved_port.return_turfs())
		if(!retrieved_port.shuttle_areas[deck.loc])
			continue
		for(var/obj/structure/closet/secure_closet/ship_lockbox/lockbox in deck)
			restored_lockbox = lockbox
			break
		if(restored_lockbox)
			break
	TEST_ASSERT(restored_lockbox, "A retrieved hull should still have the lockbox it was filed with.")
	var/restored_count = length(restored_lockbox.contents)
	TEST_ASSERT_EQUAL(restored_count, 1, "The lockbox should have been refilled from the manifest, holding [restored_count] thing(s).")

	// The point of the exercise: what came back describes the ship that went in.
	var/datum/ship_teardown/reflown = new(retrieved_port)
	TEST_ASSERT(!reflown.refusal, "A retrieved hull should tear down again, got '[reflown.refusal]'.")
	TEST_ASSERT_EQUAL(length(reflown.cells), length(filed.cells), "A retrieved hull should describe as many tiles as the one that was filed.")
	TEST_ASSERT_EQUAL(manifest_signature(reflown), manifest_signature(filed), "A retrieved hull should account for the same objects as the one that was filed.")
	TEST_ASSERT(!length(reflown.lost_detail), "A retrieved hull should lose no detail on the way back out: [jointext(reflown.lost_detail, "; ")]")
	qdel(reflown)
	qdel(filed)

/**
 * A retrieval that cannot fit has to refuse rather than run time, and has to
 * leave nothing behind when it does.
 *
 * Getting the ordering wrong here is how a player loses a ship: a load that
 * half-succeeds and then aborts would strand a hull in transit space and, if the
 * row were flipped first, mark it in service where nobody could ever reach it.
 * The proof is that the same file retrieves cleanly straight afterwards.
 */
/datum/unit_test/overmap_shipyard_registrar/refusal

/datum/unit_test/overmap_shipyard_registrar/refusal/Run()
	var/obj/effect/landmark/overmap_landing_zone/zone = stage_landing_zone(7, 7)
	var/datum/ship_teardown/filed = build_and_file_hull(zone, "Refusal Test Hull")
	TEST_ASSERT(filed, "The fixture hull should file before there is anything to refuse.")

	// Narrowed only once the hull is safely on disk: two by two cannot hold three
	// by three, and the pad port is where that is discovered - after the hull has
	// already been staged into transit space.
	zone.zone_width = 2
	zone.zone_height = 2

	var/registered_before = length(SSshuttle.mobile_docking_ports)
	var/obj/docking_port/mobile/refused = shipyard_retrieve_hull(export_path, "Refusal Test Hull", zone, filed.stored_contents)
	TEST_ASSERT(isnull(refused), "A hull too large for the zone should be refused, not landed.")
	TEST_ASSERT_EQUAL(length(SSshuttle.mobile_docking_ports), registered_before, "A refused retrieval should register nothing.")
	TEST_ASSERT(fexists(export_path), "A refused retrieval should leave the saved map alone.")

	// The retry is the real assertion: it can only pass if the refused attempt
	// released its reservation and took its staged hull with it.
	zone.zone_width = 7
	zone.zone_height = 7
	retrieved_port = shipyard_retrieve_hull(export_path, "Refusal Test Hull", zone, filed.stored_contents)
	TEST_ASSERT(retrieved_port, "A refusal should leave the ship retrievable once it has somewhere to go.")
	TEST_ASSERT(retrieved_port in SSshuttle.mobile_docking_ports, "The retried retrieval should produce a registered mobile port.")
	qdel(filed)
