// MODULE ID: OVERMAP
// Paces every shipyard fabricator against one shared construction budget.

/**
 * Runs active shipyard builds, and only active ones.
 *
 * Printing a ship is a stream of turf changes and machine initializations, so
 * several yards working at once would land that whole stream in whichever
 * subsystem ran them. Each fire hands out one mutation budget and one hull
 * registration across every printer, so a busy shipyard slows each build down
 * instead of stalling the tick.
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

/datum/controller/subsystem/processing/shipyard/fire(resumed = FALSE)
	if(!resumed)
		begin_fire()
		// The walk runs from the end of the list, so whoever went first last time
		// moves to the front and waits its turn.
		if(length(processing) > 1)
			var/first_up = processing[length(processing)]
			processing.len--
			processing.Insert(1, first_up)
	firing = TRUE
	..()
	firing = FALSE

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
