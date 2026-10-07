// MODULE ID: BLASTWAVE_HARDLIGHT
// Where a projector can put a body, and whose body it is currently holding up.

/// Every hard-light coverage in the world. Directors need to find pads nobody told them about.
GLOBAL_LIST_EMPTY(hardlight_coverages)

/**
 * Hard-light projection coverage
 *
 * The bookkeeping half of a projector: which tiles it can hold a body on, and whether it is
 * currently holding one. Deliberately knows nothing about charge, power, or combat, so that the
 * machine can own all of that and this can be reused by anything else that projects a body onto a
 * pad. Coverage is area-scoped rather than radial, matching how holopads decide where a hologram
 * may stand, which is also what gives the encounter its "it cannot follow you out of the room" rule.
 */
/datum/component/hardlight_coverage
	/// The body we are currently projecting. Weak: a gibbed avatar must not keep itself alive through us.
	var/datum/weakref/avatar_ref

/datum/component/hardlight_coverage/Initialize()
	. = ..()
	if(!ismachinery(parent))
		return COMPONENT_INCOMPATIBLE
	GLOB.hardlight_coverages += src

/datum/component/hardlight_coverage/Destroy(force)
	GLOB.hardlight_coverages -= src
	avatar_ref = null
	return ..()

/// The area this projector serves. Null if it is nowhere, which happens mid-deletion.
/datum/component/hardlight_coverage/proc/covered_area()
	var/turf/our_turf = get_turf(parent)
	return isnull(our_turf) ? null : get_area(our_turf)

/**
 * Whether we can hold a body standing on `location`.
 *
 * Area identity rather than area typepath, so two rooms built from the same area type do not
 * silently pool their coverage. This is the same test holopads use in validate_location().
 */
/datum/component/hardlight_coverage/proc/covers_turf(turf/location)
	if(isnull(location))
		return FALSE

	var/area/our_area = covered_area()
	if(isnull(our_area))
		return FALSE

	return get_area(location) == our_area

/// The body we are projecting, or null. Resolving here means callers never see a stale avatar.
/datum/component/hardlight_coverage/proc/get_avatar()
	return avatar_ref?.resolve()

/// Whether something is already standing on us.
/datum/component/hardlight_coverage/proc/is_claimed()
	return !isnull(get_avatar())

/// Takes ownership of `avatar`. Replaces any previous claim, which is how a relocation hands over.
/datum/component/hardlight_coverage/proc/claim_avatar(mob/living/avatar)
	avatar_ref = isnull(avatar) ? null : WEAKREF(avatar)

/// Gives up whatever we were holding. Does not delete it; the projector decides what happens to the body.
/datum/component/hardlight_coverage/proc/release_avatar()
	avatar_ref = null

/// Every registered coverage whose projector sits on `z_level`.
/proc/hardlight_coverage_on_z(z_level)
	var/list/found = list()
	for(var/datum/component/hardlight_coverage/coverage as anything in GLOB.hardlight_coverages)
		var/turf/pad_turf = get_turf(coverage.parent)
		if(isnull(pad_turf) || pad_turf.z != z_level)
			continue
		found += coverage
	return found
