// MODULE ID: BLASTWAVE_HARDLIGHT
// The body a projector holds up. Owns no health of its own; everything lands on the pad behind it.

/**
 * Hard-light avatar armour
 *
 * This is the whole weapon-selection lesson expressed as eight numbers.
 *
 * Kinetic impact couples badly into a capacitor bank, so bullets, fists and explosives are close to
 * worthless. Coherent light couples better but slowly. Ionising discharge is not resisted at all,
 * which is what makes the disabler and the ion gun the correct answer instead of the joke answers.
 */
/datum/armor/hardlight_avatar
	melee = 80
	bullet = 85
	laser = 55
	energy = 40
	bomb = 90
	bio = 100
	fire = 100
	acid = 100
	wound = 100

/**
 * Hard-light avatar
 *
 * A solid body projected by a nearby /obj/machinery/hardlight_projector. It is a real living mob
 * rather than a hologram effect so that it can be shoved, pulled, shot at and generally fought, but
 * it has no health worth the name: every point of damage it absorbs is subtracted from its pad's
 * capacitor bank instead, and the body simply stops existing when that bank runs out.
 *
 * Deliberately *not* flagged HOLOGRAM_1. That flag makes /atom/emp_act delete the atom outright,
 * which would let an ion bolt erase the body without touching the bank - and since the bank is what
 * gates the re-manifest, the unit would be standing back up a second later having lost nothing.
 * Routing EMP through the bank like everything else is the entire point of the fight. The
 * presentation that flag usually carries comes from holographic_nature and the traits below.
 */
/mob/living/basic/hardlight_avatar
	name = "hard-light projection"
	desc = "A body of standing light, dense enough to stop a door. It does not quite meet the floor."
	icon = 'icons/mob/simple/simple_human.dmi'
	gender = NEUTER
	mob_biotypes = MOB_ROBOTIC
	basic_mob_flags = DEL_ON_DEATH
	// Nothing ever moves this. It exists so death() and medical HUDs have a number to read.
	maxHealth = 1000
	health = 1000
	// Belt and braces behind the damage interception. If the signal ever fails to register we would
	// rather have an unkillable boss than one that a single shotgun slug deletes.
	damage_coeff = list(BRUTE = 0, BURN = 0, TOX = 0, STAMINA = 0, OXY = 0)
	armor_type = /datum/armor/hardlight_avatar
	melee_damage_lower = 6
	melee_damage_upper = 12
	melee_attack_cooldown = 2.5 SECONDS
	obj_damage = 30
	attack_verb_continuous = "lashes"
	attack_verb_simple = "lash"
	attack_sound = 'sound/items/weapons/egloves.ogg'
	speech_span = SPAN_ROBOT
	combat_mode = TRUE
	faction = list(FACTION_BLASTWAVE_DERELICT)
	alpha = 190
	// Warm, matching HARDLIGHT_COLOUR. These are the colours the body itself throws off, so a cool
	// cutoff under an orange silhouette would read as two different things overlaid.
	lighting_cutoff_red = 40
	lighting_cutoff_green = 25
	lighting_cutoff_blue = 10
	light_range = 2
	light_power = 0.6
	light_color = HARDLIGHT_LIGHT_COLOUR
	// It is light. Vacuum, cold and pressure are not opinions it has.
	habitable_atmos = null
	unsuitable_atmos_damage = 0
	unsuitable_cold_damage = 0
	unsuitable_heat_damage = 0
	minimum_survivable_temperature = 0
	maximum_survivable_temperature = INFINITY
	ai_controller = /datum/ai_controller/basic_controller/hardlight_avatar
	/// The projector holding us up. Hard reference, cleared through COMSIG_QDELETING below.
	var/obj/machinery/hardlight_projector/pad
	/// Species the projected body is built from. Subtypes dress the projection; nothing mechanical reads this.
	var/species_path = /datum/species/human
	/// Outfit the projected body appears to be wearing.
	var/outfit_path
	/// Tint laid over the composited body so it reads as standing light rather than a person.
	var/hologram_colour = HARDLIGHT_COLOUR
	/// TRUE while the pad behind us is below the destabilisation line. See sync_destabilisation().
	var/destabilised = FALSE
	/// TRUE for the half second we spend between two places. See reproject_to().
	var/reprojecting = FALSE
	/// The beam back to the plate holding us up. Decoration on a holopad; here it is the readout.
	var/obj/effect/overlay/holoray/ray

/mob/living/basic/hardlight_avatar/Initialize(mapload)
	. = ..()
	// Composites a humanoid out of the existing human icon stack, then tints the result. KEEP_TOGETHER
	// is set by the helper, which is what lets one alpha and one colour apply to the whole silhouette.
	apply_dynamic_human_appearance(src, outfit_path = outfit_path, species_path = species_path)
	add_atom_colour(hologram_colour, FIXED_COLOUR_PRIORITY)
	AddComponent(/datum/component/holographic_nature)
	add_traits(list(
		TRAIT_NOBLOOD,
		TRAIT_NO_BLOOD_OVERLAY,
		TRAIT_NOHUNGER,
		TRAIT_PERMANENTLY_MORTAL,
		TRAIT_SPAWNED_MOB,
	), INNATE_TRAIT)
	RegisterSignals(src, COMSIG_LIVING_ADJUST_ALL_DAMAGE_TYPES, PROC_REF(on_damage_adjusted))
	RegisterSignal(src, COMSIG_MOVABLE_PRE_MOVE, PROC_REF(on_pre_move))
	RegisterSignal(src, COMSIG_HOSTILE_PRE_ATTACKINGTARGET, PROC_REF(on_pre_attack))

	var/datum/action/cooldown/mob_cooldown/hardlight_lance/lance = new(src)
	lance.Grant(src)
	ai_controller?.set_blackboard_key(BB_TARGETED_ACTION, lance)

	var/datum/action/cooldown/mob_cooldown/hardlight_tether/tether = new(src)
	tether.Grant(src)
	ai_controller?.set_blackboard_key(BB_HARDLIGHT_TETHER, tether)

	var/datum/action/cooldown/mob_cooldown/hardlight_recall/recall = new(src)
	recall.Grant(src)
	ai_controller?.set_blackboard_key(BB_HARDLIGHT_RECALL, recall)

/mob/living/basic/hardlight_avatar/Destroy()
	set_pad(null)
	// Belt and braces: set_pad() short-circuits when the plate is already null, so a body that lost
	// its plate before dying would otherwise leave the beam standing in an empty room.
	QDEL_NULL(ray)
	return ..()

/mob/living/basic/hardlight_avatar/getarmor(def_zone, type)
	return get_armor_rating(type)

/// Binds us to `new_pad`, taking over its coverage claim. Passing null unbinds without derezzing.
/mob/living/basic/hardlight_avatar/proc/set_pad(obj/machinery/hardlight_projector/new_pad)
	if(pad == new_pad)
		return

	if(!isnull(pad))
		UnregisterSignal(pad, list(COMSIG_HARDLIGHT_PAD_COLLAPSED, COMSIG_QDELETING))
		if(pad.coverage?.get_avatar() == src)
			pad.coverage.release_avatar()

	pad = new_pad

	if(!isnull(pad))
		RegisterSignal(pad, COMSIG_HARDLIGHT_PAD_COLLAPSED, PROC_REF(on_pad_collapsed))
		RegisterSignal(pad, COMSIG_QDELETING, PROC_REF(on_pad_deleted))
		pad.coverage?.claim_avatar(src)

	SEND_SIGNAL(src, COMSIG_HARDLIGHT_AVATAR_PAD_CHANGED, pad)
	update_ray()

/**
 * Rebuilds the beam so it starts at whatever plate currently owns us.
 *
 * The ray lives on the plate's tile rather than ours, because that is the end that does not move.
 * Rebuilt rather than relocated on a handover: a plate change is meant to read as a snap to
 * somewhere else, and dragging the anchor across the room would read as the beam sweeping through
 * everything between the two.
 */
/mob/living/basic/hardlight_avatar/proc/update_ray()
	var/turf/anchor = isnull(pad) ? null : get_turf(pad)
	if(isnull(anchor))
		QDEL_NULL(ray)
		return

	if(isnull(ray))
		ray = new(anchor)
		ray.color = hologram_colour
	else if(ray.loc != anchor)
		ray.forceMove(anchor)

	ray.aim_at(src)

/**
 * Keeps the beam on us as we walk.
 *
 * Snaps rather than animating. A holopad tweens because its hologram shuffles a tile at a time
 * inside a small room; this thing crosses a hall, and a tweened beam lags far enough behind the
 * body to point at where it used to be, which is the one thing the beam exists not to do.
 */
/mob/living/basic/hardlight_avatar/Moved(atom/old_loc, movement_dir, forced, list/old_locs, momentum_change)
	. = ..()
	if(!isnull(ray) && !reprojecting)
		ray.aim_at(src)

/**
 * Every point of damage we would take, redirected into the pad.
 *
 * Fires from can_adjust_*_loss(), which means `amount` has already been through armour but not yet
 * through damage_coeff - so the armour datum above is doing the per-weapon-class work and this only
 * has to convert what survived into charge. Returning COMPONENT_IGNORE_CHANGE stops the adjustment
 * dead, so our own health never moves and nothing downstream sees a wounded mob.
 */
/mob/living/basic/hardlight_avatar/proc/on_damage_adjusted(mob/living/source, damage_type, amount, forced)
	SIGNAL_HANDLER

	// Healing is not a thing that happens to us, but it is also not a thing that should refill the bank.
	if(amount <= 0)
		return COMPONENT_IGNORE_CHANGE

	// Mid-transit the projector is not drawing a body anywhere, so there is nothing here to hit.
	if(reprojecting)
		return COMPONENT_IGNORE_CHANGE

	var/coefficient
	switch(damage_type)
		if(STAMINA)
			coefficient = HARDLIGHT_DRAIN_COEFF_STAMINA
		if(BURN)
			coefficient = HARDLIGHT_DRAIN_COEFF_BURN
		else
			coefficient = HARDLIGHT_DRAIN_COEFF_BRUTE

	pad?.drain(amount * coefficient)
	return COMPONENT_IGNORE_CHANGE

/**
 * Ion bolts and EMPs, which never enter the damage path at all.
 *
 * An ion bolt deals no damage; it detonates an empulse on impact. That pulse hits us and, if it is
 * wide enough, the pad as well - hence the cooldown on the pad side, so one bolt is one drain.
 */
/mob/living/basic/hardlight_avatar/emp_act(severity)
	. = ..()
	if(. & EMP_PROTECT_SELF)
		return
	visible_message(span_danger("[src] shears apart into bands of colour before pulling itself back together."))
	pad?.emp_drain(severity)

/// Confinement. A projector can only hold a body up over its own coverage, so we cannot be led out of the room.
/mob/living/basic/hardlight_avatar/proc/on_pre_move(atom/movable/source, atom/new_loc)
	SIGNAL_HANDLER

	if(isnull(pad?.coverage))
		return

	var/turf/destination = get_turf(new_loc)
	if(pad.coverage.covers_turf(destination))
		return

	return COMPONENT_MOVABLE_BLOCK_PRE_MOVE

/// Our pad lost its bank. Nothing is holding us up any more.
/mob/living/basic/hardlight_avatar/proc/on_pad_collapsed(obj/machinery/hardlight_projector/source)
	SIGNAL_HANDLER
	derez()

/mob/living/basic/hardlight_avatar/proc/on_pad_deleted(datum/source)
	SIGNAL_HANDLER
	set_pad(null)
	derez()

/// Fades out and goes away. The only way this body ever ends.
/mob/living/basic/hardlight_avatar/proc/derez()
	if(QDELETED(src))
		return

	visible_message(span_warning("[src] loses cohesion and scatters."))
	playsound(src, 'sound/effects/magic/blink.ogg', 50, TRUE)
	animate(src, alpha = 0, time = 0.6 SECONDS)
	if(!isnull(ray))
		animate(ray, alpha = 0, time = 0.6 SECONDS)
	QDEL_IN(src, 0.6 SECONDS)

/**
 * Phases out here and back in on `destination`.
 *
 * Not a teleport with a sound bolted on: for the length of the transit the body is genuinely not
 * there - not dense, not hittable, not blocking a doorway - because for that half second the
 * projector is not drawing it anywhere. That is also what lets it get out of a corner a crew has
 * boxed it into, which is the whole reason it has this.
 *
 * Returns FALSE if we are already mid-transit or have nowhere to land.
 */
/mob/living/basic/hardlight_avatar/proc/reproject_to(turf/destination)
	if(QDELETED(src) || reprojecting || isnull(destination))
		return FALSE

	reprojecting = TRUE
	visible_message(span_warning("[src] thins out and comes apart into a smear of light."))
	playsound(src, 'sound/effects/magic/blink.ogg', 50, TRUE)
	do_sparks(2, FALSE, src)

	set_density(FALSE)
	animate(src, alpha = 0, time = HARDLIGHT_RECALL_TRANSIT)
	// The beam goes with the body. Leaving it lit while there is nothing on the end of it would
	// point at the corner the crew just watched it leave.
	if(!isnull(ray))
		animate(ray, alpha = 0, time = HARDLIGHT_RECALL_TRANSIT)
	addtimer(CALLBACK(src, PROC_REF(finish_reprojection), destination), HARDLIGHT_RECALL_TRANSIT)
	return TRUE

/// Second half of reproject_to(). Puts the body back together somewhere else and re-picks a target.
/mob/living/basic/hardlight_avatar/proc/finish_reprojection(turf/destination)
	reprojecting = FALSE

	if(QDELETED(src))
		return

	set_density(initial(density))
	animate(src, alpha = initial(alpha), time = HARDLIGHT_RECALL_TRANSIT)

	// forceMove rather than Move: confinement is checked on the way in, and the plate is by
	// definition inside our own coverage, so there is nothing for that check to usefully say.
	// Re-tested all the same, because the core can relocate us to another room mid-transit and we
	// must not drag ourselves back to the plate we set off from.
	if(!QDELETED(destination) && pad?.coverage?.covers_turf(destination))
		forceMove(destination)
		visible_message(span_danger("[src] reassembles itself out of the plate."))
		do_sparks(2, FALSE, src)

	// After the move, so the beam is re-aimed at where the body ended up rather than where it went.
	if(!isnull(ray))
		animate(ray, alpha = initial(ray.alpha), time = HARDLIGHT_RECALL_TRANSIT)
		ray.aim_at(src)

	// The entire point of going home. Drop whoever led us away and look at who is actually here.
	ai_controller?.clear_blackboard_key(BB_BASIC_MOB_CURRENT_TARGET)
