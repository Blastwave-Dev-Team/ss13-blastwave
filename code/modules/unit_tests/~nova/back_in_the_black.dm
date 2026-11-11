/// Installs a fresh Back in the Black trait for the test, hiding any trait the round rolled.
/datum/unit_test/back_in_the_black
	abstract_type = /datum/unit_test/back_in_the_black
	var/datum/station_trait/back_in_the_black/trait
	var/list/stashed_traits = list()

/datum/unit_test/back_in_the_black/New()
	. = ..()
	for(var/datum/station_trait/back_in_the_black/existing in SSstation.station_traits)
		stashed_traits += existing
	SSstation.station_traits -= stashed_traits
	trait = new()
	SSstation.station_traits += trait

/datum/unit_test/back_in_the_black/Destroy()
	QDEL_NULL(trait)
	SSstation.station_traits += stashed_traits
	if(length(stashed_traits))
		ADD_TRAIT(SSstation, STATION_TRAIT_BACK_IN_THE_BLACK, STATION_TRAIT)
	stashed_traits.Cut()
	return ..()

/datum/unit_test/back_in_the_black/proc/make_associate(enroll = TRUE)
	var/mob/living/carbon/human/associate = allocate(/mob/living/carbon/human/consistent)
	associate.mind_initialize()
	var/uuid = generate_character_uuid()
	associate.mind.character_uuid = uuid
	SScharacter_ledger.insert_identity(uuid, "bitb_test", 1, associate.real_name)
	if(enroll)
		var/obj/item/implant/neuro_fiscal_tracker/tracker = new
		tracker.implant(associate, null, silent = TRUE, force = TRUE)
	return associate

/datum/unit_test/back_in_the_black/proc/tracker_in(mob/living/carbon/associate)
	return locate(/obj/item/implant/neuro_fiscal_tracker) in associate.implants

/datum/unit_test/back_in_the_black/proc/make_id(captain = FALSE)
	var/obj/item/card/id/advanced/id = allocate(/obj/item/card/id/advanced)
	id.access = captain ? list(ACCESS_CAPTAIN) : list(ACCESS_MEDICAL)
	return id

/// Goal met: three associates split 20% of earnings, and a second payout adds nothing.
/datum/unit_test/back_in_the_black/payout

/datum/unit_test/back_in_the_black/payout/Run()
	var/list/associates = list(make_associate(), make_associate(), make_associate())
	TEST_ASSERT_EQUAL(trait.active_seats, 3, "Three enrollments should claim three seats.")
	trait.add_income(trait.get_goal() + 1000, "Cargo Export")
	TEST_ASSERT(trait.goal_met(), "Income above the goal should meet it.")

	var/expected_share = round(trait.earned * BITB_BONUS_FRACTION / 3)
	TEST_ASSERT(trait.pay_out(), "pay_out() should succeed when the goal is met.")
	for(var/mob/living/carbon/human/associate as anything in associates)
		var/uuid = associate.mind.character_uuid
		TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid, LEDGER_CHANNEL_SHAREHOLDER_BONUS), 1, "Associate missing SHAREHOLDER_BONUS row.")
		TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), expected_share, "Associate received the wrong share.")

	TEST_ASSERT(!trait.pay_out(), "pay_out() should only run once.")
	for(var/mob/living/carbon/human/associate as anything in associates)
		TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(associate.mind.character_uuid, LEDGER_CHANNEL_SHAREHOLDER_BONUS), 1, "Second pay_out() credited again.")

	TEST_ASSERT(!trait.admin_set_goal(1), "admin_set_goal should refuse after payout.")
	TEST_ASSERT(!trait.admin_reset_goal(), "admin_reset_goal should refuse after payout.")
	TEST_ASSERT(!trait.admin_set_earned(1), "admin_set_earned should refuse after payout.")
	TEST_ASSERT(!trait.admin_set_label("Too Late"), "admin_set_label should refuse after payout.")

/// Goal missed: nobody is credited.
/datum/unit_test/back_in_the_black/goal_missed

/datum/unit_test/back_in_the_black/goal_missed/Run()
	var/mob/living/carbon/human/associate = make_associate()
	trait.add_income(trait.get_goal() - 1, "Cargo Export")
	TEST_ASSERT(!trait.pay_out(), "pay_out() should fail when the goal is missed.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(associate.mind.character_uuid, LEDGER_CHANNEL_SHAREHOLDER_BONUS), 0, "Missed goal still credited an associate.")

/// Dead holders and holders without the implant are skipped; the rest split the bonus.
/datum/unit_test/back_in_the_black/eligibility

/datum/unit_test/back_in_the_black/eligibility/Run()
	var/mob/living/carbon/human/alive = make_associate()
	var/mob/living/carbon/human/dead = make_associate()
	var/mob/living/carbon/human/extracted = make_associate()
	dead.death()
	var/obj/item/implant/neuro_fiscal_tracker/extracted_tracker = tracker_in(extracted)
	extracted_tracker.removed(extracted)

	TEST_ASSERT_EQUAL(trait.active_seats, 3, "Death and removal must not release seats.")
	trait.add_income(trait.get_goal(), "Service")
	var/expected_share = round(trait.earned * BITB_BONUS_FRACTION)
	TEST_ASSERT(trait.pay_out(), "pay_out() should succeed with one eligible associate.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(alive.mind.character_uuid), expected_share, "The sole eligible associate should receive the whole bonus.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(dead.mind.character_uuid), 0, "Dead associate was paid.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(extracted.mind.character_uuid), 0, "Associate without an implant was paid.")

/// Seats are claimed once per unit; the goal follows the seat count.
/datum/unit_test/back_in_the_black/seats

/datum/unit_test/back_in_the_black/seats/Run()
	TEST_ASSERT_EQUAL(trait.get_goal(), BITB_MIN_GOAL, "An empty roster should use the minimum goal.")
	var/mob/living/carbon/human/first = make_associate()
	TEST_ASSERT_EQUAL(trait.active_seats, 1, "First enrollment should claim a seat.")

	var/obj/item/implant/neuro_fiscal_tracker/tracker = tracker_in(first)
	tracker.removed(first)
	var/mob/living/carbon/human/second = make_associate(enroll = FALSE)
	TEST_ASSERT(tracker.implant(second, null, silent = TRUE, force = TRUE), "Reimplanting an active unit should work.")
	TEST_ASSERT_EQUAL(trait.active_seats, 1, "Moving an active unit to someone else must not claim a second seat.")
	TEST_ASSERT_EQUAL(tracker.seat_holder_name, first.real_name, "The seat should stay in the original holder's name.")

	var/seats_for_goal = CEILING(BITB_MIN_GOAL / BITB_GOAL_PER_CREW, 1) + 1
	trait.active_seats = seats_for_goal
	TEST_ASSERT_EQUAL(trait.get_goal(), seats_for_goal * BITB_GOAL_PER_CREW, "Goal should scale per seat above the minimum.")

/// Voiding takes Captain access, a removed unit, and only works once.
/datum/unit_test/back_in_the_black/void

/datum/unit_test/back_in_the_black/void/Run()
	var/mob/living/carbon/human/captain = allocate(/mob/living/carbon/human/consistent)
	var/mob/living/carbon/human/slacker = make_associate()
	make_associate()
	var/obj/item/implant/neuro_fiscal_tracker/tracker = tracker_in(slacker)
	var/obj/item/card/id/captain_id = make_id(captain = TRUE)
	var/obj/item/card/id/crew_id = make_id()

	TEST_ASSERT_EQUAL(tracker.void_refusal(captain_id), "remove it first", "An installed unit should not be voidable.")
	TEST_ASSERT(!tracker.void_contract(captain), "void_contract should refuse an installed unit.")
	TEST_ASSERT_EQUAL(trait.active_seats, 2, "Refused void changed the seat count.")

	tracker.removed(slacker)
	var/obj/item/implantcase/case = allocate(/obj/item/implantcase)
	tracker.forceMove(case)
	case.imp = tracker

	TEST_ASSERT_EQUAL(tracker.void_refusal(crew_id), "insufficient authority", "A crew ID should not be able to void.")
	TEST_ASSERT_EQUAL(case.item_interaction(captain, crew_id), ITEM_INTERACT_BLOCKING, "Tapping the case with a crew ID should be blocked by the implant.")
	TEST_ASSERT_EQUAL(tracker.seat_state, BITB_SEAT_ACTIVE, "A crew ID tap voided the unit.")
	TEST_ASSERT_EQUAL(case.item_interaction(captain, captain_id), ITEM_INTERACT_SUCCESS, "Tapping the case with a Captain ID should reach the implant's void prompt.")
	TEST_ASSERT_NULL(tracker.void_refusal(captain_id), "A removed active unit should be voidable by the Captain.")

	TEST_ASSERT(tracker.void_contract(captain), "void_contract should succeed on a removed unit.")
	TEST_ASSERT_EQUAL(trait.active_seats, 1, "Voiding should release the seat.")
	TEST_ASSERT_EQUAL(tracker.seat_state, BITB_SEAT_VOIDED, "Voided unit has the wrong state.")
	TEST_ASSERT_EQUAL(case.name, "implant case - 'VOIDED'", "The case should be relabeled.")

	TEST_ASSERT(!tracker.void_contract(captain), "A second void should fail.")
	TEST_ASSERT_EQUAL(trait.active_seats, 1, "A second void changed the seat count.")
	TEST_ASSERT_EQUAL(tracker.void_refusal(captain_id), "already voided", "A voided unit should report it is already voided.")

	var/mob/living/carbon/human/new_hire = make_associate(enroll = FALSE)
	TEST_ASSERT(!tracker.implant(new_hire, null, silent = TRUE, force = TRUE), "A voided unit must refuse installation.")
	TEST_ASSERT_EQUAL(trait.active_seats, 1, "A refused voided unit claimed a seat.")

/// Only voiding releases a seat; death and destruction do not.
/datum/unit_test/back_in_the_black/seat_permanence

/datum/unit_test/back_in_the_black/seat_permanence/Run()
	var/mob/living/carbon/human/doomed = make_associate()
	var/mob/living/carbon/human/lava_victim = make_associate()
	var/mob/living/carbon/human/loose_owner = make_associate()
	TEST_ASSERT_EQUAL(trait.active_seats, 3, "Setup should claim three seats.")

	doomed.death()
	TEST_ASSERT_EQUAL(trait.active_seats, 3, "Death released a seat.")

	qdel(tracker_in(lava_victim))
	TEST_ASSERT_EQUAL(trait.active_seats, 3, "Deleting an installed unit released a seat.")

	var/obj/item/implant/neuro_fiscal_tracker/loose = tracker_in(loose_owner)
	loose.removed(loose_owner)
	qdel(loose)
	TEST_ASSERT_EQUAL(trait.active_seats, 3, "Deleting a loose unit released a seat.")

	var/obj/item/implant/neuro_fiscal_tracker/pending = new
	qdel(pending)
	TEST_ASSERT_EQUAL(trait.active_seats, 3, "Deleting a pending unit changed the seat count.")

/// After round start, spawns are not auto-enrolled; before it, they are.
/datum/unit_test/back_in_the_black/roundstart_window

/datum/unit_test/back_in_the_black/roundstart_window/Run()
	TEST_ASSERT(!trait.roundstart_window_open, "A trait created after round start should have its window closed.")
	var/mob/living/carbon/human/latejoiner = make_associate(enroll = FALSE)
	trait.on_job_after_spawn(null, null, latejoiner, null)
	TEST_ASSERT_NULL(tracker_in(latejoiner), "A latejoin spawn was auto-enrolled.")
	TEST_ASSERT_EQUAL(trait.active_seats, 0, "A latejoin spawn claimed a seat.")

	trait.roundstart_window_open = TRUE
	var/mob/living/carbon/human/roundstarter = make_associate(enroll = FALSE)
	trait.on_job_after_spawn(null, null, roundstarter, null)
	TEST_ASSERT_NOTNULL(tracker_in(roundstarter), "A roundstart spawn was not enrolled while the window was open.")
	TEST_ASSERT_EQUAL(trait.active_seats, 1, "A roundstart enrollment did not claim a seat.")

	trait.close_roundstart_window()
	TEST_ASSERT(!trait.roundstart_window_open, "close_roundstart_window did not close the window.")

/// Admin goal override beats the seat formula until reset; progress can be set directly.
/datum/unit_test/back_in_the_black/admin_controls

/datum/unit_test/back_in_the_black/admin_controls/Run()
	TEST_ASSERT(trait.admin_set_goal(777), "admin_set_goal should succeed before payout.")
	TEST_ASSERT_EQUAL(trait.get_goal(), 777, "Goal override was not applied.")
	make_associate()
	TEST_ASSERT_EQUAL(trait.get_goal(), 777, "A seat claim changed an overridden goal.")

	TEST_ASSERT(trait.admin_reset_goal(), "admin_reset_goal should succeed before payout.")
	TEST_ASSERT_EQUAL(trait.get_goal(), max(BITB_MIN_GOAL, trait.active_seats * BITB_GOAL_PER_CREW), "Reset did not restore the seat formula.")

	trait.add_income(500, "Cargo Export")
	TEST_ASSERT(trait.admin_set_earned(2000), "admin_set_earned should succeed before payout.")
	TEST_ASSERT_EQUAL(trait.earned, 2000, "admin_set_earned did not set earnings.")
	TEST_ASSERT_EQUAL(trait.income_by_source["Admin adjustment"], 1500, "admin_set_earned did not record the adjustment.")

	TEST_ASSERT(trait.admin_set_label("  Pay <b>Speeding</b> Ticket  "), "admin_set_label should succeed before payout.")
	TEST_ASSERT_EQUAL(trait.goal_label, html_encode("Pay <b>Speeding</b> Ticket"), "Goal text was not trimmed and encoded.")
	trait.admin_set_label(repeat_string(BITB_GOAL_LABEL_MAX_LEN + 10, "x"))
	TEST_ASSERT_EQUAL(length(trait.goal_label), BITB_GOAL_LABEL_MAX_LEN, "Goal text was not capped.")
	trait.admin_set_label("   ")
	TEST_ASSERT_EQUAL(trait.goal_label, BITB_DEFAULT_GOAL_LABEL, "Blank goal text did not restore the default.")

/// The memo fills every value, and the handbook link survives sanitizing.
/datum/unit_test/back_in_the_black/paperwork

/datum/unit_test/back_in_the_black/paperwork/Run()
	var/memo = trait.get_memo(451)
	TEST_ASSERT(findtext(memo, bitb_credits(trait.get_goal())), "Memo is missing the computed goal.")
	TEST_ASSERT(!findtext(memo, "\["), "Memo contains an unfilled bracket.")
	TEST_ASSERT(findtext(memo, "FR-451"), "Memo is missing its number.")

	var/obj/item/book/manual/wiki/ugc/neuro_fiscal_tracker/handbook = /obj/item/book/manual/wiki/ugc/neuro_fiscal_tracker
	var/page_link = initial(handbook.page_link)
	TEST_ASSERT_EQUAL(resolve_textbook_page_link(page_link, trusted = TRUE), page_link, "Handbook page_link does not survive sanitizing.")
	TEST_ASSERT(!(handbook in get_random_manual_options()), "Handbook can spawn as a random manual.")

	TEST_ASSERT_EQUAL(bitb_credits(12340), "12,340", "bitb_credits did not group thousands.")
	TEST_ASSERT_EQUAL(bitb_credits(999), "999", "bitb_credits mangled a small number.")

/// Only lockers flagged at round start get the enrollment kit.
/datum/unit_test/back_in_the_black/cmo_locker

/datum/unit_test/back_in_the_black/cmo_locker/Run()
	var/obj/structure/closet/secure_closet/chief_medical/late_locker = allocate(/obj/structure/closet/secure_closet/chief_medical)
	TEST_ASSERT(!late_locker.bitb_roundstart_locker, "A locker created after round start was flagged.")
	late_locker.PopulateContents()
	TEST_ASSERT_NULL(locate(/obj/item/storage/box/neuro_fiscal_tracker_implants) in late_locker, "A late locker received the enrollment kit.")

	var/obj/structure/closet/secure_closet/chief_medical/roundstart_locker = allocate(/obj/structure/closet/secure_closet/chief_medical)
	roundstart_locker.bitb_roundstart_locker = TRUE
	roundstart_locker.PopulateContents()
	var/obj/item/storage/box/neuro_fiscal_tracker_implants/kit = locate() in roundstart_locker
	TEST_ASSERT_NOTNULL(kit, "A roundstart locker did not receive the enrollment kit.")
	var/case_count = 0
	for(var/obj/item/implantcase/neuro_fiscal_tracker/case in kit)
		case_count++
	TEST_ASSERT_EQUAL(case_count, BITB_LATEJOIN_IMPLANT_COUNT, "Enrollment kit has the wrong number of cases.")
	TEST_ASSERT_NOTNULL(locate(/obj/item/book/manual/wiki/ugc/neuro_fiscal_tracker) in kit, "Enrollment kit is missing the handbook.")
	TEST_ASSERT(length(kit.contents) <= kit.atom_storage.max_slots, "Enrollment kit overflows its storage.")
