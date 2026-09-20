// MODULE ID: BLASTWAVE_HARDLIGHT
// The pad. Owns the charge pool that everything projected from it is fought through.

/**
 * Hard-light projector
 *
 * A floor pad that holds a solid body up out of nothing. The body cannot be hurt; the pad can, and
 * every hit the body absorbs is subtracted from the pad's capacitor bank instead. Empty the bank and
 * the projection drops, which is the only way to get a room to yourself.
 *
 * The pad itself cannot be destroyed, and that is deliberate rather than lazy. A pad you could
 * simply break would collapse the entire encounter into "bring a welder", and the recharge is what
 * makes an eviction temporary and therefore worth timing. The capacitor tier is the only thing that
 * differs between rooms: it sets how fast the pad comes back, so a tier four room has to be cleared
 * and used inside a window measured in seconds.
 */
/obj/machinery/hardlight_projector
	name = "hard-light projector"
	desc = "A recessed floor emitter ringed with capacitor banks. The lensing is scarred from the inside, \
		as though something has been repeatedly pushed through it harder than it was meant to go."
	icon = 'icons/obj/machines/floor.dmi'
	icon_state = "holopad0"
	base_icon_state = "holopad"
	layer = MAP_SWITCH(ABOVE_OPEN_TURF_LAYER, LOW_OBJ_LAYER)
	plane = MAP_SWITCH(FLOOR_PLANE, GAME_PLANE)
	density = FALSE
	// Pads outlive their rooms. Nothing the crew carries is supposed to be an answer to the pad itself.
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	// Ruin hardware on its own isolated bus. There is no APC behind these and no breaker to pull.
	use_power = NO_POWER_USE
	processing_flags = START_PROCESSING_ON_INIT
	circuit = /obj/item/circuitboard/machine/hardlight_projector
	light_power = 0.8
	light_color = HARDLIGHT_LIGHT_COLOUR
	/// Charge left in the bank. Draining this to zero is what drops the projection.
	var/stored_charge = HARDLIGHT_PAD_MAX_CHARGE
	/// Charge the bank holds when recovered.
	var/max_charge = HARDLIGHT_PAD_MAX_CHARGE
	/// Charge per second we recover. Set from the capacitor in RefreshParts().
	var/recharge_rate = HARDLIGHT_RECHARGE_TIER_ONE
	/// TRUE between losing the bank and recovering enough of it to project again.
	var/collapsed = FALSE
	/// Our coverage bookkeeping. Cached because the director asks about it constantly.
	var/datum/component/hardlight_coverage/coverage
	/// Collapses the pad-and-body double hit a single blast would otherwise land. See emp_drain().
	COOLDOWN_DECLARE(emp_window)

/obj/machinery/hardlight_projector/Initialize(mapload)
	. = ..()
	coverage = AddComponent(/datum/component/hardlight_coverage)
	update_appearance()

/obj/machinery/hardlight_projector/Destroy()
	// The component removes itself from the registry on its own; we only drop our cache of it.
	coverage = null
	return ..()

/obj/machinery/hardlight_projector/RefreshParts()
	. = ..()

	var/tier = 0
	for(var/datum/stock_part/capacitor/capacitor in component_parts)
		tier = max(tier, capacitor.tier)

	switch(tier)
		if(2)
			recharge_rate = HARDLIGHT_RECHARGE_TIER_TWO
		if(3)
			recharge_rate = HARDLIGHT_RECHARGE_TIER_THREE
		if(4 to INFINITY)
			recharge_rate = HARDLIGHT_RECHARGE_TIER_FOUR
		else
			// Tier one, and the no-capacitor case a malformed board would hand us.
			recharge_rate = HARDLIGHT_RECHARGE_TIER_ONE

/obj/machinery/hardlight_projector/examine(mob/user)
	. = ..()
	. += span_notice("The capacitor bank reads <b>[round(charge_fraction() * 100)]%</b>, recovering roughly [recharge_rate] units a second.")
	if(collapsed)
		. += span_warning("Its lensing is dark and cold. Whatever it was holding up is gone, for now.")
	else if(is_destabilised())
		. += span_warning("The bank is low enough that the lensing is visibly stuttering.")

/// How full the bank is, 0 to 1. The single number everything else is expressed against.
/obj/machinery/hardlight_projector/proc/charge_fraction()
	return max_charge <= 0 ? 0 : (stored_charge / max_charge)

/// Below the destabilisation line the projection hits harder and is hurt harder. See HARDLIGHT_ENRAGE_FRACTION.
/obj/machinery/hardlight_projector/proc/is_destabilised()
	return !collapsed && charge_fraction() < HARDLIGHT_ENRAGE_FRACTION

/// Whether we have the bank to hold a body up right now.
/obj/machinery/hardlight_projector/proc/can_project()
	return !QDELETED(src) && !collapsed && stored_charge > 0

/**
 * Takes `amount` out of the bank, collapsing us if that empties it.
 *
 * Returns how much we actually absorbed, so callers can tell a real hit from one that landed on an
 * already-dead pad. Destabilised pads take extra: a bank that has started losing keeps losing, which
 * is what turns a grinding fight into a moment where pushing is obviously correct.
 */
/obj/machinery/hardlight_projector/proc/drain(amount)
	if(amount <= 0 || collapsed)
		return 0

	if(is_destabilised())
		amount *= HARDLIGHT_ENRAGE_DRAIN_MULT

	var/absorbed = min(amount, stored_charge)
	stored_charge -= absorbed

	if(stored_charge <= 0)
		collapse()
	else
		update_appearance(UPDATE_ICON_STATE)

	return absorbed

/// Drops the bank and whatever it was holding. Recovery is handled by process().
/obj/machinery/hardlight_projector/proc/collapse()
	if(collapsed)
		return

	collapsed = TRUE
	stored_charge = 0
	do_sparks(3, FALSE, src)
	playsound(src, 'sound/machines/synth/synth_no.ogg', 60, TRUE)
	// Whoever is projecting through us is responsible for tearing the body down; we only say so.
	SEND_SIGNAL(src, COMSIG_HARDLIGHT_PAD_COLLAPSED)
	update_appearance()

/obj/machinery/hardlight_projector/process(seconds_per_tick)
	if(stored_charge >= max_charge)
		return

	stored_charge = min(stored_charge + (recharge_rate * seconds_per_tick), max_charge)

	if(collapsed && stored_charge >= (max_charge * HARDLIGHT_REACTIVATE_FRACTION))
		collapsed = FALSE
		playsound(src, 'sound/machines/synth/synth_yes.ogg', 50, TRUE)
		update_appearance()
		// No signal here on purpose. The director re-scores on its own clock, and a pad that comes
		// back in an empty room should not drag the unit across the station to stand in it.

/**
 * Ion bolts and EMPs land here rather than in the damage path.
 *
 * Cooldown-guarded because a single blast routinely reaches both the pad and the body standing on
 * it, and both forward here. One pulse should cost one bank, not two.
 */
/obj/machinery/hardlight_projector/proc/emp_drain(severity)
	if(!COOLDOWN_FINISHED(src, emp_window))
		return 0
	COOLDOWN_START(src, emp_window, HARDLIGHT_EMP_WINDOW)
	return drain(HARDLIGHT_EMP_DRAIN / max(severity, 1))

/**
 * We deliberately skip /obj/machinery's EMP behaviour.
 *
 * That would knock the pad temporarily inoperable, which is a second disruption mechanic sitting
 * alongside the charge pool doing the same job worse. One pool, one lever: an EMP is simply the
 * most charge anything can remove at once.
 */
/obj/machinery/hardlight_projector/emp_act(severity)
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	emp_drain(severity)

/obj/machinery/hardlight_projector/update_icon_state()
	icon_state = "[base_icon_state][can_project() ? 1 : 0]"
	return ..()

/obj/machinery/hardlight_projector/update_appearance(updates)
	. = ..()
	set_light(can_project() ? 2 : 0)

// Mapper-facing tiers. The pad reads its rate off the capacitor, so the tier lives on the board and
// these exist purely so a mapper can place "the fast one" without varediting component lists.

/obj/machinery/hardlight_projector/tier_two
	circuit = /obj/item/circuitboard/machine/hardlight_projector/tier_two
	recharge_rate = HARDLIGHT_RECHARGE_TIER_TWO

/obj/machinery/hardlight_projector/tier_three
	circuit = /obj/item/circuitboard/machine/hardlight_projector/tier_three
	recharge_rate = HARDLIGHT_RECHARGE_TIER_THREE

/obj/machinery/hardlight_projector/tier_four
	circuit = /obj/item/circuitboard/machine/hardlight_projector/tier_four
	recharge_rate = HARDLIGHT_RECHARGE_TIER_FOUR

/**
 * Hard-light projector board
 *
 * Not researchable and not in any techweb. It exists so the capacitor slot is a real part a curious
 * player can find behind the maintenance hatch, which is what makes the recovery curve in the
 * Federation's own documentation checkable rather than flavour text.
 */
/obj/item/circuitboard/machine/hardlight_projector
	name = "Hard-Light Projector"
	greyscale_colors = CIRCUIT_COLOR_SCIENCE
	build_path = /obj/machinery/hardlight_projector
	req_components = list(
		/datum/stock_part/capacitor = 1, // tier sets recovery rate, and nothing else
		/datum/stock_part/micro_laser = 2,
		/datum/stock_part/scanning_module = 1,
	)

/obj/item/circuitboard/machine/hardlight_projector/tier_two
	def_components = list(/datum/stock_part/capacitor = /datum/stock_part/capacitor/tier2)

/obj/item/circuitboard/machine/hardlight_projector/tier_three
	def_components = list(/datum/stock_part/capacitor = /datum/stock_part/capacitor/tier3)

/obj/item/circuitboard/machine/hardlight_projector/tier_four
	def_components = list(/datum/stock_part/capacitor = /datum/stock_part/capacitor/tier4)
