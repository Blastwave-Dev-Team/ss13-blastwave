/proc/_megacell_charger_test_setup_charger(datum/unit_test/test, powered = TRUE)
	var/turf/stage = test.run_loc_floor_top_right
	var/obj/machinery/power/megacell_charger/wall/charger = test.allocate(/obj/machinery/power/megacell_charger/wall, stage)
	charger.setDir(NORTH)
	charger.make_terminal()
	if(powered)
		charger.terminal.powernet = new()
		charger.terminal.powernet.avail = 100 KILO JOULES
	charger.find_and_mount_on_atom()
	return charger

/proc/_megacell_charger_test_user_turf(obj/machinery/power/megacell_charger/wall/charger)
	return get_step(charger, turn(charger.dir, 180))

/proc/_megacell_charger_test_setup_area_power(datum/unit_test/test, turf/stage)
	var/obj/machinery/power/apc/apc = test.allocate(/obj/machinery/power/apc, stage)
	apc.has_electronics = APC_ELECTRONICS_SECURED
	apc.opened = APC_COVER_CLOSED
	apc.set_machine_stat(apc.machine_stat & ~MAINT)
	apc.operating = TRUE
	if(QDELETED(apc.cell))
		apc.cell = test.allocate(/obj/item/stock_parts/power_store/battery, apc)
	apc.make_terminal()
	apc.update_area_power_usage(TRUE)

/datum/unit_test/megacell_charger_shock_gating/Run()
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)

	// Incomplete chargers should not shock.
	var/obj/machinery/power/megacell_charger/frame = allocate(/obj/machinery/power/megacell_charger, run_loc_floor_bottom_left)
	var/initial_fire_loss = victim.get_fire_loss()
	TEST_ASSERT(!frame.shock_if_live(victim, 100), "Incomplete megacell charger shocked user.")
	TEST_ASSERT_EQUAL(initial_fire_loss, victim.get_fire_loss(), "Incomplete megacell charger damaged user.")

	// Unpowered complete chargers should not shock.
	var/obj/machinery/power/megacell_charger/wall/unpowered = _megacell_charger_test_setup_charger(src, powered = FALSE)
	TEST_ASSERT(!unpowered.shock_if_live(victim, 100), "Unpowered megacell charger shocked user.")
	TEST_ASSERT_EQUAL(initial_fire_loss, victim.get_fire_loss(), "Unpowered megacell charger damaged user.")

	// Powered complete chargers should shock bare hands.
	var/obj/machinery/power/megacell_charger/wall/charger = _megacell_charger_test_setup_charger(src, powered = TRUE)
	victim.forceMove(_megacell_charger_test_user_turf(charger))
	victim.heal_bodypart_damage(brute = victim.get_brute_loss(), burn = victim.get_fire_loss())
	initial_fire_loss = victim.get_fire_loss()
	TEST_ASSERT(charger.shock_if_live(victim, 100), "Powered megacell charger failed to shock user.")
	TEST_ASSERT(victim.get_fire_loss() > initial_fire_loss, "Powered megacell charger did not deal burn damage.")

	// Insulated gloves should block shocks.
	var/obj/item/clothing/gloves/color/yellow/insulated_gloves = allocate(/obj/item/clothing/gloves/color/yellow)
	victim.equip_to_slot_if_possible(insulated_gloves, ITEM_SLOT_GLOVES)
	initial_fire_loss = victim.get_fire_loss()
	TEST_ASSERT(!charger.shock_if_live(victim, 100), "Insulated gloves failed to block megacell charger shock.")
	TEST_ASSERT_EQUAL(initial_fire_loss, victim.get_fire_loss(), "Insulated gloves still took burn damage from megacell charger.")

	// Conductive tools should shock; non-conductive tools should not.
	victim.drop_all_held_items()
	qdel(victim.get_item_by_slot(ITEM_SLOT_GLOVES))
	var/obj/item/screwdriver/conductive_tool = allocate(/obj/item/screwdriver)
	initial_fire_loss = victim.get_fire_loss()
	TEST_ASSERT(charger.shock_on_conductive_tool(victim, conductive_tool, 100), "Conductive tool failed to shock user.")
	TEST_ASSERT(victim.get_fire_loss() > initial_fire_loss, "Conductive tool shock did not deal burn damage.")

	var/obj/item/kitchen/rollingpin/non_conductive_tool = allocate(/obj/item/kitchen/rollingpin)
	victim.heal_bodypart_damage(brute = victim.get_brute_loss(), burn = victim.get_fire_loss())
	initial_fire_loss = victim.get_fire_loss()
	TEST_ASSERT(!charger.shock_on_conductive_tool(victim, non_conductive_tool), "Non-conductive tool incorrectly shocked user.")
	TEST_ASSERT_EQUAL(initial_fire_loss, victim.get_fire_loss(), "Non-conductive tool shock dealt burn damage.")

/datum/unit_test/megacell_charger_shock_interaction/Run()
	var/turf/stage = run_loc_floor_top_right
	_megacell_charger_test_setup_area_power(src, stage)
	var/obj/machinery/power/megacell_charger/wall/charger = _megacell_charger_test_setup_charger(src, powered = TRUE)
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent, _megacell_charger_test_user_turf(charger))
	var/obj/item/stock_parts/power_store/battery/empty/megacell = allocate(/obj/item/stock_parts/power_store/battery/empty)
	charger.charging = megacell
	megacell.forceMove(charger)

	// Bare-hand battery removal must not shock the user.
	user.drop_all_held_items()
	var/obj/item/gloves = user.get_item_by_slot(ITEM_SLOT_GLOVES)
	if(gloves)
		qdel(gloves)
	var/initial_fire_loss = user.get_fire_loss()
	charger.attack_hand(user, list())
	TEST_ASSERT_EQUAL(initial_fire_loss, user.get_fire_loss(), "Bare-hand megacell removal shocked the user.")
	TEST_ASSERT_NULL(charger.charging, "Megacell was not removed bare-handed.")

	// Bare-hand megacell insertion must not shock the user.
	_megacell_charger_test_setup_area_power(src, stage)
	charger = _megacell_charger_test_setup_charger(src, powered = TRUE)
	user.forceMove(_megacell_charger_test_user_turf(charger))
	user.drop_all_held_items()
	gloves = user.get_item_by_slot(ITEM_SLOT_GLOVES)
	if(gloves)
		qdel(gloves)
	megacell = allocate(/obj/item/stock_parts/power_store/battery/empty)
	user.put_in_active_hand(megacell, forced = TRUE)
	initial_fire_loss = user.get_fire_loss()
	var/interaction_result = charger.item_interaction(user, megacell, list())
	TEST_ASSERT_EQUAL(initial_fire_loss, user.get_fire_loss(), "Bare-hand megacell insertion shocked the user.")
	TEST_ASSERT_EQUAL(interaction_result, ITEM_INTERACT_SUCCESS, "Megacell insertion failed.")
	TEST_ASSERT(charger.charging == megacell, "Megacell was not inserted into charger.")

/datum/unit_test/megacell_charger_wall_bump/Run()
	var/obj/machinery/power/megacell_charger/wall/charger = _megacell_charger_test_setup_charger(src, powered = TRUE)
	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human/consistent, _megacell_charger_test_user_turf(charger))
	var/datum/component/atom_mounted/mount = charger.GetComponent(/datum/component/atom_mounted)
	TEST_ASSERT_NOTNULL(mount, "Megacell charger failed to wall mount.")
	TEST_ASSERT(isclosedturf(mount.hanging_support_atom), "Megacell charger did not mount to a closed turf.")

	victim.heal_bodypart_damage(brute = victim.get_brute_loss(), burn = victim.get_fire_loss())
	var/initial_fire_loss = victim.get_fire_loss()
	mount.hanging_support_atom.Bumped(victim)
	charger.Bumped(victim)
	TEST_ASSERT_EQUAL(initial_fire_loss, victim.get_fire_loss(), "Bumping the megacell charger shocked the user.")
