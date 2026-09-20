// MODULE ID: BLASTWAVE_HARDLIGHT
// The wall in front of the core, and the only thing that gets through it.

/**
 * Hard-light containment field
 *
 * Indestructible to everything the crew can carry, and deliberately so: the only thing that
 * touches it is sustained fire from an /obj/machinery/power/emitter, which means the objective is
 * not "bring a weapon" but "haul an industrial laser across a station, power it, and then hold the
 * room around it for two minutes". That is a fight with a shape, rather than a damage race.
 *
 * Progress decays rather than resets when the drill goes quiet, so losing a round of defence costs
 * the crew ground without throwing away the attempt. While the drill is live the field nominates
 * whoever is firing it as the command core's priority threat, which is what sends the unit after
 * the emitter instead of after the people standing over it - and since the unit unmoors hardware
 * rather than destroying it, the crew's recovery is a re-wrench rather than a dead run.
 *
 * Dormant until raised. Wiring is by queuelink: whatever disables the core's security fires
 * COMSIG_PUZZLE_COMPLETED, and this comes up in response. The trap is that opening the door is
 * what puts the wall there.
 */
/obj/machinery/hardlight_containment
	name = "containment field"
	desc = "A standing plane of hard light, mounted floor to ceiling. It does not flicker, and it \
		does not appear to be held up by anything in this room."
	icon = 'icons/obj/machines/engine/singularity.dmi'
	icon_state = "Contain_F"
	density = FALSE
	anchored = TRUE
	move_resist = INFINITY
	resistance_flags = INDESTRUCTIBLE | LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	use_power = NO_POWER_USE
	processing_flags = START_PROCESSING_ON_INIT
	interaction_flags_atom = NONE
	interaction_flags_machine = NONE
	explosion_block = INFINITY
	layer = ABOVE_OBJ_LAYER
	light_color = HARDLIGHT_LIGHT_COLOUR
	/// Queuelink id. Whatever shares it and completes raises us. Null means "up from mapload".
	var/puzzle_id
	/// Whether we are actually in the way of anything.
	var/raised = FALSE
	/// Accumulated drill progress, against HARDLIGHT_DRILL_REQUIRED.
	var/drill_progress = 0
	/// Set once we have been breached. A breach is permanent; this is a one-way objective.
	var/breached = FALSE
	/// The thing currently drilling us, held so we can stop nominating it once it stops.
	var/datum/weakref/driller_ref
	/// Refreshed by every bolt. While unexpired we count as under active fire.
	COOLDOWN_DECLARE(drill_window)

/obj/machinery/hardlight_containment/Initialize(mapload)
	// Before the parent call, not after: explosion_block is inert without this element, and
	// /atom/movable/Initialize asserts the pairing on the way past. Same ordering the
	// singularity's own containment uses.
	AddElement(/datum/element/blocks_explosives)
	. = ..()
	if(isnull(puzzle_id))
		raise()
	else
		SSqueuelinks.add_to_queue(src, puzzle_id)
	update_appearance()

/obj/machinery/hardlight_containment/Destroy()
	clear_driver()
	return ..()

/obj/machinery/hardlight_containment/MatchedLinks(id, list/partners)
	for(var/partner in partners)
		RegisterSignal(partner, COMSIG_PUZZLE_COMPLETED, PROC_REF(on_puzzle_completed))

/obj/machinery/hardlight_containment/proc/on_puzzle_completed(datum/source)
	SIGNAL_HANDLER
	raise()

/obj/machinery/hardlight_containment/examine(mob/user)
	. = ..()
	if(!raised)
		return

	. += span_warning("Nothing you are carrying is going to do anything to this.")
	if(drill_progress > 0)
		. += span_notice("A cone of it has gone milky and soft, roughly <b>[round((drill_progress / HARDLIGHT_DRILL_REQUIRED) * 100)]%</b> of the way through.")

/// Puts the wall up. Idempotent, and refused once the field has been breached for good.
/obj/machinery/hardlight_containment/proc/raise()
	if(raised || breached)
		return

	raised = TRUE
	set_density(TRUE)
	air_update_turf(TRUE, TRUE)
	visible_message(span_boldwarning("[src] snaps into existence, floor to ceiling."))
	playsound(src, 'sound/effects/empulse.ogg', 70, TRUE)
	update_appearance()

/**
 * Emitter fire, and nothing else.
 *
 * Everything that is not an emitter bolt sparks and is discarded without comment, which is the
 * whole lesson: the answer to this wall is not in anyone's holster.
 */
/obj/machinery/hardlight_containment/bullet_act(obj/projectile/hitting_projectile, def_zone, piercing_hit = FALSE)
	if(!raised)
		return ..()

	if(!istype(hitting_projectile, /obj/projectile/beam/emitter))
		do_sparks(1, FALSE, src)
		return BULLET_ACT_BLOCK

	register_drill_hit(hitting_projectile.firer)
	return BULLET_ACT_BLOCK

/**
 * Books one bolt's worth of progress and nominates the emitter as what the unit should go for.
 *
 * The bolt type is checked at the wall, but an emitter bolt is necessary rather than sufficient:
 * what the phase asks for is a real emitter stood up and pointed at the ring. A bolt that arrived
 * any other way has no machine behind it to defend, nothing for the unit to be sent at, and no
 * objective to have completed - so it sparks off like everything else that is not the answer.
 */
/obj/machinery/hardlight_containment/proc/register_drill_hit(obj/machinery/power/emitter/driller)
	if(!istype(driller))
		do_sparks(1, FALSE, src)
		return

	COOLDOWN_START(src, drill_window, HARDLIGHT_DRILL_IDLE_WINDOW)
	do_sparks(3, FALSE, src)
	playsound(src, 'sound/items/weapons/emitter2.ogg', 50, TRUE)

	if(driller_ref?.resolve() != driller)
		set_driver(driller)

	drill_progress = min(drill_progress + HARDLIGHT_DRILL_PER_BOLT, HARDLIGHT_DRILL_REQUIRED)
	if(drill_progress >= HARDLIGHT_DRILL_REQUIRED)
		breach()

/obj/machinery/hardlight_containment/process(seconds_per_tick)
	if(breached || !raised)
		return

	if(!COOLDOWN_FINISHED(src, drill_window))
		return

	// The drill has gone quiet. Stop pointing the unit at it, and let the hole start closing.
	clear_driver()

	if(drill_progress <= 0)
		return

	drill_progress = max(drill_progress - (HARDLIGHT_DRILL_DECAY * seconds_per_tick), 0)

/// Tells the core that `driller` outranks every room on its preference list.
/obj/machinery/hardlight_containment/proc/set_driver(atom/driller)
	driller_ref = WEAKREF(driller)

	var/obj/machinery/hardlight_command_core/core = our_core()
	if(isnull(core))
		return

	// Standing an emitter up against the ring is the third of the phase-two objectives, and the
	// only one the unit gets to watch happen rather than infer after the fact.
	core.note_objective(HARDLIGHT_OBJECTIVE_EMITTER)
	core.set_priority_threat(driller)

/// Stands the nomination down, but only if it is still ours to stand down.
/obj/machinery/hardlight_containment/proc/clear_driver()
	var/atom/driller = driller_ref?.resolve()
	driller_ref = null
	if(isnull(driller))
		return

	var/obj/machinery/hardlight_command_core/core = our_core()
	// Something else may have claimed the slot since. Do not clobber a newer nomination.
	if(isnull(core) || core.get_priority_threat() != driller)
		return
	core.set_priority_threat(null)

/obj/machinery/hardlight_containment/proc/our_core()
	var/turf/our_turf = get_turf(src)
	return isnull(our_turf) ? null : hardlight_core_on_z(our_turf.z)

/// The field comes down for good, and the core is reachable.
/obj/machinery/hardlight_containment/proc/breach()
	if(breached)
		return

	breached = TRUE
	raised = FALSE
	clear_driver()
	set_density(FALSE)
	air_update_turf(TRUE, TRUE)
	visible_message(span_boldwarning("[src] tears open along the drill line and collapses inward."))
	playsound(src, 'sound/effects/magic/blink.ogg', 80, TRUE)
	do_sparks(5, FALSE, src)
	update_appearance()

	our_core()?.set_phase(HARDLIGHT_PHASE_BREACHED)

/obj/machinery/hardlight_containment/update_appearance(updates)
	. = ..()
	// Dormant and breached look the same, which is correct: both mean the doorway is a doorway.
	invisibility = raised ? INVISIBILITY_NONE : INVISIBILITY_ABSTRACT
	set_light(raised ? 4 : 0)
