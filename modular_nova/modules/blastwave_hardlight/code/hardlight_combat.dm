// MODULE ID: BLASTWAVE_HARDLIGHT
// What the projected body does once it is standing up. Room selection is the command core's job.

/**
 * Avatar targeting
 *
 * Refuses anything its projector cannot reach. Without this the unit happily locks onto someone
 * through a doorway, walks into its own confinement block and stands there twitching.
 */
/datum/targeting_strategy/basic/hardlight

/datum/targeting_strategy/basic/hardlight/can_attack(mob/living/living_mob, atom/the_target, vision_range)
	. = ..()
	if(!.)
		return FALSE

	var/mob/living/basic/hardlight_avatar/avatar = living_mob
	if(!istype(avatar) || isnull(avatar.pad?.coverage))
		return TRUE

	return avatar.pad.coverage.covers_turf(get_turf(the_target))

/**
 * Whatever the command core says matters most
 *
 * Runs ahead of target-finding and writes straight into the current-target slot, so the attack
 * subtrees downstream treat a drilling emitter exactly like they would treat a person.
 */
/datum/ai_planning_subtree/hardlight_priority_target

/datum/ai_planning_subtree/hardlight_priority_target/SelectBehaviors(datum/ai_controller/controller, seconds_per_tick)
	var/atom/threat = controller.blackboard[BB_HARDLIGHT_PRIORITY_TARGET]
	if(QDELETED(threat))
		return

	var/mob/living/basic/hardlight_avatar/avatar = controller.pawn
	if(!istype(avatar) || !avatar.pad?.coverage?.covers_turf(get_turf(threat)))
		return

	controller.set_blackboard_key(BB_BASIC_MOB_CURRENT_TARGET, threat)

/// Target-finding, suppressed while a priority threat is in reach so it cannot be distracted off it.
/datum/ai_planning_subtree/simple_find_target/hardlight

/datum/ai_planning_subtree/simple_find_target/hardlight/SelectBehaviors(datum/ai_controller/controller, seconds_per_tick)
	var/atom/threat = controller.blackboard[BB_HARDLIGHT_PRIORITY_TARGET]
	if(!QDELETED(threat))
		var/mob/living/basic/hardlight_avatar/avatar = controller.pawn
		if(istype(avatar) && avatar.pad?.coverage?.covers_turf(get_turf(threat)))
			return

	controller.queue_behavior(/datum/ai_behavior/find_potential_targets/hardlight, target_key, strategy_key, BB_BASIC_MOB_CURRENT_TARGET_HIDING_LOCATION)

/**
 * Goes for whoever is standing closest to the plate, not whoever is closest to the body.
 *
 * The plate is the thing worth defending and the thing that can tether, so crowding it should be
 * the mistake that gets punished. It also means shoving the avatar across the room buys nothing:
 * it will still turn round and walk back to the person leaning on its projector.
 */
/datum/ai_behavior/find_potential_targets/hardlight

/datum/ai_behavior/find_potential_targets/hardlight/pick_final_target(datum/ai_controller/controller, list/filtered_targets)
	var/mob/living/basic/hardlight_avatar/avatar = controller.pawn
	if(!istype(avatar) || isnull(avatar.pad))
		return ..()

	var/turf/plate_turf = get_turf(avatar.pad)
	if(isnull(plate_turf))
		return ..()

	return get_closest_atom(/atom/, filtered_targets, plate_turf)

/**
 * Clamp whoever is loitering on the plate.
 *
 * Gated the way the goliath gates its tentacles: only on a target that is actually within reach of
 * the plate, and never on someone already held.
 */
/datum/ai_planning_subtree/targeted_mob_ability/hardlight_tether
	ability_key = BB_HARDLIGHT_TETHER

/datum/ai_planning_subtree/targeted_mob_ability/hardlight_tether/additional_ability_checks(datum/ai_controller/controller, datum/action/cooldown/using_action)
	var/mob/living/carbon/target = controller.blackboard[target_key]
	if(!iscarbon(target) || target.stat == DEAD || target.legcuffed)
		return FALSE

	var/mob/living/basic/hardlight_avatar/avatar = controller.pawn
	if(!istype(avatar) || !avatar.pad?.can_project())
		return FALSE

	return get_dist(target, avatar.pad) <= HARDLIGHT_TETHER_RANGE

/datum/ai_planning_subtree/targeted_mob_ability/hardlight_lance
	ability_key = BB_TARGETED_ACTION
	finish_planning = FALSE

/datum/ai_planning_subtree/targeted_mob_ability/hardlight_lance/additional_ability_checks(datum/ai_controller/controller, datum/action/cooldown/using_action)
	// Throwing someone we have just pinned to the floor accomplishes nothing and reads as a bug.
	// A tethered target gets beaten on in melee instead, which is the point of pinning them.
	var/mob/living/carbon/target = controller.blackboard[target_key]
	return !iscarbon(target) || !istype(target.legcuffed, /obj/item/restraints/legcuffs/hardlight_tether)

/**
 * Snap back to the plate rather than be walked off it.
 *
 * Fires when the body has been drawn away from its projector and whatever drew it away is not the
 * most useful thing to be hitting. Without this the counterplay to the whole encounter is "one
 * person jogs in circles at the far wall while everyone else works on the objective ten tiles
 * away", because the body will dutifully chase them and the room is effectively cleared. With it,
 * being led away is a thing the unit notices and undoes, and the person leaning on the plate is
 * the one who pays for it.
 */
/datum/ai_planning_subtree/use_mob_ability/hardlight_recall
	ability_key = BB_HARDLIGHT_RECALL
	finish_planning = TRUE

/datum/ai_planning_subtree/use_mob_ability/hardlight_recall/SelectBehaviors(datum/ai_controller/controller, seconds_per_tick)
	var/mob/living/basic/hardlight_avatar/avatar = controller.pawn
	if(!istype(avatar) || !avatar.pad?.can_project())
		return

	if(get_dist(avatar, avatar.pad) < HARDLIGHT_RECALL_DISTANCE)
		return

	// Whoever we are chasing is standing on the objective, so chasing them is the correct thing to
	// be doing and going home would just hand them the room.
	var/atom/current_target = controller.blackboard[BB_BASIC_MOB_CURRENT_TARGET]
	if(!isnull(current_target) && get_dist(current_target, avatar.pad) < HARDLIGHT_RECALL_DISTANCE)
		return

	return ..()

/datum/ai_controller/basic_controller/hardlight_avatar
	blackboard = list(
		BB_TARGETING_STRATEGY = /datum/targeting_strategy/basic/hardlight,
	)
	ai_movement = /datum/ai_movement/basic_avoidance
	idle_behavior = /datum/idle_behavior/idle_random_walk
	planning_subtrees = list(
		/datum/ai_planning_subtree/hardlight_priority_target,
		/datum/ai_planning_subtree/simple_find_target/hardlight,
		// Before anything else: are we even in the right part of the room to be fighting from?
		/datum/ai_planning_subtree/use_mob_ability/hardlight_recall,
		// Tether next: pinning someone to the plate is worth more than any amount of hitting them.
		/datum/ai_planning_subtree/targeted_mob_ability/hardlight_tether,
		/datum/ai_planning_subtree/targeted_mob_ability/hardlight_lance,
		/datum/ai_planning_subtree/basic_melee_attack_subtree,
	)

/**
 * Reprojection
 *
 * The body is not walking anywhere; it is being drawn, and the projector can stop drawing it here
 * and start drawing it there. Presented as a phase-out rather than a teleport because that is what
 * it is, and because the half second of smeared light is the tell that lets a crew who have seen it
 * once predict it the next time.
 *
 * Deliberately free. Charging the pad for it would make "kite it into a corner" a drain strategy,
 * and the pad is supposed to be drained by shooting it, not by jogging.
 */
/datum/action/cooldown/mob_cooldown/hardlight_recall
	name = "Reprojection"
	desc = "Collapse and re-form on the projector plate."
	button_icon = 'icons/mob/actions/actions_revenant.dmi'
	button_icon_state = "r_transmit"
	cooldown_time = 15 SECONDS
	melee_cooldown_time = 0

/datum/action/cooldown/mob_cooldown/hardlight_recall/Activate(atom/target)
	var/mob/living/basic/hardlight_avatar/avatar = owner
	if(!istype(avatar) || !avatar.pad?.can_project())
		return FALSE

	var/turf/plate_turf = get_turf(avatar.pad)
	if(isnull(plate_turf) || avatar.loc == plate_turf)
		return FALSE

	if(!avatar.reproject_to(plate_turf))
		return FALSE

	StartCooldown()
	return TRUE

/**
 * Plate tether
 *
 * Reaches out from the projector rather than from the body, so it works at plate range and not at
 * arm's length. The loop dies when the body leaves that plate, so a hop or a kite is a release
 * rather than a leftover cuff in an empty room.
 */
/datum/action/cooldown/mob_cooldown/hardlight_tether
	name = "Plate Tether"
	desc = "Clamp a target to the projector plate."
	button_icon = 'icons/mob/simple/lavaland/lavaland_monsters.dmi'
	button_icon_state = "goliath_tentacle_wiggle"
	cooldown_time = 20 SECONDS
	melee_cooldown_time = 0
	click_to_activate = TRUE

/datum/action/cooldown/mob_cooldown/hardlight_tether/Activate(atom/target)
	var/mob/living/basic/hardlight_avatar/avatar = owner
	if(!istype(avatar) || !avatar.pad?.can_project())
		return FALSE
	if(!iscarbon(target) || get_dist(target, avatar.pad) > HARDLIGHT_TETHER_RANGE)
		return FALSE

	var/mob/living/carbon/victim = target
	if(victim.legcuffed)
		return FALSE

	new /obj/item/restraints/legcuffs/hardlight_tether(get_turf(victim), victim, avatar.pad, avatar)
	StartCooldown()
	return TRUE

/**
 * Displacement lance
 *
 * The ranged half of the fight. Against people it throws and breaks bones, which is unpleasant but
 * survivable; against hardware it rips the moorings out, which is the part that actually threatens
 * an objective. Same ability either way, so the unit choosing to shoot the drill instead of the
 * person standing over it reads as a decision rather than a special case.
 *
 * Two stages, and both exist to stop it being a tax. It used to land the instant the unit decided
 * to throw it - a hitscan beam with the effect applied directly - which meant the only counterplay
 * to a nine second cooldown was to already be somewhere else. Now it telegraphs for a second and a
 * half and then throws something that has to cross the intervening tiles, so the fight has an
 * answer in it that is not "have more health".
 */
/datum/action/cooldown/mob_cooldown/hardlight_lance
	name = "Displacement Lance"
	desc = "Throw a target away along a lance of hard light."
	button_icon = 'icons/mob/actions/actions_items.dmi'
	button_icon_state = "sniper_zoom"
	cooldown_time = 9 SECONDS
	melee_cooldown_time = 0
	click_to_activate = TRUE
	/// Furthest we will reach.
	var/lance_range = 7
	/// Windup before the bolt leaves. This is the dodge window, and the tell that there is one.
	var/charge_time = 1.5 SECONDS
	/// What the windup throws.
	var/projectile_type = /obj/projectile/energy/hardlight_lance

/datum/action/cooldown/mob_cooldown/hardlight_lance/IsAvailable(feedback = FALSE)
	. = ..()
	if(!.)
		return FALSE
	return !isnull(owner)

/**
 * Winds up. The bolt itself leaves in release().
 *
 * The cooldown starts here rather than on release, so the windup is paid out of the gap between
 * shots instead of being added on top of it - the attack is meant to become avoidable, not rarer.
 */
/datum/action/cooldown/mob_cooldown/hardlight_lance/Activate(atom/target)
	if(QDELETED(target) || get_dist(owner, target) > lance_range)
		return FALSE

	owner.visible_message(span_danger("[owner] levels an arm at [target], and light begins to pool along it."))
	playsound(owner, 'sound/effects/seedling_chargeup.ogg', 65, TRUE)
	owner.add_filter("hardlight_lance_charge", 2, list("type" = "outline", "color" = HARDLIGHT_COLOUR, "size" = 2))

	// Weak, and re-checked on the way out: a target can die, be gibbed, or walk through a door in
	// the second and a half this takes, and all three of those should waste the shot.
	addtimer(CALLBACK(src, PROC_REF(release), WEAKREF(target)), charge_time)
	StartCooldown()
	return TRUE

/**
 * Second half of the lance. Throws the bolt at wherever the target is *now*.
 *
 * Aimed live rather than at the tile the windup started on, because a bolt that lands on where
 * somebody used to be standing is not a boss attack, it is a free hit for walking in a straight
 * line. What makes it dodgeable is that the bolt then has to travel, and that the windup told you
 * to stop being in front of it.
 */
/datum/action/cooldown/mob_cooldown/hardlight_lance/proc/release(datum/weakref/target_ref)
	if(QDELETED(owner))
		return

	owner.remove_filter("hardlight_lance_charge")

	// Blinked out mid-windup. There is no arm anywhere to throw anything with.
	var/mob/living/basic/hardlight_avatar/avatar = owner
	if(istype(avatar) && avatar.reprojecting)
		return

	var/atom/target = target_ref?.resolve()
	if(QDELETED(target) || get_dist(owner, target) > lance_range)
		return

	owner.visible_message(span_danger("[owner] throws its arm forward and the pooled light leaves it!"))
	owner.fire_projectile(projectile_type, target, 'sound/items/weapons/laser.ogg', owner)

/**
 * Displacement bolt
 *
 * Slow on purpose. Everything else about this fight is unavoidable by design - the body cannot be
 * killed, the tether cannot be outrun, the plate has to be drained - so the one attack that can be
 * stepped out of is carrying the whole weight of "there is something you can do here".
 *
 * Damage rides the normal projectile pipeline so armour counts for something. The throw and the
 * fracture are applied on top in on_hit(), because those are the parts that cost the crew a minute
 * of triage rather than a health bar.
 */
/obj/projectile/energy/hardlight_lance
	name = "displacement lance"
	// "spark" is inherited and definitely exists; the colour is doing the identification.
	color = HARDLIGHT_COLOUR
	damage = 12
	damage_type = BRUTE
	armor_flag = ENERGY
	speed = 2.5
	range = 9
	light_color = HARDLIGHT_LIGHT_COLOUR
	light_range = 2
	hitsound = 'sound/items/weapons/sonic_jackhammer.ogg'
	/// Tiles a living target is thrown on impact.
	var/throw_distance = 4

/obj/projectile/energy/hardlight_lance/on_hit(atom/target, blocked = 0, pierce_hit)
	. = ..()
	// Fully blocked is fully blocked. Being thrown across a room through a riot shield would make
	// the shield worse than useless, which is the opposite of the point of slowing this down.
	if(blocked >= 100)
		return .

	if(isliving(target))
		displace(target)
	else
		hardlight_unmoor(target, firer)

	return .

/// Hurls a living target along our line of travel and cracks something on the way out.
/obj/projectile/energy/hardlight_lance/proc/displace(mob/living/victim)
	var/direction = isnull(firer) ? dir : get_dir(firer, victim)
	victim.safe_throw_at(get_edge_target_turf(victim, direction), throw_distance, 3, firer)

	if(!iscarbon(victim))
		return

	// A blunt fracture is the point: it is a wound a field medic can splint, so a lance hit costs the
	// crew a minute of triage rather than a body. Anything lethal here would make the room unholdable.
	var/mob/living/carbon/carbon_victim = victim
	var/obj/item/bodypart/struck = pick(carbon_victim.get_bodyparts())
	if(isnull(struck))
		return

	var/datum/wound/blunt/bone/moderate/fracture = new()
	fracture.apply_wound(struck, wound_source = "hard-light displacement", attack_direction = direction)

/**
 * Rips a machine off its mounts without breaking it.
 *
 * Emitters and portable generators both stop working the moment they stop being anchored, and both
 * go straight back to work once re-secured. That asymmetry is the whole design of the drill fight:
 * the unit can cost the crew a minute, but it cannot cost them the run. Losing the only emitter on
 * the station to a stray crit would.
 *
 * Returns TRUE if we took something offline.
 */
/proc/hardlight_unmoor(atom/target, mob/living/ripper)
	var/obj/machinery/machine = target
	if(!istype(machine) || !machine.anchored)
		return FALSE

	if(!istype(machine, /obj/machinery/power/emitter) && !istype(machine, /obj/machinery/power/port_gen))
		return FALSE

	// Emitters clear their own welded flag on losing anchor, which is what actually stops them firing.
	machine.set_anchored(FALSE)
	machine.visible_message(span_boldwarning("[ripper] tears [machine] off its mounts!"))
	playsound(machine, 'sound/items/weapons/smash.ogg', 70, TRUE)
	step(machine, get_dir(ripper, machine))
	do_sparks(3, FALSE, machine)
	return TRUE

/**
 * Tether
 *
 * The goliath beat, rebuilt out of light: the victim is pinned where they stand, on a visible line
 * back to the plate that did it. They can still shoot. The loop lasts only while the body is still
 * standing on that plate - drain it, hop it to another room, or walk it off, and the cuff comes
 * apart. A pin that outlives the projection is a leftover, not a hold.
 */
/obj/item/restraints/legcuffs/hardlight_tether
	name = "hard-light tether"
	desc = "A rigid loop of standing light closed around your leg. The other end goes into the floor plate."
	color = HARDLIGHT_COLOUR
	breakouttime = HARDLIGHT_TETHER_BREAKOUT
	item_flags = DROPDEL
	obj_flags = CONDUCTS_ELECTRICITY | CAN_BE_HIT
	uses_integrity = TRUE
	max_integrity = 60
	/// The plate we are anchored to.
	var/obj/machinery/hardlight_projector/anchor
	/// The body that threw this. The loop is its reach, not the plate's leftover.
	var/mob/living/basic/hardlight_avatar/caster
	/// Backstop for anything that moves the victim without walking them, such as a throw.
	var/datum/component/leash/leash
	/// Visible line back to the plate.
	var/datum/beam/beam_effect

/obj/item/restraints/legcuffs/hardlight_tether/Initialize(mapload, mob/living/carbon/target, obj/machinery/hardlight_projector/anchor, mob/living/basic/hardlight_avatar/caster)
	. = ..()
	src.anchor = anchor
	src.caster = caster
	if(isnull(anchor) || isnull(caster) || !iscarbon(target))
		return INITIALIZE_HINT_QDEL
	if(!target.equip_to_slot_if_possible(src, ITEM_SLOT_LEGCUFFED, disable_warning = TRUE, bypass_equip_delay_self = TRUE))
		return INITIALIZE_HINT_QDEL

/obj/item/restraints/legcuffs/hardlight_tether/Destroy(force)
	if(!isnull(caster))
		UnregisterSignal(caster, list(COMSIG_MOVABLE_MOVED, COMSIG_QDELETING, COMSIG_HARDLIGHT_AVATAR_PAD_CHANGED))
	caster = null
	. = ..()
	QDEL_NULL(leash)
	QDEL_NULL(beam_effect)
	anchor = null

/obj/item/restraints/legcuffs/hardlight_tether/equipped(mob/user, slot, initial)
	. = ..()
	if(slot != ITEM_SLOT_LEGCUFFED || !isnull(leash) || isnull(anchor))
		return

	// Rooted, not merely slowed. Resisting out, a dead pad, or the body leaving the plate are the
	// ways off this; the last is the one that used to fail to fire.
	ADD_TRAIT(user, TRAIT_IMMOBILIZED, REF(src))
	leash = user.AddComponent(/datum/component/leash, owner = anchor, distance = 1, silent = TRUE)
	beam_effect = user.Beam(anchor, icon_state = "b_beam", beam_color = HARDLIGHT_COLOUR)
	user.visible_message(
		span_danger("A band of light snaps out of [anchor] and closes around [user]'s leg!"),
		span_userdanger("The plate throws a loop of hard light around your leg. You cannot move."),
	)
	playsound(user, 'sound/effects/magic/repulse.ogg', 60, TRUE)

	RegisterSignal(anchor, COMSIG_HARDLIGHT_PAD_COLLAPSED, PROC_REF(on_anchor_lost))
	RegisterSignal(anchor, COMSIG_QDELETING, PROC_REF(on_anchor_lost))
	RegisterSignal(leash, COMSIG_QDELETING, PROC_REF(on_anchor_lost))
	RegisterSignal(caster, COMSIG_MOVABLE_MOVED, PROC_REF(on_caster_moved))
	RegisterSignal(caster, COMSIG_HARDLIGHT_AVATAR_PAD_CHANGED, PROC_REF(on_caster_pad_changed))
	RegisterSignal(caster, COMSIG_QDELETING, PROC_REF(on_anchor_lost))

/obj/item/restraints/legcuffs/hardlight_tether/dropped(mob/user, silent)
	if(!isnull(user))
		REMOVE_TRAIT(user, TRAIT_IMMOBILIZED, REF(src))
	return ..()

/obj/item/restraints/legcuffs/hardlight_tether/proc/on_anchor_lost(datum/source)
	SIGNAL_HANDLER
	qdel(src)

/// Drops the moment the body is no longer close enough to the plate to have thrown this.
/obj/item/restraints/legcuffs/hardlight_tether/proc/on_caster_moved(atom/movable/source)
	SIGNAL_HANDLER

	if(QDELETED(caster) || get_dist(caster, anchor) > HARDLIGHT_TETHER_RANGE)
		qdel(src)

/// A hop to another plate is a leave even if the two plates sit inside the same reach.
/obj/item/restraints/legcuffs/hardlight_tether/proc/on_caster_pad_changed(datum/source, obj/machinery/hardlight_projector/new_pad)
	SIGNAL_HANDLER

	if(new_pad != anchor)
		qdel(src)

// Avatar behaviour. Split from hardlight_avatar.dm so the mob file stays about damage plumbing and
// this one stays about what the thing does to you; both halves are still the same type.

/**
 * Melee against hardware unmoors it instead of hitting it.
 *
 * Doing this on our side rather than by adding ourselves to the emitter's megafauna branch keeps the
 * whole behaviour in this module, where someone reading the encounter can find it.
 */
/mob/living/basic/hardlight_avatar/proc/on_pre_attack(mob/living/source, atom/target, proximity, list/modifiers)
	SIGNAL_HANDLER

	if(!hardlight_unmoor(target, src))
		return
	return COMPONENT_HOSTILE_NO_ATTACK

/mob/living/basic/hardlight_avatar/Life(seconds_per_tick, times_fired)
	. = ..()
	if(QDELETED(src))
		return
	sync_destabilisation()

/**
 * Keeps our aggression in step with the bank behind us.
 *
 * Below the destabilisation line the pad also takes extra drain, so this is the moment the fight
 * becomes a race rather than a grind, in both directions at once.
 */
/mob/living/basic/hardlight_avatar/proc/sync_destabilisation()
	var/should_be = !isnull(pad) && pad.is_destabilised()
	if(should_be == destabilised)
		return

	destabilised = should_be
	melee_damage_lower = initial(melee_damage_lower) * (destabilised ? HARDLIGHT_ENRAGE_DAMAGE_MULT : 1)
	melee_damage_upper = initial(melee_damage_upper) * (destabilised ? HARDLIGHT_ENRAGE_DAMAGE_MULT : 1)
	melee_attack_cooldown = initial(melee_attack_cooldown) * (destabilised ? 0.6 : 1)
	add_atom_colour(destabilised ? HARDLIGHT_COLOUR_DESTABILISED : hologram_colour, FIXED_COLOUR_PRIORITY)

	if(destabilised)
		visible_message(span_boldwarning("[src] flickers hard and the edges of it start to come apart."))
