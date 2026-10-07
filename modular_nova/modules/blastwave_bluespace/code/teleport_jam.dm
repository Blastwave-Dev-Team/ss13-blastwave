// MODULE ID: BLASTWAVE_BLUESPACE
// Bluespace interdiction. Interdicted space refuses every teleport into or out of it.
// Static maps declare ZTRAIT_NO_TELEPORT in their JSON; runtime sources register through add_teleport_jam().

/// Assoc list of "[z]" -> /datum/teleport_jam_zone, holding only the Zs something is actually jamming.
GLOBAL_LIST_EMPTY(teleport_jam_zones)

/**
 * Bluespace interdiction coverage for one Z
 *
 * Owns every source jamming that Z and answers coverage queries about it. Sources are refcounted, so
 * two overlapping jammers each have to release before the space they shared opens back up.
 *
 * Everything here is held weakly. This datum hangs off a global for the whole round, so a hard
 * reference to a machine would keep that machine alive past its own deletion and turn every
 * destroyed jammer into a hard delete.
 *
 * Whole-Z claims are kept in their own list. A single tier-four array makes position irrelevant, and
 * that is by far the common case, so it should not cost a walk over the ranged sources to notice.
 */
/datum/teleport_jam_zone
	/// The Z we cover.
	var/z_level
	/// /datum/weakref -> tile radius, covering every claim we hold. Bookkeeping for release.
	var/list/claims = list()
	/// Ranged claims only, widest first. The biggest bubble is the likeliest to hold any given tile.
	var/list/ordered_claims = list()
	/// Claims covering the level outright, so a tier four array answers without measuring anything.
	var/list/whole_z_claims = list()

/datum/teleport_jam_zone/New(z_level)
	. = ..()
	src.z_level = z_level

/**
 * The claim `source` holds on us, if any.
 *
 * Matches on REF text rather than resolving, because a machine releasing from inside its own
 * Destroy() is already QDELETED: WEAKREF() would hand back null and resolve() would not find it.
 */
/datum/teleport_jam_zone/proc/find_claim(datum/source)
	var/source_ref = REF(source)
	for(var/datum/weakref/claim as anything in claims)
		if(claim.reference == source_ref)
			return claim
	return null

/// Records source as jamming us out to `range`, replacing any claim it already held.
/datum/teleport_jam_zone/proc/add_claim(datum/source, range)
	var/datum/weakref/claim = WEAKREF(source)
	if(isnull(claim))
		return

	drop_claim(find_claim(source))
	claims[claim] = range
	if(range == JAM_RANGE_WHOLE_Z)
		whole_z_claims += claim
	else
		insert_ordered(claim, range)

/// Drops source's claim, sweeping any dead ones out with it. Returns TRUE if that emptied us out.
/datum/teleport_jam_zone/proc/remove_claim(datum/source)
	drop_claim(find_claim(source))

	// Mutation is off the hot path, so it is the right moment to clear out sources that went away
	// without releasing. Without this a leaked claim would pin the zone open for the whole round.
	for(var/i in length(claims) to 1 step -1)
		var/datum/weakref/claim = claims[i]
		if(isnull(claim.resolve()))
			drop_claim(claim)

	return !length(claims)

/// Forgets a single claim, whichever list it lives in.
/datum/teleport_jam_zone/proc/drop_claim(datum/weakref/claim)
	if(isnull(claim) || !(claim in claims))
		return
	if(claims[claim] == JAM_RANGE_WHOLE_Z)
		whole_z_claims -= claim
	else
		ordered_claims -= claim
	claims -= claim

/// Slots a claim into ordered_claims so the list stays sorted widest radius first.
/datum/teleport_jam_zone/proc/insert_ordered(datum/weakref/claim, range)
	for(var/i in 1 to length(ordered_claims))
		var/datum/weakref/other = ordered_claims[i]
		if(claims[other] < range)
			ordered_claims.Insert(i, claim)
			return
	ordered_claims += claim

/**
 * Whether our interdiction actually reaches `location`, which must already be on our Z.
 *
 * Claims whose source has gone away simply never match. Sweeping them is left to the next mutation
 * so that this stays a pure read, which is what is_teleport_jammed() promises its callers.
 */
/datum/teleport_jam_zone/proc/covers(turf/location)
	for(var/datum/weakref/claim as anything in whole_z_claims)
		if(!isnull(claim.resolve()))
			return TRUE

	for(var/datum/weakref/claim as anything in ordered_claims)
		var/datum/source = claim.resolve()
		if(isnull(source))
			continue
		var/turf/source_turf = get_turf(source)
		// A source that wandered off our Z keeps its claim but stops covering anything here; the
		// machines re-register on z change, so this only catches the gap in between.
		if(isnull(source_turf) || source_turf.z != z_level)
			continue
		if(get_dist(location, source_turf) <= claims[claim])
			return TRUE

	return FALSE

/**
 * Registers source as jamming bluespace on z_level.
 *
 * Calling this again for the same source replaces its range, which is how a machine reports a
 * part upgrade. Sources must be passed back to remove_teleport_jam() to release.
 *
 * Arguments:
 * * z_level - the Z to jam.
 * * source - the datum responsible.
 * * range - tile radius around the source, or JAM_RANGE_WHOLE_Z to cover the level. Anything without
 * a turf is whole-Z regardless, since there is no position to measure a radius from.
 */
/proc/add_teleport_jam(z_level, datum/source, range = JAM_RANGE_WHOLE_Z)
	if(!isnum(z_level) || z_level < 1 || isnull(source))
		return FALSE

	var/key = "[z_level]"
	var/datum/teleport_jam_zone/zone = GLOB.teleport_jam_zones[key]
	if(isnull(zone))
		zone = new /datum/teleport_jam_zone(z_level)
		GLOB.teleport_jam_zones[key] = zone

	zone.add_claim(source, isnull(get_turf(source)) ? JAM_RANGE_WHOLE_Z : range)
	return TRUE

/// Releases source's claim on z_level. See add_teleport_jam().
/proc/remove_teleport_jam(z_level, datum/source)
	if(!isnum(z_level) || z_level < 1 || isnull(source))
		return FALSE

	var/key = "[z_level]"
	var/datum/teleport_jam_zone/zone = GLOB.teleport_jam_zones[key]
	if(isnull(zone))
		return FALSE

	if(zone.remove_claim(source))
		GLOB.teleport_jam_zones -= key
		qdel(zone)
	return TRUE

/// Whether bluespace at `location` is interdicted, by a runtime source in range or by its level's traits.
/proc/is_teleport_jammed(atom/location)
	SHOULD_BE_PURE(TRUE)

	var/turf/our_turf = get_turf(location)
	if(isnull(our_turf))
		return FALSE

	// A level that declares itself dark has no machine to look up, so it is dark everywhere.
	if(SSmapping.level_trait(our_turf.z, ZTRAIT_NO_TELEPORT))
		return TRUE

	// No zone datum means nothing is jamming this Z at all, which is the answer almost every time.
	var/datum/teleport_jam_zone/zone = GLOB.teleport_jam_zones["[our_turf.z]"]
	if(isnull(zone))
		return FALSE

	return zone.covers(our_turf)
