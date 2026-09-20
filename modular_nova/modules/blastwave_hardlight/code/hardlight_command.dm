// MODULE ID: BLASTWAVE_HARDLIGHT
// The thing doing the projecting. Owns which room the body stands in, and how far the fight has got.

/**
 * The command core sitting on `z_level`, if there is one.
 *
 * One site, one core, so this returns the first match rather than a list. Exists so puzzle
 * machinery elsewhere - including in private content that cannot be referenced from here - can push
 * the encounter forward without every set piece needing a mapper-typed id to find the core by.
 */
/proc/hardlight_core_on_z(z_level)
	for(var/obj/machinery/hardlight_command_core/core as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/hardlight_command_core))
		var/turf/core_turf = get_turf(core)
		if(isnull(core_turf) || core_turf.z != z_level)
			continue
		return core
	return null

/**
 * Hard-light command core
 *
 * One per site. Holds the encounter's phase, and every couple of seconds decides which projector
 * should be holding the body up. That decision living here rather than in an AI planning subtree is
 * the single biggest simplification in the whole system: the avatar's controller only ever has to
 * fight whatever is in the room with it, which stock basic-mob behaviours already do well, and
 * "which room" becomes a small scoring problem solved somewhere it can see the whole map.
 *
 * Generic on purpose. It knows about ranked areas and a priority threat; it knows nothing about
 * emitters, intellicards or the Sepulchure. Encounters subtype it and fill in area_priority.
 */
/obj/machinery/hardlight_command_core
	name = "command data core"
	desc = "A sealed lattice of optical storage behind armoured glass. Something in it is still keeping time."
	icon = 'icons/mob/silicon/ai.dmi'
	icon_state = "ai-core"
	density = TRUE
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	use_power = NO_POWER_USE
	processing_flags = START_PROCESSING_ON_INIT
	/// Area typepaths in descending preference. Anywhere unlisted is a valid but last-choice room.
	var/list/area_priority = list()
	/// What we project when we have somewhere to stand.
	var/avatar_type = /mob/living/basic/hardlight_avatar
	/// How far the crew has got. See the HARDLIGHT_PHASE_* defines.
	var/phase = HARDLIGHT_PHASE_DORMANT
	/// The body we currently have up, if any.
	var/mob/living/basic/hardlight_avatar/avatar
	/// Something that outranks every room and every player. Weak: threats are usually destructible.
	var/datum/weakref/priority_threat_ref
	/// Paces our re-scoring. Cheap as it is, there is no reason to do it every machine tick.
	COOLDOWN_DECLARE(rescore_cooldown)
	/// Which of the three phase-two objectives the crew has taken. See HARDLIGHT_OBJECTIVE_*.
	var/objectives_taken = NONE
	/// Unprompted lines, one list per escalation tier. Index one is the calmest. Encounter-set.
	var/list/idle_lines = list()
	/// Lines for taking a specific objective, keyed by hardlight_objective_key().
	var/list/objective_lines = list()
	/// Lines for the beats that are not objectives - waking up, losing containment, being emptied.
	var/list/event_lines = list()
	/// Paces the unprompted lines. Event lines push this out rather than reading it.
	COOLDOWN_DECLARE(taunt_cooldown)

/obj/machinery/hardlight_command_core/Initialize(mapload)
	. = ..()
	update_appearance()
	register_prep_guide_circular()

/obj/machinery/hardlight_command_core/Destroy()
	banish()
	priority_threat_ref = null
	return ..()

/**
 * Screen state, on the stock AI core frame.
 *
 * Reusing the AI core sprite is doing real work here: a crew that walks into this room already
 * knows what they are looking at and roughly what talking to it will cost them. The screen is the
 * only thing that changes, so the room reads its own progress from the doorway.
 */
/obj/machinery/hardlight_command_core/update_overlays()
	. = ..()

	var/screen_state
	switch(phase)
		if(HARDLIGHT_PHASE_DORMANT)
			screen_state = "ai-empty"
		if(HARDLIGHT_PHASE_ACTIVE, HARDLIGHT_PHASE_BREACHED)
			screen_state = "ai-red"

	// Nothing on the glass once the matrix is out. An empty frame is the trophy.
	if(isnull(screen_state))
		return

	var/mutable_appearance/screen = mutable_appearance(icon, screen_state)
	screen.layer = FLOAT_LAYER
	screen.appearance_flags = RESET_COLOR | KEEP_APART
	. += screen
	. += emissive_appearance(icon, screen_state, src, alpha = 255)

/obj/machinery/hardlight_command_core/update_appearance(updates)
	. = ..()
	switch(phase)
		if(HARDLIGHT_PHASE_DORMANT)
			set_light(2, 0.4, LIGHT_COLOR_FAINT_CYAN)
		if(HARDLIGHT_PHASE_ACTIVE, HARDLIGHT_PHASE_BREACHED)
			set_light(3, 0.9, COLOR_RED)
		else
			set_light(0)

/obj/machinery/hardlight_command_core/examine(mob/user)
	. = ..()
	switch(phase)
		if(HARDLIGHT_PHASE_DORMANT)
			. += span_notice("Its status lattice is amber. Whatever runs on it has not been given a reason to wake up.")
		if(HARDLIGHT_PHASE_ACTIVE)
			. += span_warning("The lattice is lit end to end and cycling hard.")
		if(HARDLIGHT_PHASE_BREACHED)
			. += span_warning("Containment is down. The storage lattice is physically exposed.")
		if(HARDLIGHT_PHASE_EXTRACTED)
			. += span_notice("The lattice is dark and the mounts are empty.")

/obj/machinery/hardlight_command_core/process(seconds_per_tick)
	// Asleep before the crew trips it, and gone once the matrix is out. Both ends want no body up.
	if(phase != HARDLIGHT_PHASE_ACTIVE && phase != HARDLIGHT_PHASE_BREACHED)
		banish()
		return

	consider_taunting()

	if(!COOLDOWN_FINISHED(src, rescore_cooldown))
		return
	COOLDOWN_START(src, rescore_cooldown, HARDLIGHT_DIRECTOR_INTERVAL)

	reconsider()

/// Re-picks where the body should be, and moves or drops it accordingly.
/obj/machinery/hardlight_command_core/proc/reconsider()
	var/obj/machinery/hardlight_projector/target = choose_pad()

	if(isnull(target))
		// Every room worth standing in is either empty or has a flat pad. Wait it out.
		banish()
		return

	if(!QDELETED(avatar) && avatar.pad == target)
		return

	manifest_at(target)

/**
 * Picks the projector the body should be standing on, or null for "nowhere worth being".
 *
 * A priority threat - something the encounter has declared more important than any room, such as an
 * emitter actively drilling the core - wins outright. Otherwise the best-ranked room that both
 * contains a player and has a plate with charge left, which is what makes clearing a room mean
 * something: the unit walks away and goes and finds whoever is next.
 *
 * Rooms may carry more than one plate, and the room is only genuinely clear once all of them are
 * flat. Between plates in the same room the nearest one to whoever is standing there wins, so a
 * hall with plates down its length is fought along rather than fought at one end of, and emptying
 * the plate you are standing over buys ground rather than the room.
 *
 * Selection is sticky by HARDLIGHT_REPAD_MARGIN. Pure nearest-wins reads as a twitch when two
 * plates are close to equidistant, and the body should look like it is repositioning deliberately
 * rather than being dragged back and forth by someone shuffling between two tiles.
 */
/obj/machinery/hardlight_command_core/proc/choose_pad()
	var/turf/our_turf = get_turf(src)
	if(isnull(our_turf))
		return null

	var/atom/threat = priority_threat_ref?.resolve()
	if(!isnull(threat))
		var/obj/machinery/hardlight_projector/threat_pad = pad_covering(get_turf(threat))
		if(!isnull(threat_pad))
			return threat_pad

	var/list/occupancy = players_by_area()
	if(!length(occupancy))
		return null

	// The plate we are already standing on, tracked alongside the winner so we can decide whether
	// the winner is enough of an improvement to be worth moving for.
	var/obj/machinery/hardlight_projector/current = QDELETED(avatar) ? null : avatar.pad
	var/current_rank = INFINITY
	var/current_distance = INFINITY

	var/obj/machinery/hardlight_projector/best
	var/best_rank = INFINITY
	var/best_distance = INFINITY

	for(var/datum/component/hardlight_coverage/coverage as anything in hardlight_coverage_on_z(our_turf.z))
		var/obj/machinery/hardlight_projector/candidate = coverage.parent
		if(!istype(candidate) || !candidate.can_project())
			continue

		var/area/candidate_area = coverage.covered_area()
		if(isnull(candidate_area))
			continue

		var/list/occupants = occupancy[candidate_area]
		if(!length(occupants))
			continue

		var/rank = rank_of(candidate_area)
		var/distance = nearest_occupant_distance(candidate, occupants)

		if(candidate == current)
			current_rank = rank
			current_distance = distance

		if(rank < best_rank || (rank == best_rank && distance < best_distance))
			best_rank = rank
			best_distance = distance
			best = candidate

	// Same room, and the rival is not appreciably closer to anyone. Stay put.
	if(!isnull(current) && current != best && current_rank == best_rank && current_distance <= best_distance + HARDLIGHT_REPAD_MARGIN)
		return current

	return best

/// How far `pad` is from the nearest of `occupants`. INFINITY if it is nowhere.
/obj/machinery/hardlight_command_core/proc/nearest_occupant_distance(obj/machinery/hardlight_projector/pad, list/turf/occupants)
	var/turf/pad_turf = get_turf(pad)
	if(isnull(pad_turf))
		return INFINITY

	var/closest = INFINITY
	for(var/turf/occupant as anything in occupants)
		closest = min(closest, get_dist(pad_turf, occupant))
	return closest

/// Where our preference list puts `checked_area`. Unlisted rooms sort after every listed one.
/obj/machinery/hardlight_command_core/proc/rank_of(area/checked_area)
	for(var/index in 1 to length(area_priority))
		if(istype(checked_area, area_priority[index]))
			return index
	return length(area_priority) + 1

/**
 * Live players on our Z, as a list of turfs per area.
 *
 * Turfs rather than a headcount, because plate selection needs to know where in the room people
 * actually are and not merely that somebody is in it.
 *
 * Walks the player list rather than mobs_in_area_type(), which sweeps every living mob in the world
 * once per area type asked about. There are never many players and this runs on a timer.
 */
/obj/machinery/hardlight_command_core/proc/players_by_area()
	var/list/occupancy = list()
	var/turf/our_turf = get_turf(src)
	if(isnull(our_turf))
		return occupancy

	for(var/mob/living/player as anything in GLOB.player_list)
		if(!isliving(player) || player.stat == DEAD || QDELETED(player))
			continue

		var/turf/player_turf = get_turf(player)
		if(isnull(player_turf) || player_turf.z != our_turf.z)
			continue

		var/area/player_area = get_area(player_turf)
		if(isnull(player_area))
			continue

		var/list/turfs = occupancy[player_area]
		if(isnull(turfs))
			turfs = list()
			occupancy[player_area] = turfs
		turfs += player_turf

	return occupancy

/// The nearest projector to `location` that could hold a body standing there, if any has the charge.
/obj/machinery/hardlight_command_core/proc/pad_covering(turf/location)
	if(isnull(location))
		return null

	var/obj/machinery/hardlight_projector/closest
	var/closest_distance = INFINITY

	for(var/datum/component/hardlight_coverage/coverage as anything in hardlight_coverage_on_z(location.z))
		if(!coverage.covers_turf(location))
			continue
		var/obj/machinery/hardlight_projector/candidate = coverage.parent
		if(!istype(candidate) || !candidate.can_project())
			continue

		// Coverage is area-wide, so a room with several plates offers several valid answers here.
		// The one standing closest to the thing we care about is the one that should be holding it.
		var/distance = get_dist(get_turf(candidate), location)
		if(distance >= closest_distance)
			continue

		closest_distance = distance
		closest = candidate

	return closest

/// Stands a body up on `target`, moving the existing one if we already have one out.
/obj/machinery/hardlight_command_core/proc/manifest_at(obj/machinery/hardlight_projector/target)
	if(QDELETED(target) || !target.can_project())
		return FALSE

	var/turf/destination = get_turf(target)
	if(isnull(destination))
		return FALSE

	if(QDELETED(avatar))
		avatar = new avatar_type(destination)
		RegisterSignal(avatar, COMSIG_QDELETING, PROC_REF(on_avatar_deleted))
	else
		// forceMove skips COMSIG_MOVABLE_PRE_MOVE, so the avatar's own confinement check does not
		// fight us here. Every other kind of movement it makes still has to stay in its room.
		avatar.visible_message(span_warning("[avatar] folds in on itself and is gone."))
		avatar.forceMove(destination)
		avatar.visible_message(span_danger("[avatar] unfolds out of [target]."))

	avatar.set_pad(target)
	push_threat_to_avatar()
	do_sparks(2, FALSE, target)
	return TRUE

/// Drops whatever body we have out. Safe to call when we have none.
/obj/machinery/hardlight_command_core/proc/banish()
	if(QDELETED(avatar))
		return
	avatar.derez()

/obj/machinery/hardlight_command_core/proc/on_avatar_deleted(datum/source)
	SIGNAL_HANDLER
	avatar = null

/**
 * Declares something more important than the room-preference list.
 *
 * Kept as a general slot rather than hardcoding the emitter it was written for, so later objectives
 * can claim the unit's attention the same way without touching this file.
 */
/obj/machinery/hardlight_command_core/proc/set_priority_threat(atom/threat)
	priority_threat_ref = isnull(threat) ? null : WEAKREF(threat)
	push_threat_to_avatar()
	// Do not wait out the timer. The whole point of a threat is that it is urgent.
	if(phase == HARDLIGHT_PHASE_ACTIVE || phase == HARDLIGHT_PHASE_BREACHED)
		reconsider()

/// Whatever currently outranks the room preference list, or null.
/obj/machinery/hardlight_command_core/proc/get_priority_threat()
	return priority_threat_ref?.resolve()

/// Hands the current threat down to the avatar's targeting, which prefers it over living targets.
/obj/machinery/hardlight_command_core/proc/push_threat_to_avatar()
	if(QDELETED(avatar))
		return
	avatar.ai_controller?.set_blackboard_key(BB_HARDLIGHT_PRIORITY_TARGET, priority_threat_ref?.resolve())

/// Moves the encounter forward. Idempotent, so puzzle machinery can call it without coordinating.
/obj/machinery/hardlight_command_core/proc/set_phase(new_phase)
	if(new_phase == phase)
		return

	var/old_phase = phase
	phase = new_phase
	update_appearance()
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_HARDLIGHT_PHASE_CHANGED, src, new_phase, old_phase)

	if(phase == HARDLIGHT_PHASE_ACTIVE)
		// Skip the timer so waking the unit is immediately felt rather than felt two seconds later.
		COOLDOWN_RESET(src, rescore_cooldown)
		reconsider()
		speak_event(event_lines?["woken"])
	else if(phase == HARDLIGHT_PHASE_BREACHED)
		speak_event(event_lines?["breached"])
	else if(phase == HARDLIGHT_PHASE_EXTRACTED)
		// Before the banish, because after it there is nothing left to say anything.
		speak_event(event_lines?["extracted"])
		banish()

/// Called by whatever pulls the matrix out. Ends the boss and wakes whatever was waiting on it.
/obj/machinery/hardlight_command_core/proc/matrix_extracted(mob/living/extractor)
	if(phase == HARDLIGHT_PHASE_EXTRACTED)
		return FALSE

	set_phase(HARDLIGHT_PHASE_EXTRACTED)
	SEND_GLOBAL_SIGNAL(COMSIG_GLOB_HARDLIGHT_MATRIX_EXTRACTED, src, extractor)
	return TRUE
