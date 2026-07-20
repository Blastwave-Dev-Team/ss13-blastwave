// MODULE ID: OVERMAP
// Landing zone controller access tiers, board programming, and faction dock filtering.

/datum/unit_test/overmap_landing_controller
	abstract_type = /datum/unit_test/overmap_landing_controller

/datum/unit_test/overmap_landing_controller/Destroy()
	for(var/obj/docking_port/port in allocated.Copy())
		if(!QDELETED(port))
			qdel(port, force = TRUE)
	return ..()

/datum/unit_test/overmap_landing_controller/access_tiers

/datum/unit_test/overmap_landing_controller/access_tiers/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human/consistent, stage)
	subject.equipOutfit(/datum/outfit/job/assistant/consistent)
	var/obj/item/card/id/advanced/keycard = subject.wear_id

	var/obj/machinery/computer/landing_controller/unlocked = allocate(/obj/machinery/computer/landing_controller, stage)
	var/obj/machinery/computer/landing_controller/nanotrasen/nt = allocate(/obj/machinery/computer/landing_controller/nanotrasen, stage)
	var/obj/machinery/computer/landing_controller/programmable/prog = allocate(/obj/machinery/computer/landing_controller/programmable, stage)

	TEST_ASSERT_EQUAL(unlocked.dock_affiliation, null, "Unlocked controller should leave dock affiliation open.")
	TEST_ASSERT_EQUAL(nt.dock_affiliation, OVERMAP_AFFILIATION_NT, "Nanotrasen controller should stamp NT dock affiliation.")
	TEST_ASSERT_EQUAL(prog.dock_affiliation, null, "Unprogrammed programmable controller should leave dock affiliation open.")
	TEST_ASSERT_EQUAL(prog.icon_screen, "shuttle", "Unprogrammed programmable controller should use the normal shuttle monitor.")

	keycard.access = list()
	TEST_ASSERT(unlocked.allowed(subject), "Unlocked controller should allow anyone.")
	TEST_ASSERT(!nt.allowed(subject), "Nanotrasen controller should deny assistants without command/engineering.")

	keycard.access = list(ACCESS_ENGINEERING)
	TEST_ASSERT(nt.allowed(subject), "Nanotrasen controller should allow engineering access.")
	TEST_ASSERT(prog.allowed(subject), "Unprogrammed programmable controller should allow anyone.")

	var/obj/item/circuitboard/computer/landing_controller/programmable/board = allocate(/obj/item/circuitboard/computer/landing_controller/programmable, stage)
	TEST_ASSERT_EQUAL(board.program_mode, LANDING_CONTROLLER_LOCK_FACTION, "Board should default to faction mode.")
	TEST_ASSERT_EQUAL(get_id_overmap_faction(keycard), OVERMAP_AFFILIATION_NT, "Station job ID should resolve as NT.")

	TEST_ASSERT_EQUAL(board.item_interaction(subject, keycard), ITEM_INTERACT_SUCCESS, "Faction swipe should program the board.")
	TEST_ASSERT_EQUAL(board.stored_dock_affiliation, OVERMAP_AFFILIATION_NT, "Station ID should store NT faction on the board.")

	prog.circuit = board
	prog.apply_board_program()
	TEST_ASSERT_EQUAL(prog.lock_mode, LANDING_CONTROLLER_LOCK_FACTION, "Applied board should set faction lock mode.")
	TEST_ASSERT_EQUAL(prog.dock_affiliation, OVERMAP_AFFILIATION_NT, "Applied board should lock the pad to NT.")
	TEST_ASSERT(prog.allowed(subject), "Matching faction ID should be allowed on the console.")

	var/obj/item/card/id/advanced/blank = allocate(/obj/item/card/id/advanced, stage)
	blank.access = list(ACCESS_CARGO)
	subject.wear_id = blank
	TEST_ASSERT(!prog.allowed(subject), "Non-faction ID should be denied on a faction-locked console.")
	subject.wear_id = keycard

	TEST_ASSERT_EQUAL(board.item_interaction(subject, keycard), ITEM_INTERACT_SUCCESS, "Matching faction swipe should clear the board.")
	TEST_ASSERT(!board.is_programmed(), "Cleared board should be unprogrammed.")
	prog.apply_board_program()
	TEST_ASSERT_EQUAL(prog.dock_affiliation, null, "Cleared board should reopen docking.")

	keycard.access |= ACCESS_SYNDICATE
	SSid_access.apply_trim_to_card(keycard, /datum/id_trim/syndicom/nova/ds2/syndicatestaff)
	TEST_ASSERT_EQUAL(get_id_overmap_faction(keycard), OVERMAP_AFFILIATION_DS2, "DS2 trim should resolve as DS2.")
	TEST_ASSERT_EQUAL(board.item_interaction(subject, keycard), ITEM_INTERACT_SUCCESS, "Syndicate swipe should program the board.")
	prog.apply_board_program()
	TEST_ASSERT_EQUAL(prog.dock_affiliation, OVERMAP_AFFILIATION_DS2, "Syndicate board program should lock the pad to DS2.")
	TEST_ASSERT_EQUAL(prog.icon_screen, "emagged_general", "Syndicate-configured console should use the emagged red monitor.")

	board.clear_program()
	prog.apply_board_program()
	TEST_ASSERT(prog.emag_act(null, null), "Emagging a programmable landing controller should succeed.")
	TEST_ASSERT(prog.obj_flags & EMAGGED, "Programmable controller should be marked emagged.")
	TEST_ASSERT_EQUAL(prog.dock_affiliation, OVERMAP_AFFILIATION_DS2, "Emag should lock the pad to DS2.")
	TEST_ASSERT_EQUAL(prog.icon_screen, "emagged_general", "Emagged programmable console should use the red monitor.")
	TEST_ASSERT(prog.allowed(subject), "Emagged console should allow login.")

/datum/unit_test/overmap_landing_controller/board_modes

/datum/unit_test/overmap_landing_controller/board_modes/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/mob/living/carbon/human/subject = allocate(/mob/living/carbon/human/consistent, stage)
	subject.equipOutfit(/datum/outfit/job/assistant/consistent)
	var/obj/item/card/id/advanced/keycard = subject.wear_id
	keycard.registered_name = "Test Pilot"
	if(isnull(keycard.registered_account))
		keycard.registered_account = new /datum/bank_account(keycard.registered_name, null, 1, FALSE)

	var/obj/item/circuitboard/computer/landing_controller/programmable/board = allocate(/obj/item/circuitboard/computer/landing_controller/programmable, stage)
	board.attack_self(subject)
	TEST_ASSERT_EQUAL(board.program_mode, LANDING_CONTROLLER_LOCK_USER, "Use-in-hand should toggle to user mode.")

	TEST_ASSERT_EQUAL(board.item_interaction(subject, keycard), ITEM_INTERACT_SUCCESS, "User swipe should bind the board.")
	TEST_ASSERT_EQUAL(board.stored_owner_account_id, keycard.registered_account.account_id, "Board should store the account id.")
	TEST_ASSERT_EQUAL(board.stored_dock_affiliation, null, "User mode should leave pad docking open.")

	var/obj/machinery/computer/landing_controller/programmable/prog = allocate(/obj/machinery/computer/landing_controller/programmable, stage)
	prog.circuit = board
	prog.apply_board_program()
	TEST_ASSERT_EQUAL(prog.lock_mode, LANDING_CONTROLLER_LOCK_USER, "Applied board should set user lock mode.")
	TEST_ASSERT_EQUAL(prog.dock_affiliation, null, "User-locked console should keep open docking.")
	TEST_ASSERT(prog.allowed(subject), "Bound owner should be allowed.")

	var/obj/item/card/id/advanced/intruder = allocate(/obj/item/card/id/advanced, stage)
	intruder.registered_name = "Intruder"
	intruder.registered_account = new /datum/bank_account("Intruder", null, 1, FALSE)
	subject.wear_id = intruder
	TEST_ASSERT(!prog.allowed(subject), "Non-owner should be denied on a user-locked console.")

	var/obj/item/card/id/advanced/tarkon = allocate(/obj/item/card/id/advanced/tarkon, stage)
	TEST_ASSERT_EQUAL(get_id_overmap_faction(tarkon), null, "Tarkon IDs should map to open.")
	var/obj/item/card/id/advanced/interdyne = allocate(/obj/item/card/id/advanced, stage)
	SSid_access.apply_trim_to_card(interdyne, /datum/id_trim/syndicom/nova/interdyne)
	interdyne.access |= list(ACCESS_SYNDICATE, ACCESS_SYNDICATE_LEADER)
	TEST_ASSERT_EQUAL(get_id_overmap_faction(interdyne), null, "Interdyne IDs should map to open even with syndicate access.")

/datum/unit_test/overmap_landing_controller/emag_opens_nt_dock

/datum/unit_test/overmap_landing_controller/emag_opens_nt_dock/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/area/hull_area = get_area(stage)
	var/obj/docking_port/mobile/port = allocate(/obj/docking_port/mobile, stage, list(hull_area))
	port.width = 3
	port.height = 3
	port.dwidth = 1
	port.dheight = 1

	var/obj/structure/overmap/ship/simulated/ship = allocate(/obj/structure/overmap/ship/simulated, stage, port.shuttle_id, port)
	port.current_ship = ship
	ship.home_level_id = DES_TWO_OVERMAP_OBJECT_ID
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_DS2, "Test ship should resolve as DS2.")

	var/obj/structure/overmap/level/nav_target = allocate(/obj/structure/overmap/level, stage, "test_lz_emag_nav", list(stage.z))
	var/obj/machinery/computer/landing_controller/nanotrasen/nt = allocate(/obj/machinery/computer/landing_controller/nanotrasen, stage)
	nt.apply_zone(stage.x, stage.y, stage.z, 12, 12)
	TEST_ASSERT(!QDELETED(nt.active_zone), "NT controller should manage an active zone.")
	TEST_ASSERT_EQUAL(nt.active_zone.dock_affiliation, OVERMAP_AFFILIATION_NT, "Managed zone should start NT-locked.")

	var/list/zones = ship.get_landing_zones_for(nav_target)
	TEST_ASSERT(!(nt.active_zone in zones), "DS2 ships should not see NT-locked pads before emag.")

	TEST_ASSERT(nt.emag_act(null, null), "Emagging an NT landing controller should succeed.")
	TEST_ASSERT(nt.obj_flags & EMAGGED, "NT controller should be marked emagged.")
	TEST_ASSERT_EQUAL(nt.dock_affiliation, null, "Emag should clear dock affiliation on the console.")
	TEST_ASSERT_EQUAL(nt.active_zone.dock_affiliation, null, "Emag should open the managed landmark to any affiliation.")
	TEST_ASSERT(!length(nt.req_one_access), "Emag should clear NT console access requirements.")

	zones = ship.get_landing_zones_for(nav_target)
	TEST_ASSERT(nt.active_zone in zones, "DS2 ships should see emagged NT pads as open docking.")

/datum/unit_test/overmap_landing_controller/program_persist

/datum/unit_test/overmap_landing_controller/program_persist/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/item/circuitboard/computer/landing_controller/programmable/board = allocate(/obj/item/circuitboard/computer/landing_controller/programmable, stage)
	board.program_mode = LANDING_CONTROLLER_LOCK_FACTION
	board.stored_dock_affiliation = OVERMAP_AFFILIATION_DS2

	var/obj/machinery/computer/landing_controller/programmable/console = allocate(/obj/machinery/computer/landing_controller/programmable, stage)
	console.circuit = board
	console.on_construction(null)
	TEST_ASSERT_EQUAL(console.lock_mode, LANDING_CONTROLLER_LOCK_FACTION, "Construction should restore faction lock mode.")
	TEST_ASSERT_EQUAL(console.dock_affiliation, OVERMAP_AFFILIATION_DS2, "Construction should restore DS2 dock lock.")
	TEST_ASSERT_EQUAL(console.icon_screen, "emagged_general", "Restored syndicate lock should use the red monitor.")

	console.lock_mode = LANDING_CONTROLLER_LOCK_USER
	console.owner_account_id = 12345
	console.owner_name = "Persist Pilot"
	console.set_dock_affiliation(null)
	console.on_deconstruction(TRUE)
	TEST_ASSERT_EQUAL(board.program_mode, LANDING_CONTROLLER_LOCK_USER, "Deconstruction should persist user mode.")
	TEST_ASSERT_EQUAL(board.stored_owner_account_id, 12345, "Deconstruction should persist owner account id.")
	TEST_ASSERT_EQUAL(board.stored_owner_name, "Persist Pilot", "Deconstruction should persist owner name.")
	TEST_ASSERT_EQUAL(board.stored_dock_affiliation, null, "User mode persist should clear stored dock affiliation.")

/datum/unit_test/overmap_landing_controller/faction_dock

/datum/unit_test/overmap_landing_controller/faction_dock/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/area/hull_area = get_area(stage)
	var/obj/docking_port/mobile/port = allocate(/obj/docking_port/mobile, stage, list(hull_area))
	port.width = 3
	port.height = 3
	port.dwidth = 1
	port.dheight = 1

	var/obj/structure/overmap/ship/simulated/ship = allocate(/obj/structure/overmap/ship/simulated, stage, port.shuttle_id, port)
	port.current_ship = ship
	ship.home_level_id = MAIN_OVERMAP_OBJECT_ID
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_NT, "Test ship should resolve as NT.")

	var/obj/structure/overmap/level/nav_target = allocate(/obj/structure/overmap/level, stage, "test_lz_nav", list(stage.z))

	var/obj/effect/landmark/overmap_landing_zone/open_lz = allocate(/obj/effect/landmark/overmap_landing_zone, stage)
	open_lz.zone_width = 20
	open_lz.zone_height = 20
	open_lz.dock_affiliation = null

	var/turf/nt_turf = locate(stage.x + 1, stage.y, stage.z) || stage
	var/obj/effect/landmark/overmap_landing_zone/nt_lz = allocate(/obj/effect/landmark/overmap_landing_zone, nt_turf)
	nt_lz.zone_width = 20
	nt_lz.zone_height = 20
	nt_lz.dock_affiliation = OVERMAP_AFFILIATION_NT

	var/turf/ds2_turf = locate(stage.x + 2, stage.y, stage.z) || stage
	var/obj/effect/landmark/overmap_landing_zone/ds2_lz = allocate(/obj/effect/landmark/overmap_landing_zone, ds2_turf)
	ds2_lz.zone_width = 20
	ds2_lz.zone_height = 20
	ds2_lz.dock_affiliation = OVERMAP_AFFILIATION_DS2

	var/obj/machinery/computer/landing_controller/nanotrasen/nt_console = allocate(/obj/machinery/computer/landing_controller/nanotrasen, stage)
	nt_console.apply_zone(stage.x, stage.y, stage.z, 8, 8)
	TEST_ASSERT(!QDELETED(nt_console.active_zone), "apply_zone should create a managed landmark.")
	TEST_ASSERT_EQUAL(nt_console.active_zone.dock_affiliation, OVERMAP_AFFILIATION_NT, "Managed NT landmark should inherit dock affiliation.")

	var/list/zones = ship.get_landing_zones_for(nav_target)
	TEST_ASSERT(open_lz in zones, "Open LZs should remain available to NT ships.")
	TEST_ASSERT(nt_lz in zones, "NT-affiliated LZs should be available to NT ships.")
	TEST_ASSERT(!(ds2_lz in zones), "DS2-affiliated LZs should be hidden from NT ships.")

	ship.home_level_id = DES_TWO_OVERMAP_OBJECT_ID
	TEST_ASSERT_EQUAL(SSovermap.get_affiliation(ship), OVERMAP_AFFILIATION_DS2, "Test ship should resolve as DS2 after home change.")
	zones = ship.get_landing_zones_for(nav_target)
	TEST_ASSERT(open_lz in zones, "Open LZs should remain available to DS2 ships.")
	TEST_ASSERT(ds2_lz in zones, "DS2-affiliated LZs should be available to DS2 ships.")
	TEST_ASSERT(!(nt_lz in zones), "NT-affiliated LZs should be hidden from DS2 ships.")

/// Thrust/mass forward accel: hall-scale thrust is much slower; max_speed still caps.
/obj/structure/overmap/ship/unit_test_thrust
	var/test_thrust = 90
	var/test_mass = 100

/obj/structure/overmap/ship/unit_test_thrust/get_effective_thrust()
	return test_thrust

/obj/structure/overmap/ship/unit_test_thrust/get_effective_mass()
	return max(test_mass, 1)

/datum/unit_test/overmap_thrust_accel

/datum/unit_test/overmap_thrust_accel/Run()
	var/turf/stage = run_loc_floor_bottom_left
	var/obj/structure/overmap/ship/unit_test_thrust/ship = allocate(/obj/structure/overmap/ship/unit_test_thrust, stage)
	ship.max_speed = OVERMAP_MAX_SPEED
	ship.desired_angle = 0
	ship.desired_throttle = 1
	ship.has_heading = TRUE
	ship.test_mass = 100

	var/dt = 0.2
	ship.test_thrust = 90
	ship.vel_x = 0
	ship.vel_y = 0
	ship.physics_tick(dt)
	var/full_speed = ship.get_speed()

	ship.test_thrust = 90 * 0.15
	ship.vel_x = 0
	ship.vel_y = 0
	ship.physics_tick(dt)
	var/hall_speed = ship.get_speed()

	TEST_ASSERT(full_speed > OVERMAP_VELOCITY_EPSILON, "Full thrust should produce forward speed.")
	TEST_ASSERT(hall_speed > OVERMAP_VELOCITY_EPSILON, "Hall-scale thrust should still produce forward speed.")
	TEST_ASSERT(full_speed > hall_speed * 4, "Full propellant accel should be several times hall-only accel.")
	TEST_ASSERT(hall_speed < full_speed / 5, "Hall-only accel should be roughly 0.15× full (at least 5× slower).")

	ship.test_thrust = 9000
	ship.vel_x = 0
	ship.vel_y = 0
	for(var/i in 1 to 40)
		ship.physics_tick(dt)
	TEST_ASSERT(ship.get_speed() <= ship.max_speed + OVERMAP_VELOCITY_EPSILON, "Thrust-derived accel must still respect max_speed.")
	TEST_ASSERT(abs(ship.get_speed() - ship.max_speed) < 0.05, "Sustained full throttle should reach cruise max_speed.")
