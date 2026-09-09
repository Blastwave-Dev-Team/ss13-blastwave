// MODULE ID: BLASTWAVE-BLUESPACE
// The interdiction generator's breaker is a one-way trip. Collapsing the field spends it, and
// nothing short of admin intervention brings the field back, because the whole set piece rests
// on players being able to shut the thing down and have it stay down.
//
// Authorisation lives in the cards physically sitting in the reader, so these also cover the
// slot/eject round trip: taking a card back out has to re-lock the slot it filled.

/datum/unit_test/unstable_field_breaker
	abstract_type = /datum/unit_test/unstable_field_breaker

/// A card the generator will accept, in the test's hands rather than the machine's.
/datum/unit_test/unstable_field_breaker/proc/build_card(puzzle_id = "test_authorisation")
	var/obj/item/keycard/card = allocate(/obj/item/keycard)
	card.puzzle_id = puzzle_id
	return card

/// Builds a generator needing one authorization, with its card already slotted so the breaker
/// is free. Goes through attackby() so the fixture exercises the real insertion path.
/datum/unit_test/unstable_field_breaker/proc/build_generator()
	var/obj/machinery/unstable_field_generator/main/generator = allocate(
		/obj/machinery/unstable_field_generator/main,
		run_loc_floor_bottom_left,
	)
	generator.required_puzzle_ids = list("test_authorisation")

	var/mob/living/carbon/human/consistent/technician = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/keycard/card = build_card()
	technician.put_in_hands(card)
	generator.attackby(card, technician, list(), list())
	return generator

/// Pulls the breaker and runs the ramp to the floor. Returns the number of process ticks the
/// collapse took, so callers can assert on how long it takes in wall-clock terms.
/datum/unit_test/unstable_field_breaker/proc/collapse(obj/machinery/unstable_field_generator/main/generator)
	generator.breaker = FALSE
	generator.set_power()
	var/ticks = 0
	for(var/i in 1 to 200)
		if(!generator.on && generator.breaker_spent)
			break
		generator.process()
		ticks++
	return ticks

/// Cards go into the machine and come back out, and the slot only counts while one is in it.
/datum/unit_test/unstable_field_breaker/cards_slot_and_eject

/datum/unit_test/unstable_field_breaker/cards_slot_and_eject/Run()
	var/obj/machinery/unstable_field_generator/main/generator = allocate(
		/obj/machinery/unstable_field_generator/main,
		run_loc_floor_bottom_left,
	)
	generator.required_puzzle_ids = list("test_authorisation")

	var/mob/living/carbon/human/consistent/technician = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/keycard/card = build_card()
	technician.put_in_hands(card)
	TEST_ASSERT_EQUAL(length(generator.missing_puzzle_ids()), 1, "An empty reader should report its slot unfilled.")

	generator.attackby(card, technician, list(), list())
	TEST_ASSERT_EQUAL(card.loc, generator, "Slotting a card must move it into the machine, not just read it.")
	TEST_ASSERT(card in generator.slotted_cards, "A slotted card should be tracked in the slot list.")
	TEST_ASSERT_EQUAL(length(generator.missing_puzzle_ids()), 0, "A slotted card should fill its slot.")

	generator.interact(technician)
	TEST_ASSERT(!(card in generator.slotted_cards), "An empty hand should take the card back out.")
	TEST_ASSERT(card.loc != generator, "An ejected card must leave the machine's contents.")
	TEST_ASSERT_EQUAL(length(generator.missing_puzzle_ids()), 1, "Removing a card must re-lock its slot.")

/// A card the generator does not ask for stays in the user's hand.
/datum/unit_test/unstable_field_breaker/rejects_wrong_card

/datum/unit_test/unstable_field_breaker/rejects_wrong_card/Run()
	var/obj/machinery/unstable_field_generator/main/generator = allocate(
		/obj/machinery/unstable_field_generator/main,
		run_loc_floor_bottom_left,
	)
	generator.required_puzzle_ids = list("test_authorisation")

	var/mob/living/carbon/human/consistent/technician = allocate(/mob/living/carbon/human/consistent)
	var/obj/item/keycard/wrong = build_card("some_other_door")
	technician.put_in_hands(wrong)

	generator.attackby(wrong, technician, list(), list())
	TEST_ASSERT(wrong.loc != generator, "A card for another lock must not be swallowed by the reader.")
	TEST_ASSERT_EQUAL(length(generator.slotted_cards), 0, "A rejected card must not occupy a slot.")

/// Emptying the reader must take the breaker's freedom with it.
/datum/unit_test/unstable_field_breaker/eject_relocks_breaker

/datum/unit_test/unstable_field_breaker/eject_relocks_breaker/Run()
	var/obj/machinery/unstable_field_generator/main/generator = build_generator()
	var/mob/living/carbon/human/consistent/engineer = allocate(/mob/living/carbon/human/consistent)

	generator.interact(engineer)
	TEST_ASSERT_EQUAL(length(generator.missing_puzzle_ids()), 1, "Fixture should be one card short after ejecting.")

	generator.pull_breaker(engineer)
	TEST_ASSERT(generator.breaker, "The breaker must not move while a slot sits empty.")

/datum/unit_test/unstable_field_breaker/spends_on_collapse

/datum/unit_test/unstable_field_breaker/spends_on_collapse/Run()
	var/obj/machinery/unstable_field_generator/main/generator = build_generator()
	TEST_ASSERT(!generator.breaker_spent, "A fresh generator should not start with a spent breaker.")

	collapse(generator)
	TEST_ASSERT(generator.breaker_spent, "Collapsing the field should spend the breaker.")
	TEST_ASSERT(!generator.on, "A collapsed generator should not report itself running.")
	TEST_ASSERT(!generator.breaker, "Collapsing should leave the breaker pulled.")

/// The capacitor bank is supposed to dump in roughly fifteen seconds, not linger for a minute.
/datum/unit_test/unstable_field_breaker/collapses_within_fifteen_seconds

/datum/unit_test/unstable_field_breaker/collapses_within_fifteen_seconds/Run()
	var/obj/machinery/unstable_field_generator/main/generator = build_generator()
	TEST_ASSERT_EQUAL(generator.charge_count, 100, "Test needs a full bank to time the drain from.")

	var/ticks = collapse(generator)
	var/seconds = (ticks * SSmachines.wait) / (1 SECONDS)
	TEST_ASSERT(seconds <= 15, "Collapse took [seconds]s of SSmachines time, expected 15s or less.")
	TEST_ASSERT(seconds >= 8, "Collapse took only [seconds]s, which is too abrupt to react to.")

/datum/unit_test/unstable_field_breaker/refuses_to_re_engage

/datum/unit_test/unstable_field_breaker/refuses_to_re_engage/Run()
	var/obj/machinery/unstable_field_generator/main/generator = build_generator()
	collapse(generator)

	var/mob/living/carbon/human/consistent/engineer = allocate(/mob/living/carbon/human/consistent)
	generator.pull_breaker(engineer)
	TEST_ASSERT(!generator.breaker, "pull_breaker() must not re-engage a spent breaker.")

	var/settled = generator.charge_count
	for(var/i in 1 to 20)
		generator.process()
	TEST_ASSERT(generator.charge_count <= settled, "A spent generator must never ramp back up.")

	generator.breaker = TRUE
	generator.set_power()
	settled = generator.charge_count
	for(var/i in 1 to 200)
		generator.process()
	TEST_ASSERT(generator.charge_count <= settled, "set_power() must ignore a re-forced breaker once spent.")
	TEST_ASSERT(!generator.on, "A spent generator must not come back on no matter how long it runs.")

/// Re-slotting the full card set must not resurrect a spent breaker.
/datum/unit_test/unstable_field_breaker/authorisations_do_not_revive

/datum/unit_test/unstable_field_breaker/authorisations_do_not_revive/Run()
	var/obj/machinery/unstable_field_generator/main/generator = build_generator()
	collapse(generator)

	var/mob/living/carbon/human/consistent/engineer = allocate(/mob/living/carbon/human/consistent)
	TEST_ASSERT_EQUAL(length(generator.missing_puzzle_ids()), 0, "The card should still be sitting in the spent machine.")

	generator.pull_breaker(engineer)
	TEST_ASSERT(!generator.breaker, "A full set of authorisations must not free a spent breaker.")
	TEST_ASSERT(!generator.on, "A full set of authorisations must not restart the field.")
