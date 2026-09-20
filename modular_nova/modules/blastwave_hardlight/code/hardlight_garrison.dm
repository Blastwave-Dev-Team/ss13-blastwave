// MODULE ID: BLASTWAVE_HARDLIGHT
// What is still in the building, and when it stops being still.

/**
 * Dormancy rack
 *
 * A sealed rack with something in it that has not been told to stop. Holds a typepath rather than
 * a mob, so a station can be wallpapered with these at no roundstart cost: nothing exists until
 * the matrix comes out, and then everything does at once.
 *
 * Waking on the matrix signal rather than on anyone opening a pod is the point. The last objective
 * is also the trigger, so there is no version of the ending where a cautious crew clears the racks
 * first - the thing that lets them leave is the thing that fills the halls behind them.
 *
 * Not deconstructible and not trivially breakable, for the same reason. A crew that spends phase
 * two quietly wrenching every rack on the station has not outplayed the encounter, they have
 * deleted the last third of it.
 */
/obj/structure/fluff/cryostasis_pod/dormant
	name = "occupied dormancy pod"
	desc = "A standing rack, sealed, with a chassis in it. The status strip along the frame is lit \
		and has been lit for a very long time. The service plate lists a unit designation and a \
		deployment that never happened."
	// The base pod is multiplied down to a dead grey. This one is running.
	color = "#8FA6C4"
	deconstructible = FALSE
	max_integrity = 400
	/**
	 * Weighted pool of what might be in a rack. Typepaths, so nothing is alive until called.
	 *
	 * A garrison of identical units is a wall with a number on it. A mixed one is a room the crew
	 * has to read before crossing: infantry can be walked past, rifles cannot, and a cyborg chassis
	 * has to be dealt with. Rolled per rack at wake rather than mapped, so the composition differs
	 * round to round and a crew who cleared the site last week cannot walk it from memory.
	 *
	 * Weighted toward infantry because that is what the fiction says is stacked in here, with the
	 * heavier chassis rare enough to still register as a problem when one comes out. The laser
	 * cyborg is rarest of the four; it is by some distance the most expensive thing to meet in a
	 * corridor you are trying to leave by.
	 */
	var/list/garrison_pool = list(
		/mob/living/basic/trooper/blastwave_synth = 40,
		/mob/living/basic/trooper/blastwave_synth/ranged = 25,
		/mob/living/basic/blastwave_cyborg = 20,
		/mob/living/basic/blastwave_cyborg/security = 15,
	)
	/// Sprite we swap to once we have let go of whatever was inside.
	var/open_icon_state = "cryopod-open"
	/// TRUE once we have spawned. A rack only ever opens once.
	var/woken = FALSE
	/// Longest stagger before we open. Twenty racks popping on one tick is a lag spike, not a scare.
	var/wake_delay_max = 8 SECONDS

/obj/structure/fluff/cryostasis_pod/dormant/Initialize(mapload)
	. = ..()
	RegisterSignal(SSdcs, COMSIG_GLOB_HARDLIGHT_MATRIX_EXTRACTED, PROC_REF(on_matrix_extracted))

/obj/structure/fluff/cryostasis_pod/dormant/examine(mob/user)
	. = ..()
	if(woken)
		. += span_notice("The rack is empty and the seal is hanging off it.")
		return
	. += span_warning("Whatever is in there is drawing power. The seal has never been broken.")

/obj/structure/fluff/cryostasis_pod/dormant/proc/on_matrix_extracted(datum/source, obj/machinery/hardlight_command_core/core, mob/living/extractor)
	SIGNAL_HANDLER

	if(woken)
		return

	var/turf/our_turf = get_turf(src)
	var/turf/core_turf = get_turf(core)
	// A second site on another Z must not empty its racks because this one was cracked.
	if(isnull(our_turf) || isnull(core_turf) || our_turf.z != core_turf.z)
		return

	// Claimed here rather than in wake(), so a second signal inside the stagger window is a no-op.
	woken = TRUE
	addtimer(CALLBACK(src, PROC_REF(wake)), rand(1 SECONDS, wake_delay_max))

/// Opens the rack and lets out whatever was in it.
/obj/structure/fluff/cryostasis_pod/dormant/proc/wake()
	if(QDELETED(src))
		return

	icon_state = open_icon_state
	update_appearance()
	visible_message(span_boldwarning("[src] cracks its seal and swings open."))
	playsound(src, 'sound/machines/airlock/airlockforced.ogg', 60, TRUE)
	do_sparks(2, FALSE, src)

	if(!length(garrison_pool))
		return

	var/mob/living/waking = pick_weight(garrison_pool)
	if(isnull(waking))
		return
	new waking(get_turf(src))

/**
 * Fixed racks
 *
 * Pools of one, for a mapper who wants a specific thing in a specific room rather than a share of
 * the mix. Kept as named subtypes rather than expecting the pool to be overridden inline, because
 * "this corridor is covered" should be a decision that survives someone later rebalancing the
 * weights above.
 */
/// Laser-armed chassis. The ones that make an open hallway expensive to cross.
/obj/structure/fluff/cryostasis_pod/dormant/security
	garrison_pool = list(/mob/living/basic/blastwave_cyborg/security = 1)

/// Heavier chassis, for rooms the crew has to come back through.
/obj/structure/fluff/cryostasis_pod/dormant/engineering
	garrison_pool = list(/mob/living/basic/blastwave_cyborg/engineering = 1)
