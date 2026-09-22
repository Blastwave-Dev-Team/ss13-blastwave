// MODULE ID: BLASTWAVE_HARDLIGHT
// How the thing in the middle of the station talks to the people walking around it.

/// Every hard-light speaker in the world. Cores need to find the ones on their own Z.
GLOBAL_LIST_EMPTY(hardlight_intercoms)

/**
 * Site speaker
 *
 * A wall intercom the command core talks through. It is a prop, not a radio: nothing is
 * transmitted and nothing is received, the core simply makes it speak.
 *
 * That is a deliberate choice over wiring it to the radio subsystem. Intercoms default to
 * `subspace_transmission = FALSE`, so on a Z with no telecomms a real broadcast falls through to
 * `backup_transmission()` two seconds later, and that path excludes headsets - the only things
 * that would end up speaking are other intercoms. Which is the outcome we want anyway, so driving
 * them directly buys the same result without the lag or the dependency on hardware the site does
 * not have.
 *
 * Starts switched on, which needs no declaring - radios do by default, and `on` is private to the
 * radio anyway. It can be switched off, though, and that matters: a crew that has had enough of
 * being talked at should be able to do something about it, and finding out that they can is its
 * own small beat.
 */
/obj/item/radio/intercom/hardlight
	name = "site address speaker"
	desc = "A hardwired wall speaker on a bus with one thing on it. There is no handset and no \
		dial - whatever talks through this decided a long time ago that it would not be answered."
	/// Nothing is listening on the other end, and nothing here should leak onto a real channel.
	subspace_transmission = FALSE

/obj/item/radio/intercom/hardlight/Initialize(mapload, ...)
	. = ..()
	set_broadcasting(FALSE)
	set_listening(FALSE)
	GLOB.hardlight_intercoms += src

/obj/item/radio/intercom/hardlight/Destroy()
	GLOB.hardlight_intercoms -= src
	return ..()

/// Wallmounts are mapped by direction, and the macro only generates for the type it is handed.
/// The offset matches INTERCOM_OFFSET, which is undef'd at the bottom of the file that owns it.
MAPPING_DIRECTIONAL_HELPERS(/obj/item/radio/intercom/hardlight, 27)

/// Every switched-on speaker sitting on `z_level`.
/proc/hardlight_intercoms_on_z(z_level)
	var/list/found = list()
	for(var/obj/item/radio/intercom/hardlight/speaker as anything in GLOB.hardlight_intercoms)
		var/turf/speaker_turf = get_turf(speaker)
		if(isnull(speaker_turf) || speaker_turf.z != z_level || !speaker.is_on())
			continue
		found += speaker
	return found

/*
 * Broadcasting
 */

/**
 * Says `line` out of every live speaker on our Z.
 *
 * Returns TRUE if anything actually carried it. The core uses that to decide whether a line was
 * spent or should be tried again later - a taunt nobody could hear is not a taunt, and burning
 * the good ones into a dead station would leave the crew with the dregs.
 */
/obj/machinery/hardlight_command_core/proc/broadcast(line)
	var/turf/our_turf = get_turf(src)
	if(isnull(our_turf) || !length(line))
		return FALSE

	var/list/speakers = hardlight_intercoms_on_z(our_turf.z)
	if(!length(speakers))
		return FALSE

	for(var/obj/item/radio/intercom/hardlight/speaker as anything in speakers)
		playsound(speaker, 'sound/machines/terminal/terminal_on.ogg', 25, FALSE)
		speaker.say(line, spans = list(SPAN_ROBOT))

	return TRUE

/// Whether anybody is alive on our Z to be talked at. Nothing monologues to an empty station.
/obj/machinery/hardlight_command_core/proc/has_audience()
	var/turf/our_turf = get_turf(src)
	if(isnull(our_turf))
		return FALSE

	for(var/mob/living/player as anything in GLOB.player_list)
		if(!isliving(player) || player.stat >= UNCONSCIOUS || QDELETED(player))
			continue
		var/turf/player_turf = get_turf(player)
		if(!isnull(player_turf) && player_turf.z == our_turf.z)
			return TRUE

	return FALSE

/*
 * Escalation
 */

/**
 * How wound up the unit currently is, as an index into `idle_lines`.
 *
 * One step per phase-two objective taken off it, which is what makes the escalation legible: the
 * crew can hear that the last thing they did landed. Breaching containment pins it at the top
 * rather than adding a step, because by then there is nothing left to bargain with.
 */
/obj/machinery/hardlight_command_core/proc/taunt_tier()
	if(phase >= HARDLIGHT_PHASE_BREACHED)
		return length(idle_lines)

	var/tier = 1
	for(var/flag in list(HARDLIGHT_OBJECTIVE_CARRIER, HARDLIGHT_OBJECTIVE_KEYS, HARDLIGHT_OBJECTIVE_EMITTER))
		if(objectives_taken & flag)
			tier++

	return min(tier, length(idle_lines))

/**
 * Text key for an objective flag.
 *
 * The line tables are var initializers, and DM will only take constant expressions there - so the
 * flags themselves cannot be interpolated into keys at that point. A name each, looked up here.
 */
/proc/hardlight_objective_key(flag)
	switch(flag)
		if(HARDLIGHT_OBJECTIVE_CARRIER)
			return "carrier"
		if(HARDLIGHT_OBJECTIVE_KEYS)
			return "keys"
		if(HARDLIGHT_OBJECTIVE_EMITTER)
			return "emitter"
	return null

/**
 * Records that the crew has taken one of the three things, and says something about it.
 *
 * Idempotent, so the machinery that calls this does not have to track whether it already has.
 * Puzzle set pieces fire on interaction and interactions repeat.
 */
/obj/machinery/hardlight_command_core/proc/note_objective(flag)
	if(objectives_taken & flag)
		return
	objectives_taken |= flag

	speak_event(objective_lines?[hardlight_objective_key(flag)])

/**
 * Says one line from `pool` now, and pushes the idle timer out so it does not tread on itself.
 *
 * Event lines are the ones that carry the encounter, so they jump the queue unconditionally -
 * an event line lost because the small talk timer happened to be up would be the wrong thing to
 * economise on.
 */
/obj/machinery/hardlight_command_core/proc/speak_event(pool)
	if(isnull(pool))
		return

	var/line = islist(pool) ? pick(pool) : pool
	if(!broadcast(line))
		return

	COOLDOWN_START(src, taunt_cooldown, rand(HARDLIGHT_TAUNT_INTERVAL_MIN, HARDLIGHT_TAUNT_INTERVAL_MAX))

/**
 * The unprompted half. Called from the core's own process loop.
 *
 * Silent while dormant - the site is supposed to read as abandoned until the lockdown lifts, and
 * a voice before then gives away that anything is home.
 */
/obj/machinery/hardlight_command_core/proc/consider_taunting()
	if(phase == HARDLIGHT_PHASE_DORMANT || phase == HARDLIGHT_PHASE_EXTRACTED)
		return
	if(!COOLDOWN_FINISHED(src, taunt_cooldown))
		return
	if(!has_audience())
		return

	var/list/pool = LAZYACCESS(idle_lines, taunt_tier())
	if(!length(pool))
		return

	if(!broadcast(pick(pool)))
		return

	COOLDOWN_START(src, taunt_cooldown, rand(HARDLIGHT_TAUNT_INTERVAL_MIN, HARDLIGHT_TAUNT_INTERVAL_MAX))
