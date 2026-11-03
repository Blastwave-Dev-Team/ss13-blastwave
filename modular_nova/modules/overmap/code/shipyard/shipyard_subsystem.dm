// MODULE ID: OVERMAP
// Paces every shipyard fabricator against one shared construction budget, and
// every hull walk against one shared slice of the tick.

/**
 * Runs active shipyard builds, and only active ones, and the hull walks that
 * surveys and filings wait on.
 *
 * Printing a ship is a stream of turf changes and machine initializations, so
 * several yards working at once would land that whole stream in whichever
 * subsystem ran them. Each fire hands out one mutation budget and one hull
 * registration across every printer, so a busy shipyard slows each build down
 * instead of stalling the tick.
 *
 * A walk reads every atom aboard a hull, which on a large ship is far more
 * than one tick's worth. Walks get their own slice of each fire, and while any
 * are queued the subsystem pauses rather than finishing, so the MC resumes it
 * on the very next tick instead of a full `wait` later.
 */
PROCESSING_SUBSYSTEM_DEF(shipyard)
	name = "Shipyard"
	wait = 1 SECONDS
	stat_tag = "SY"
	/// Mutation cost still unspent this fire.
	var/remaining_budget = SHIPYARD_MUTATION_BUDGET_PER_FIRE
	/// Whether a printer registered its hull as a shuttle this fire.
	var/registration_used = FALSE
	/// Whether printers are being run by this subsystem, rather than called directly.
	var/firing = FALSE
	/// Hull walks still describing, oldest first.
	var/list/datum/ship_teardown/walks = list()
	/// Whether walks are being advanced by this subsystem, rather than run directly.
	var/walking = FALSE
	/// TICK_USAGE when walks began their share of the current tick.
	var/walk_started_at = 0
	/// Whether this cycle's printers have been started, so a resumed fire continues them.
	var/printers_started = FALSE

/datum/controller/subsystem/processing/shipyard/fire(resumed = FALSE)
	if(!resumed)
		begin_fire()
		printers_started = FALSE
		// The walk runs from the end of the list, so whoever went first last time
		// moves to the front and waits its turn.
		if(length(processing) > 1)
			var/first_up = processing[length(processing)]
			processing.len--
			processing.Insert(1, first_up)
	advance_walks()
	if(state != SS_RUNNING)
		return
	firing = TRUE
	..(printers_started)
	firing = FALSE
	printers_started = TRUE
	if(state == SS_RUNNING && length(walks))
		pause()

/// Advance queued walks until they are done or their share of this tick is spent.
/datum/controller/subsystem/processing/shipyard/proc/advance_walks()
	walking = TRUE
	walk_started_at = TICK_USAGE
	while(length(walks))
		var/datum/ship_teardown/teardown = walks[1]
		if(QDELETED(teardown) || teardown.advance())
			walks -= teardown
		if(TICK_CHECK)
			pause()
			break
		if(walk_should_yield())
			break
	walking = FALSE

/// Whether a walk should hand the rest of its turn back. Direct walks never yield.
/datum/controller/subsystem/processing/shipyard/proc/walk_should_yield()
	return walking && (TICK_CHECK || TICK_USAGE - walk_started_at > SHIPYARD_WALK_TICK_BUDGET)

/**
 * Describe `teardown`'s hull on this subsystem's clock, sleeping until it is
 * done. Without a subsystem to run it - before init, or with the MC stopped -
 * it is walked on the spot instead.
 */
/datum/controller/subsystem/processing/shipyard/proc/run_walk(datum/ship_teardown/teardown)
	if(!initialized || !can_fire || (ss_flags & SS_NO_FIRE))
		teardown.advance()
		return
	walks += teardown
	// Someone is waiting on this, so it starts next tick rather than next cycle.
	next_fire = min(next_fire, world.time)
	var/deadline = world.time + SHIPYARD_WALK_TIMEOUT
	UNTIL(teardown.walk_done || QDELETED(teardown) || world.time > deadline)
	if(!teardown.walk_done && !QDELETED(teardown))
		walks -= teardown
		teardown.refuse(SHIPYARD_REFUSAL_UNFILABLE, "the hull walk timed out")
		teardown.walk_done = TRUE

/// Hands out a fresh budget and registration slot.
/datum/controller/subsystem/processing/shipyard/proc/begin_fire()
	remaining_budget = SHIPYARD_MUTATION_BUDGET_PER_FIRE
	registration_used = FALSE

/// Spends `cost` from this fire's budget. Direct calls outside a fire are never capped.
/datum/controller/subsystem/processing/shipyard/proc/try_consume(cost)
	if(!firing)
		return TRUE
	if(cost > remaining_budget)
		return FALSE
	remaining_budget -= cost
	return TRUE

/// Claims this fire's single hull registration. Direct calls outside a fire are never capped.
/datum/controller/subsystem/processing/shipyard/proc/try_register()
	if(!firing)
		return TRUE
	if(registration_used)
		return FALSE
	registration_used = TRUE
	return TRUE

/// Whether a printer should hand the rest of its turn back to the tick.
/datum/controller/subsystem/processing/shipyard/proc/should_yield()
	return firing && (remaining_budget <= 0 || TICK_CHECK)
