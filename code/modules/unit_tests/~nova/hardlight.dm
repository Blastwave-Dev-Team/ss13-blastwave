// MODULE ID: BLASTWAVE_HARDLIGHT
// The hard-light encounter's load-bearing numbers and its one-way phase chain.
//
// The balance tests here are deliberately written against the composition of armour and drain
// coefficient rather than against fired projectiles. What the encounter promises is an ordering -
// a disabler must be worth more than a rifle - and that ordering is a property of those two
// numbers multiplied together. Testing it directly means a future tweak to either one cannot
// quietly invert the lesson the first room is supposed to teach.

/datum/unit_test/hardlight
	abstract_type = /datum/unit_test/hardlight

/// Drain, collapse, and the recovery threshold that makes an eviction temporary.
/datum/unit_test/hardlight/pad_lifecycle

/datum/unit_test/hardlight/pad_lifecycle/Run()
	var/obj/machinery/hardlight_projector/pad = allocate(/obj/machinery/hardlight_projector, run_loc_floor_bottom_left)

	TEST_ASSERT(pad.can_project(), "A fresh pad should be able to hold a body up.")
	TEST_ASSERT_EQUAL(pad.stored_charge, HARDLIGHT_PAD_MAX_CHARGE, "A fresh pad should start on a full bank.")

	// A partial hit comes straight off the bank, one for one, while the bank is healthy.
	var/absorbed = pad.drain(100)
	TEST_ASSERT_EQUAL(absorbed, 100, "A pad above the destabilisation line should absorb a hit one for one.")
	TEST_ASSERT_EQUAL(pad.stored_charge, HARDLIGHT_PAD_MAX_CHARGE - 100, "Absorbed charge should leave the bank.")
	TEST_ASSERT(!pad.collapsed, "A pad with charge left should not be collapsed.")

	// Emptying it is the eviction.
	pad.drain(HARDLIGHT_PAD_MAX_CHARGE * 10)
	TEST_ASSERT(pad.collapsed, "Draining the bank to zero should collapse the pad.")
	TEST_ASSERT_EQUAL(pad.stored_charge, 0, "A collapsed pad should hold no charge.")
	TEST_ASSERT(!pad.can_project(), "A collapsed pad should not be able to hold a body up.")
	TEST_ASSERT_EQUAL(pad.drain(50), 0, "A collapsed pad should absorb nothing.")

	// Recovery is the timer the crew is working against, and it is not done at the first spark.
	var/reactivate_at = HARDLIGHT_PAD_MAX_CHARGE * HARDLIGHT_REACTIVATE_FRACTION
	pad.stored_charge = reactivate_at - 1
	pad.process(0)
	TEST_ASSERT(pad.collapsed, "A pad below the reactivation threshold should stay collapsed.")

	pad.stored_charge = reactivate_at - 1
	pad.recharge_rate = 10
	pad.process(1)
	TEST_ASSERT(!pad.collapsed, "Crossing the reactivation threshold should bring the pad back.")
	TEST_ASSERT(pad.can_project(), "A recovered pad should be able to hold a body up again.")

/// No APC in the room halves recovery; an area feeder restores the capacitor rate.
/datum/unit_test/hardlight/pad_apc_trickle

/datum/unit_test/hardlight/pad_apc_trickle/Run()
	var/obj/machinery/hardlight_projector/pad = allocate(/obj/machinery/hardlight_projector, run_loc_floor_bottom_left)
	var/area/here = get_area(pad)
	TEST_ASSERT(here, "Pad should have an area for the APC trickle check.")
	var/obj/machinery/power/apc/prior = here.apc

	pad.recharge_rate = 10
	pad.stored_charge = 0
	here.apc = null
	TEST_ASSERT(!pad.has_area_apc(), "Nulling the area APC should put the pad on trickle.")
	TEST_ASSERT_EQUAL(pad.effective_recharge_rate(), 10 * HARDLIGHT_RECHARGE_NO_APC_MULT, "No APC should half the capacitor rate.")
	pad.process(1)
	TEST_ASSERT_EQUAL(pad.stored_charge, 10 * HARDLIGHT_RECHARGE_NO_APC_MULT, "Trickle process should apply the halved rate.")

	if(prior && !QDELETED(prior))
		here.apc = prior
	else
		here.apc = allocate(/obj/machinery/power/apc, run_loc_floor_bottom_left)
	TEST_ASSERT(pad.has_area_apc(), "An area APC should restore full recovery.")
	TEST_ASSERT_EQUAL(pad.effective_recharge_rate(), 10, "An area APC should use the capacitor rate.")
	pad.stored_charge = 0
	pad.process(1)
	TEST_ASSERT_EQUAL(pad.stored_charge, 10, "Fed process should apply the full rate.")

	if(here.apc != prior)
		here.apc = prior

	var/found_trickle = FALSE
	for(var/entry in pad.examine(allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)))
		if(findtext(entry, "trickle-charge"))
			found_trickle = TRUE
			break
	TEST_ASSERT(found_trickle, "Examine should mention trickle-charge, like energy weapons.")

/// Below the destabilisation line a pad that has started losing keeps losing.
/datum/unit_test/hardlight/pad_destabilisation

/datum/unit_test/hardlight/pad_destabilisation/Run()
	var/obj/machinery/hardlight_projector/pad = allocate(/obj/machinery/hardlight_projector, run_loc_floor_bottom_left)

	TEST_ASSERT(!pad.is_destabilised(), "A full pad should not read as destabilised.")

	// Just under the line, with enough bank left that the amplified hit cannot bottom it out.
	pad.stored_charge = (HARDLIGHT_PAD_MAX_CHARGE * HARDLIGHT_ENRAGE_FRACTION) - 1
	TEST_ASSERT(pad.is_destabilised(), "A pad under HARDLIGHT_ENRAGE_FRACTION should read as destabilised.")

	var/before = pad.stored_charge
	var/absorbed = pad.drain(10)
	TEST_ASSERT_EQUAL(absorbed, 10 * HARDLIGHT_ENRAGE_DRAIN_MULT, "A destabilised pad should absorb the enrage multiple of the hit.")
	TEST_ASSERT_EQUAL(pad.stored_charge, before - absorbed, "The amplified amount should be what actually leaves the bank.")

	// A collapsed pad is not destabilised, it is gone. The distinction matters to the avatar.
	pad.drain(HARDLIGHT_PAD_MAX_CHARGE)
	TEST_ASSERT(!pad.is_destabilised(), "A collapsed pad should not also report as destabilised.")

/// One pulse, one bank. Both the pad and the body forward EMPs here.
/datum/unit_test/hardlight/pad_emp_window

/datum/unit_test/hardlight/pad_emp_window/Run()
	var/obj/machinery/hardlight_projector/pad = allocate(/obj/machinery/hardlight_projector, run_loc_floor_bottom_left)

	var/first = pad.emp_drain(EMP_HEAVY)
	TEST_ASSERT_EQUAL(first, HARDLIGHT_EMP_DRAIN / EMP_HEAVY, "A heavy EMP should strip the full flat drain.")

	// The same blast reaching the body a tick later must not be charged twice.
	TEST_ASSERT_EQUAL(pad.emp_drain(EMP_HEAVY), 0, "A second EMP inside HARDLIGHT_EMP_WINDOW should be free.")

	COOLDOWN_RESET(pad, emp_window)
	TEST_ASSERT(pad.emp_drain(EMP_LIGHT) > 0, "A separate pulse after the window should drain again.")

/**
 * The weapon-selection lesson, as an ordering.
 *
 * Effective cost per point of incoming damage is (what armour lets through) times (what the pad is
 * charged for it). Disablers have to beat everything conventional or nobody carries one, and
 * bullets have to be visibly pointless or the first room teaches nothing.
 */
/datum/unit_test/hardlight/drain_efficiency

/datum/unit_test/hardlight/drain_efficiency/Run()
	var/datum/armor/armour = get_armor_by_type(/datum/armor/hardlight_avatar)
	TEST_ASSERT(!isnull(armour), "The hardlight avatar armour datum should be registered.")

	var/disabler = through(armour, ENERGY) * HARDLIGHT_DRAIN_COEFF_STAMINA
	var/laser = through(armour, LASER) * HARDLIGHT_DRAIN_COEFF_BURN
	var/bullet = through(armour, BULLET) * HARDLIGHT_DRAIN_COEFF_BRUTE
	var/melee = through(armour, MELEE) * HARDLIGHT_DRAIN_COEFF_BRUTE
	var/bomb = through(armour, BOMB) * HARDLIGHT_DRAIN_COEFF_BRUTE

	TEST_ASSERT(disabler > laser, "Disabler stamina must cost the bank more per point than a laser, or the intended answer is not the answer.")
	TEST_ASSERT(laser > bullet, "Kill-energy weapons must beat kinetics, per the design's 'works but slowly'.")
	TEST_ASSERT(bullet < disabler * 0.25, "Bullets must be dramatically worse than disablers, not merely worse.")
	TEST_ASSERT(melee < laser, "Melee must not be competitive with directed energy.")
	TEST_ASSERT(bomb < bullet, "Explosives couple worst of all into a capacitor bank.")

	// The burst answer. One pulse has to be worth more than a magazine emptied into the thing.
	var/magazine = 30 * 25 * through(armour, BULLET) * HARDLIGHT_DRAIN_COEFF_BRUTE
	TEST_ASSERT(HARDLIGHT_EMP_DRAIN > magazine, "A heavy EMP should out-drain a full magazine of rifle fire.")

/// Fraction of a hit of `armour_type` that survives to reach the bank.
/datum/unit_test/hardlight/drain_efficiency/proc/through(datum/armor/armour, armour_type)
	return (100 - armour.get_rating(armour_type)) / 100

/// Coverage is scoped by area identity, which is what stops the body following anyone out of a room.
/datum/unit_test/hardlight/coverage_is_area_scoped

/datum/unit_test/hardlight/coverage_is_area_scoped/Run()
	var/turf/home = run_loc_floor_bottom_left
	var/turf/neighbour = get_step(home, EAST)
	TEST_ASSERT(isfloorturf(neighbour), "Coverage test needs a second floor turf to work with.")

	var/obj/machinery/hardlight_projector/pad = allocate(/obj/machinery/hardlight_projector, home)
	TEST_ASSERT(!isnull(pad.coverage), "A projector should carry a coverage component.")
	TEST_ASSERT(pad.coverage.covers_turf(home), "A pad should cover its own tile.")
	TEST_ASSERT(pad.coverage.covers_turf(neighbour), "A pad should cover a tile sharing its area.")
	TEST_ASSERT(!pad.coverage.covers_turf(null), "Nowhere is not covered.")

	// Same area type, different area instance: two rooms built from one typepath must not pool.
	var/area/original = get_area(neighbour)
	var/area/elsewhere = new original.type
	neighbour.change_area(original, elsewhere)
	TEST_ASSERT(!pad.coverage.covers_turf(neighbour), "Coverage must compare area identity, not area typepath.")
	neighbour.change_area(elsewhere, original)
	qdel(elsewhere)

	// The registry is how the director finds pads nobody handed it.
	TEST_ASSERT(pad.coverage in hardlight_coverage_on_z(home.z), "A live pad should be discoverable on its own Z.")

/// Claiming is one-body-per-pad, and a relocation hands the claim over rather than duplicating it.
/datum/unit_test/hardlight/coverage_claim

/datum/unit_test/hardlight/coverage_claim/Run()
	var/obj/machinery/hardlight_projector/pad = allocate(/obj/machinery/hardlight_projector, run_loc_floor_bottom_left)
	var/mob/living/carbon/human/stand_in = allocate(/mob/living/carbon/human/consistent, run_loc_floor_bottom_left)

	TEST_ASSERT(!pad.coverage.is_claimed(), "A fresh pad should not be holding anything up.")

	pad.coverage.claim_avatar(stand_in)
	TEST_ASSERT(pad.coverage.is_claimed(), "Claiming should mark the pad as occupied.")
	TEST_ASSERT_EQUAL(pad.coverage.get_avatar(), stand_in, "The pad should hand back what it was given.")

	pad.coverage.release_avatar()
	TEST_ASSERT(!pad.coverage.is_claimed(), "Releasing should free the pad.")

/// Room preference, including where unlisted rooms sort.
/datum/unit_test/hardlight/area_ranking

/datum/unit_test/hardlight/area_ranking/Run()
	var/obj/machinery/hardlight_command_core/core = allocate(/obj/machinery/hardlight_command_core, run_loc_floor_bottom_left)
	// Two sibling types, so neither can satisfy the other's istype() check, plus their shared
	// parent standing in for a room the encounter author never listed.
	core.area_priority = list(
		/area/misc/start,
		/area/misc/testroom,
	)

	var/area/first = new /area/misc/start
	var/area/second = new /area/misc/testroom
	var/area/unlisted = new /area/misc

	TEST_ASSERT_EQUAL(core.rank_of(first), 1, "The head of the preference list should rank first.")
	TEST_ASSERT_EQUAL(core.rank_of(second), 2, "The second entry should rank second.")
	TEST_ASSERT(core.rank_of(unlisted) > core.rank_of(second), "An unlisted area must sort after every listed one.")
	TEST_ASSERT_EQUAL(core.rank_of(null), length(core.area_priority) + 1, "Nowhere should sort with the unlisted rooms.")

	qdel(first)
	qdel(second)
	qdel(unlisted)

/**
 * Several plates in one room.
 *
 * A room is allowed as many plates as it deserves, and the unit is supposed to take whichever one
 * is nearest whoever it is going for - that is what makes a long hall something you fight along
 * rather than something you fight at one end of. The stickiness is tested alongside it because
 * nearest-wins on its own produces a body that twitches between two plates as someone sidesteps.
 */
/datum/unit_test/hardlight/pad_proximity

/datum/unit_test/hardlight/pad_proximity/Run()
	var/turf/home = run_loc_floor_bottom_left
	var/obj/machinery/hardlight_command_core/core = allocate(/obj/machinery/hardlight_command_core, home)

	// Opposite corners of the unit-test room: same area, far enough that the
	// repad margin cannot treat them as one plate.
	var/turf/near_turf = home
	var/turf/far_turf = run_loc_floor_top_right
	TEST_ASSERT(isfloorturf(far_turf), "Proximity test needs the unit-test room's far corner.")
	TEST_ASSERT(get_dist(near_turf, far_turf) > HARDLIGHT_REPAD_MARGIN, "The two corners must sit farther apart than HARDLIGHT_REPAD_MARGIN.")
	TEST_ASSERT_EQUAL(get_area(far_turf), get_area(home), "Both plates must share one area for this test to mean anything.")

	var/obj/machinery/hardlight_projector/near_pad = allocate(/obj/machinery/hardlight_projector, near_turf)
	var/obj/machinery/hardlight_projector/far_pad = allocate(/obj/machinery/hardlight_projector, far_turf)

	// pad_covering() answers for the priority-threat path, which is the emitter case.
	TEST_ASSERT_EQUAL(core.pad_covering(near_turf), near_pad, "The nearer plate should answer for a threat standing on it.")
	TEST_ASSERT_EQUAL(core.pad_covering(far_turf), far_pad, "The farther plate should answer for a threat standing on it.")

	// A flat plate is not an answer, even when it is the closest thing to the threat.
	near_pad.drain(HARDLIGHT_PAD_MAX_CHARGE)
	TEST_ASSERT(near_pad.collapsed, "Setup expected the near plate to be flat.")
	TEST_ASSERT_EQUAL(core.pad_covering(near_turf), far_pad, "A collapsed plate should hand the room over rather than answer.")

	// Which is the whole point of allowing several: emptying one does not empty the room.
	TEST_ASSERT(far_pad.can_project(), "Draining one plate must not drain its neighbours.")

/**
 * The phase chain, and the one signal the rest of the encounter hangs off.
 *
 * Progression is one-way by design: every step is something the crew did, and none of them are
 * things the station can undo. Extraction in particular has to stay idempotent, because the
 * garrison waking twice would be a very bad bug to find in a playtest.
 */
/datum/unit_test/hardlight/phase_progression

/datum/unit_test/hardlight/phase_progression/Run()
	var/obj/machinery/hardlight_command_core/core = allocate(/obj/machinery/hardlight_command_core, run_loc_floor_bottom_left)
	TEST_ASSERT_EQUAL(core.phase, HARDLIGHT_PHASE_DORMANT, "A core should start asleep.")

	core.set_phase(HARDLIGHT_PHASE_ACTIVE)
	TEST_ASSERT_EQUAL(core.phase, HARDLIGHT_PHASE_ACTIVE, "Lifting the site lockdown should wake the core.")

	core.set_phase(HARDLIGHT_PHASE_BREACHED)
	TEST_ASSERT_EQUAL(core.phase, HARDLIGHT_PHASE_BREACHED, "Drilling the containment field should breach the core.")

	TEST_ASSERT(core.matrix_extracted(null), "Extraction against a breached core should succeed.")
	TEST_ASSERT_EQUAL(core.phase, HARDLIGHT_PHASE_EXTRACTED, "Extraction should end the encounter's boss phase.")
	TEST_ASSERT(isnull(core.avatar), "An extracted core should have no body up.")

	TEST_ASSERT(!core.matrix_extracted(null), "A second extraction should be refused rather than re-firing the garrison signal.")

/// The field only answers to an emitter, and only breaches once.
/datum/unit_test/hardlight/containment_drill

/datum/unit_test/hardlight/containment_drill/Run()
	var/turf/home = run_loc_floor_bottom_left
	var/obj/machinery/hardlight_command_core/core = allocate(/obj/machinery/hardlight_command_core, home)
	core.set_phase(HARDLIGHT_PHASE_ACTIVE)

	// Null puzzle_id means the field is up from mapload, which is what we want to test against.
	var/obj/machinery/hardlight_containment/field = allocate(/obj/machinery/hardlight_containment, home)
	TEST_ASSERT(field.raised, "A field with no puzzle id should come up at mapload.")
	TEST_ASSERT(field.density, "A raised field should be in the way.")

	// The rest of the ring. Never drilled, and has to come down regardless.
	var/obj/machinery/hardlight_containment/sibling = allocate(/obj/machinery/hardlight_containment, home)

	var/obj/machinery/power/emitter/drill = allocate(/obj/machinery/power/emitter, home)

	// One short of the threshold, so we can check the last bolt is what does it.
	var/bolts_needed = HARDLIGHT_DRILL_REQUIRED / HARDLIGHT_DRILL_PER_BOLT
	for(var/i in 1 to bolts_needed - 1)
		field.register_drill_hit(drill)

	TEST_ASSERT(!field.breached, "The field should not breach before the drill threshold.")
	TEST_ASSERT_EQUAL(core.get_priority_threat(), drill, "An active drill should outrank every room on the core's list.")

	field.register_drill_hit(drill)
	TEST_ASSERT(field.breached, "Reaching HARDLIGHT_DRILL_REQUIRED should breach the field.")
	TEST_ASSERT(!field.density, "A breached field should not be in the way.")
	TEST_ASSERT_EQUAL(core.phase, HARDLIGHT_PHASE_BREACHED, "Breaching the field should push the core to its next phase.")
	TEST_ASSERT(isnull(core.get_priority_threat()), "A finished drill should stop claiming the core's attention.")

	// A hole anywhere is a hole in the whole ring. Leaving the undrilled panels standing would ask
	// the crew to repeat a solved objective, and the core has already moved past the phase anyway.
	TEST_ASSERT(QDELETED(sibling), "Breaching one panel should take the rest of the ring with it.")
	TEST_ASSERT(QDELETED(field), "The drilled panel should go the same way as the ring it was part of.")
	TEST_ASSERT(!(sibling in GLOB.hardlight_containments), "A collapsed panel should drop out of the registry.")

	// Progress decays rather than resetting, so a lost round of defence costs ground and no more.
	var/obj/machinery/hardlight_containment/second = allocate(/obj/machinery/hardlight_containment, home)
	second.register_drill_hit(drill)
	var/banked = second.drill_progress
	TEST_ASSERT(banked > 0, "A landed bolt should bank progress.")

	COOLDOWN_RESET(second, drill_window)
	second.process(1)
	TEST_ASSERT_EQUAL(second.drill_progress, banked - HARDLIGHT_DRILL_DECAY, "An idle drill should bleed progress, not lose it.")

	// An emitter bolt is not the same thing as an emitter. Anything else sparks off and banks
	// nothing, so the phase cannot be satisfied by whatever happens to be in somebody's holster.
	var/obj/machinery/hardlight_containment/third = allocate(/obj/machinery/hardlight_containment, home)
	var/atom/not_an_emitter = core
	third.register_drill_hit(not_an_emitter)
	TEST_ASSERT_EQUAL(third.drill_progress, 0, "Only an emitter should bank drill progress.")
	TEST_ASSERT(isnull(third.driller_ref?.resolve()), "A rejected bolt should not nominate anything for the unit to chase.")

/// The racks hold a typepath until the matrix comes out, and then they do not hold it twice.
/datum/unit_test/hardlight/garrison_wake

/datum/unit_test/hardlight/garrison_wake/Run()
	var/turf/home = run_loc_floor_bottom_left
	var/obj/machinery/hardlight_command_core/core = allocate(/obj/machinery/hardlight_command_core, home)
	core.set_phase(HARDLIGHT_PHASE_BREACHED)

	var/obj/structure/fluff/cryostasis_pod/dormant/rack = allocate(/obj/structure/fluff/cryostasis_pod/dormant, home)
	TEST_ASSERT(!rack.woken, "A rack should start sealed.")
	TEST_ASSERT(length(rack.garrison_pool), "A rack with nothing in it is set dressing, not a garrison.")

	core.matrix_extracted(null)
	TEST_ASSERT(rack.woken, "Pulling the matrix should claim every rack on the core's Z.")

	// Opening is what actually puts something in the room; claiming only schedules it.
	rack.wake()
	var/mob/living/released = locate(/mob/living/basic) in home
	TEST_ASSERT(!isnull(released), "Opening a rack should release whatever typepath it was holding.")
	TEST_ASSERT(released.type in rack.garrison_pool, "A rack should only ever release something from its own pool.")
	qdel(released)

	// Every row of the weight table has to be reachable. A pool that in practice only ever lands on
	// its heaviest entries is not a mix, and nothing about a spawn would say so at a glance. Three
	// hundred rolls against the rarest weight here makes a false failure vanishingly unlikely.
	var/list/seen = list()
	for(var/i in 1 to 300)
		seen |= pick_weight(rack.garrison_pool)
	TEST_ASSERT_EQUAL(length(seen), length(rack.garrison_pool), "Every chassis in the pool should be reachable by the roll.")

	// Fixed racks have to actually be fixed rather than inheriting the mix, or a mapper asking for
	// a covered corridor gets whatever the table felt like that round.
	var/obj/structure/fluff/cryostasis_pod/dormant/security/fixed = allocate(/obj/structure/fluff/cryostasis_pod/dormant/security, home)
	TEST_ASSERT_EQUAL(length(fixed.garrison_pool), 1, "A fixed rack should hold exactly one thing and roll nothing.")

/// Objective bookkeeping, the tier it feeds, and who can actually hear any of it.
/datum/unit_test/hardlight/voice

/datum/unit_test/hardlight/voice/Run()
	var/turf/home = run_loc_floor_bottom_left
	var/obj/machinery/hardlight_command_core/core = allocate(/obj/machinery/hardlight_command_core, home)

	// Four tiers of stock lines, so the maths below has somewhere to climb to.
	core.idle_lines = list(list("one"), list("two"), list("three"), list("four"))
	core.phase = HARDLIGHT_PHASE_ACTIVE

	TEST_ASSERT_EQUAL(core.taunt_tier(), 1, "A core that has lost nothing should sit on its calmest tier.")

	core.note_objective(HARDLIGHT_OBJECTIVE_KEYS)
	TEST_ASSERT_EQUAL(core.objectives_taken, HARDLIGHT_OBJECTIVE_KEYS, "Noting an objective should record that one flag.")
	TEST_ASSERT_EQUAL(core.taunt_tier(), 2, "Each objective taken should cost the core a tier of composure.")

	// Puzzle machinery fires on interaction, and interactions repeat.
	core.note_objective(HARDLIGHT_OBJECTIVE_KEYS)
	TEST_ASSERT_EQUAL(core.taunt_tier(), 2, "Noting the same objective twice should not climb twice.")

	core.note_objective(HARDLIGHT_OBJECTIVE_CARRIER)
	core.note_objective(HARDLIGHT_OBJECTIVE_EMITTER)
	TEST_ASSERT_EQUAL(core.objectives_taken, HARDLIGHT_OBJECTIVES_ALL, "All three noted should fill the bitfield.")
	TEST_ASSERT_EQUAL(core.taunt_tier(), 4, "Losing all three should reach the last tier.")

	// Breaching pins the tier rather than running off the end of the list.
	core.set_phase(HARDLIGHT_PHASE_BREACHED)
	TEST_ASSERT_EQUAL(core.taunt_tier(), 4, "A breach should pin the top tier, not index past it.")

	// Nothing to speak through is not the same as nothing to say, and the core has to know which
	// it is - a line spent on a station with no working speakers is a line the crew never hears.
	TEST_ASSERT(!core.broadcast("test"), "A core with no speakers on its Z should report that nothing carried.")

	var/obj/item/radio/intercom/hardlight/speaker = allocate(/obj/item/radio/intercom/hardlight, home)
	TEST_ASSERT(speaker.is_on(), "A site speaker should map in live without being told to.")
	TEST_ASSERT(core.broadcast("test"), "A live speaker on our Z should carry a line.")

	speaker.set_on(FALSE)
	TEST_ASSERT(!core.broadcast("test"), "A speaker the crew has switched off should not carry anything.")

/// A tether is the body's reach. Walking off the plate, or hopping to another, has to let go.
/datum/unit_test/hardlight/tether_releases

/datum/unit_test/hardlight/tether_releases/Run()
	var/turf/home = run_loc_floor_bottom_left
	var/turf/away = locate(home.x + HARDLIGHT_TETHER_RANGE + 1, home.y, home.z)
	TEST_ASSERT(!isnull(away) && !isclosedturf(away), "Need a walkable tile just past tether range.")

	var/obj/machinery/hardlight_projector/pad = allocate(/obj/machinery/hardlight_projector, home)
	var/mob/living/basic/hardlight_avatar/avatar = allocate(/mob/living/basic/hardlight_avatar, home)
	avatar.set_pad(pad)

	var/mob/living/carbon/human/victim = allocate(/mob/living/carbon/human/consistent, home)
	var/obj/item/restraints/legcuffs/hardlight_tether/cuff = allocate(/obj/item/restraints/legcuffs/hardlight_tether, home, victim, pad, avatar)
	TEST_ASSERT(!QDELETED(cuff), "A live pad and a body on it should throw a tether.")
	TEST_ASSERT_EQUAL(victim.legcuffed, cuff, "The victim should be wearing the tether.")

	avatar.forceMove(away)
	TEST_ASSERT(QDELETED(cuff), "Walking the body off the plate should drop the tether.")
	TEST_ASSERT(isnull(victim.legcuffed), "A dropped tether should leave the victim uncuffed.")

	avatar.forceMove(home)
	avatar.set_pad(pad)
	var/obj/item/restraints/legcuffs/hardlight_tether/second = allocate(/obj/item/restraints/legcuffs/hardlight_tether, home, victim, pad, avatar)
	TEST_ASSERT(!QDELETED(second), "Re-applying on a returned body should hold.")

	var/turf/next_tile = get_step(home, EAST)
	TEST_ASSERT(!isnull(next_tile) && !isclosedturf(next_tile), "Need a neighbouring tile for a one-step hop.")
	var/obj/machinery/hardlight_projector/other = allocate(/obj/machinery/hardlight_projector, next_tile)
	avatar.forceMove(next_tile)
	TEST_ASSERT(!QDELETED(second), "A one-tile step is still inside the hold, and should not drop it.")
	avatar.set_pad(other)
	TEST_ASSERT(QDELETED(second), "Handing the body to another plate should drop the old tether.")
