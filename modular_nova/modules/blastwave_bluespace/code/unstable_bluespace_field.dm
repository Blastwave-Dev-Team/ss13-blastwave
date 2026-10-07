// MODULE ID: BLASTWAVE_BLUESPACE
// A world-wide hazard: while any source holds it, every successful teleport hurts and throws loose junk around.
// Deliberately not a /datum/station_trait; those are rolled in the lobby and this is sourced by a machine at runtime.

/// Chance, in percent, that an arriving mob is scattered off its intended tile.
#define UNSTABLE_BLUESPACE_SCATTER_CHANCE 20
/// Chance, in percent, that an arriving mob is knocked down.
#define UNSTABLE_BLUESPACE_KNOCKDOWN_CHANCE 25
/// How far from the arrival tile loose objects get picked up and thrown.
#define UNSTABLE_BLUESPACE_HURL_RANGE 2

/// The single live field. Null whenever nothing is sourcing it.
GLOBAL_DATUM(unstable_bluespace_field, /datum/unstable_bluespace_field)

/**
 * Registers source as holding the global unstable bluespace field up, creating the field if it is the first one.
 *
 * Arguments:
 * * source - the datum responsible. Must be passed back to remove_unstable_bluespace_source().
 */
/proc/add_unstable_bluespace_source(datum/source)
	if(isnull(source))
		return FALSE
	if(isnull(GLOB.unstable_bluespace_field))
		GLOB.unstable_bluespace_field = new
	return GLOB.unstable_bluespace_field.add_source(source)

/// Releases source's hold on the global field, tearing the field down if it was the last one.
/proc/remove_unstable_bluespace_source(datum/source)
	if(isnull(source) || isnull(GLOB.unstable_bluespace_field))
		return FALSE
	return GLOB.unstable_bluespace_field.remove_source(source)

/// Whether the world is currently under an unstable bluespace field.
/proc/is_bluespace_unstable()
	return !isnull(GLOB.unstable_bluespace_field)

/datum/unstable_bluespace_field
	/// Datums keeping this field alive. The field deletes itself when this empties.
	var/list/sources = list()

/datum/unstable_bluespace_field/New()
	. = ..()
	RegisterSignal(SSdcs, COMSIG_GLOB_MOVABLE_POST_TELEPORT, PROC_REF(on_teleport))

/datum/unstable_bluespace_field/Destroy(force)
	UnregisterSignal(SSdcs, COMSIG_GLOB_MOVABLE_POST_TELEPORT)
	sources.Cut()
	if(GLOB.unstable_bluespace_field == src)
		GLOB.unstable_bluespace_field = null
	return ..()

/datum/unstable_bluespace_field/proc/add_source(datum/source)
	if(source in sources)
		return FALSE
	sources += source
	RegisterSignal(source, COMSIG_QDELETING, PROC_REF(on_source_deleted))
	return TRUE

/datum/unstable_bluespace_field/proc/remove_source(datum/source)
	if(!(source in sources))
		return FALSE
	sources -= source
	UnregisterSignal(source, COMSIG_QDELETING)
	if(!length(sources))
		qdel(src)
	return TRUE

/// A source was deleted while still holding the field. Treat it as having switched off.
/datum/unstable_bluespace_field/proc/on_source_deleted(datum/source)
	SIGNAL_HANDLER
	remove_source(source)

/**
 * Every successful do_teleport() in the world routes through here.
 *
 * Skips forced teleports (admin and map escapes), observers, and the catch-all FREE channel so that internal
 * plumbing like deathmatch and virtual domains does not start mangling people.
 */
/datum/unstable_bluespace_field/proc/on_teleport(datum/source, atom/movable/teleported, turf/destination, channel, forced)
	SIGNAL_HANDLER

	if(forced || channel == TELEPORT_CHANNEL_FREE)
		return
	if(QDELETED(teleported) || isobserver(teleported))
		return
	if(!isturf(destination) || is_reserved_level(destination.z))
		return

	do_sparks(3, FALSE, destination)
	hurl_loose_objects(destination)

	if(!isliving(teleported))
		return

	var/mob/living/arriver = teleported
	if(HAS_TRAIT(arriver, TRAIT_GODMODE))
		return

	arriver.apply_damage(rand(5, 15), BRUTE, spread_damage = TRUE)
	arriver.apply_damage(rand(5, 15), BURN, spread_damage = TRUE)
	to_chat(arriver, span_userdanger("Bluespace tears at you on the way through!"))

	if(prob(UNSTABLE_BLUESPACE_KNOCKDOWN_CHANCE))
		arriver.Knockdown(2 SECONDS)

	if(prob(UNSTABLE_BLUESPACE_SCATTER_CHANCE))
		scatter(arriver, destination)

/// Throws loose objects around the arrival tile, which is the "the field hurls things" beat.
/datum/unstable_bluespace_field/proc/hurl_loose_objects(turf/epicenter)
	for(var/obj/item/loose in range(1, epicenter))
		if(loose.anchored || !isturf(loose.loc))
			continue
		var/turf/fling_to = get_random_turf_in_range(epicenter, UNSTABLE_BLUESPACE_HURL_RANGE)
		if(isnull(fling_to))
			continue
		loose.throw_at(fling_to, UNSTABLE_BLUESPACE_HURL_RANGE, 2)

/// Nudges an arriving mob off its intended tile so arrivals feel unreliable rather than merely painful.
/datum/unstable_bluespace_field/proc/scatter(mob/living/arriver, turf/arrived_at)
	var/turf/scatter_to = get_random_turf_in_range(arrived_at, 1)
	if(isnull(scatter_to) || scatter_to == arrived_at)
		return
	arriver.forceMove(scatter_to)
	arriver.visible_message(span_warning("[arriver] lurches sideways out of nowhere!"))

/// Picks a random open, unblocked turf within radius of center. Null if there is nowhere sane to go.
/datum/unstable_bluespace_field/proc/get_random_turf_in_range(turf/center, radius)
	var/list/candidates = list()
	for(var/turf/open/candidate in range(radius, center))
		if(candidate == center || candidate.is_blocked_turf(exclude_mobs = TRUE))
			continue
		candidates += candidate
	return length(candidates) ? pick(candidates) : null

#undef UNSTABLE_BLUESPACE_SCATTER_CHANCE
#undef UNSTABLE_BLUESPACE_KNOCKDOWN_CHANCE
#undef UNSTABLE_BLUESPACE_HURL_RANGE
