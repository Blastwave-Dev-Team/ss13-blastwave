// MODULE ID: BLASTWAVE_BLUESPACE
// The encounter's field source. Wears the gravity generator's sprite so crews read it as "the big scary one",
// but shares no code with /obj/machinery/gravity_generator: that one is INDESTRUCTIBLE, registers in
// GLOB.gravity_generators, and drives Z gravity, blackouts and nebula shielding. None of that is wanted here.

#define FIELD_POWER_IDLE 0
#define FIELD_POWER_UP 1
#define FIELD_POWER_DOWN 2

/// Abstract parent for the 3x3 block. Never map this directly; map the /main.
/obj/machinery/unstable_field_generator
	name = "bluespace resonance generator"
	desc = "A heavy graviton-frame generator, refitted for something it was never rated for. The housing hums at a pitch that makes your fillings ache."
	icon = 'icons/obj/machines/gravity_generator.dmi'
	density = TRUE
	move_resist = INFINITY
	use_power = NO_POWER_USE
	max_integrity = 800
	resistance_flags = LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF
	/// Which of the nine part sprites this piece wears.
	var/sprite_number = 0

/obj/machinery/unstable_field_generator/update_icon_state()
	icon_state = "[get_status()]_[sprite_number]"
	return ..()

/// "on", "off". Parts defer to the main unit so the whole block lights up together.
/obj/machinery/unstable_field_generator/proc/get_status()
	return "off"

/obj/machinery/unstable_field_generator/Move()
	. = ..()
	qdel(src)

/obj/machinery/unstable_field_generator/shuttleRotate(rotation, params)
	params = NONE
	return ..()

/// A dumb corner of the housing. Forwards everything to the main unit.
/obj/machinery/unstable_field_generator/part
	var/obj/machinery/unstable_field_generator/main/main_part

/obj/machinery/unstable_field_generator/part/Destroy()
	if(main_part)
		main_part.generator_parts -= src
		UnregisterSignal(main_part, COMSIG_ATOM_UPDATED_ICON)
		main_part = null
	return ..()

/obj/machinery/unstable_field_generator/part/get_status()
	return main_part?.get_status() || "off"

/obj/machinery/unstable_field_generator/part/attackby(obj/item/weapon, mob/user, list/modifiers, list/attack_modifiers)
	if(!main_part)
		return ..()
	return main_part.attackby(weapon, user, modifiers, attack_modifiers)

/obj/machinery/unstable_field_generator/part/attack_hand(mob/user, list/modifiers)
	if(!main_part)
		return ..()
	return main_part.attack_hand(user, modifiers)

/// Eats the extra update_appearance args so parts can ride the main unit's icon updates.
/obj/machinery/unstable_field_generator/part/proc/on_update_icon(obj/machinery/unstable_field_generator/source, updates, updated)
	SIGNAL_HANDLER
	return update_appearance(updates)

/**
 * The interactable core.
 *
 * Map this on the bottom-middle tile of the intended 3x3 footprint, same as the real gravity generator.
 * Starts running, holds the global unstable bluespace field, and only lets go once every required keycard
 * has been swiped and someone pulls the breaker.
 */
/obj/machinery/unstable_field_generator/main
	icon_state = "on_8"
	sprite_number = 8
	interaction_flags_machine = INTERACT_MACHINE_ALLOW_SILICON | INTERACT_MACHINE_OFFLINE

	/// The eight surrounding housing pieces.
	var/list/generator_parts = list()
	/// The middle piece, which carries the animated core overlay.
	var/obj/machinery/unstable_field_generator/part/center_part
	/// Whether we are currently holding the global field up.
	var/on = TRUE
	/// Whether the breaker is engaged. Goes false when someone with all the keys pulls it.
	var/breaker = TRUE
	/// FIELD_POWER_IDLE, FIELD_POWER_UP or FIELD_POWER_DOWN.
	var/charging_state = FIELD_POWER_IDLE
	/// 0 to 100. Ramps toward whichever end the breaker points at, and flips `on` when it gets there.
	var/charge_count = 100
	/// Tint applied to the whole housing so it reads as "not the gravity generator you know".
	var/field_color = "#7B4FD1"
	/// puzzle_id values that must all be slotted before the breaker will move. Mappers set this.
	var/list/required_puzzle_ids = list()
	/// Blast doors interlocked with the field. Mapper-set; each entry matches the `id` on the doors themselves.
	var/list/blast_door_ids
	/// Set once the field has collapsed. The breaker is a one-way trip: the authorizations that
	/// freed it are spent, and the whole point of the set piece is that shutting it down sticks.
	var/breaker_spent = FALSE
	/// Charge percent gained per process tick while climbing. Refilling a capacitor bank is the
	/// slow direction, so a change of heart before the field drops costs real time.
	var/charge_rate = 2
	/// Charge percent shed per process tick while collapsing. SSmachines ticks every 2 seconds,
	/// so 15 empties a full bank in about fifteen: fast enough to read as an event, slow enough
	/// that there is still time to be somewhere else when it lets go.
	var/discharge_rate = 15
	/// Keycards physically sitting in the reader, oldest first. These *are* the authorisation:
	/// pulling one back out re-locks its slot, so the state lives on the cards the machine is
	/// actually holding rather than in a parallel list that could drift out of step with them.
	var/list/obj/item/keycard/slotted_cards = list()
	/// Which core overlay is currently applied.
	var/current_overlay

/obj/machinery/unstable_field_generator/main/Initialize(mapload)
	. = ..()
	setup_parts()
	if(on)
		enable()
	update_core_overlay()
	register_context()

/obj/machinery/unstable_field_generator/main/Destroy()
	// A destroyed source counts as switched off. Nobody gets to keep the field up by exploding the machine.
	disable()
	// Spit the cards out rather than taking them with us. They are puzzle keys someone walked the
	// length of the site for, and they are INDESTRUCTIBLE precisely so they cannot be lost.
	var/turf/drop_turf = get_turf(src)
	for(var/obj/item/keycard/card as anything in slotted_cards)
		card.forceMove(drop_turf)
	slotted_cards = null
	QDEL_NULL(center_part)
	QDEL_LIST(generator_parts)
	return ..()

/obj/machinery/unstable_field_generator/main/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(istype(held_item, /obj/item/keycard))
		context[SCREENTIP_CONTEXT_LMB] = "Slot authorization card"
		return CONTEXTUAL_SCREENTIP_SET
	if(!isnull(held_item))
		return NONE

	if(length(slotted_cards))
		context[SCREENTIP_CONTEXT_LMB] = "Remove card"
	if(!breaker_spent && !length(missing_puzzle_ids()))
		context[SCREENTIP_CONTEXT_RMB] = breaker ? "Pull breaker" : "Engage breaker"
	return length(context) ? CONTEXTUAL_SCREENTIP_SET : NONE

/obj/machinery/unstable_field_generator/main/get_status()
	return (on || charging_state != FIELD_POWER_IDLE) ? "on" : "off"

/// Builds the eight surrounding housing pieces, 3x3 block anchored on our tile as the bottom middle.
/obj/machinery/unstable_field_generator/main/proc/setup_parts()
	var/turf/our_turf = get_turf(src)
	var/list/spawn_turfs = CORNER_BLOCK_OFFSET(our_turf, 3, 3, -1, 0)
	var/count = 10
	for(var/turf/spawn_turf in spawn_turfs)
		count--
		if(spawn_turf == our_turf)
			continue
		var/obj/machinery/unstable_field_generator/part/part = new(spawn_turf)
		if(count == 5)
			center_part = part
		if(count <= 3) // Top row is the overhanging part of the sprite, so it should not block movement.
			part.set_density(FALSE)
			part.layer = WALL_OBJ_LAYER
		part.sprite_number = count
		part.main_part = src
		part.add_atom_colour(field_color, FIXED_COLOUR_PRIORITY)
		generator_parts += part
		part.update_appearance()
		part.RegisterSignal(src, COMSIG_ATOM_UPDATED_ICON, TYPE_PROC_REF(/obj/machinery/unstable_field_generator/part, on_update_icon))

	add_atom_colour(field_color, FIXED_COLOUR_PRIORITY)

/obj/machinery/unstable_field_generator/main/examine(mob/user)
	. = ..()
	. += span_notice("The output gauge reads <b>[charge_count]%</b>, [charging_state == FIELD_POWER_DOWN ? "falling" : (charging_state == FIELD_POWER_UP ? "climbing" : "steady")].")

	if(length(slotted_cards))
		. += span_notice("[length(slotted_cards)] card\s [length(slotted_cards) == 1 ? "sits" : "sit"] in the reader.")

	if(breaker_spent)
		. += span_notice("The breaker has dropped out of its housing. Whatever it was holding closed is not going back.")
		return

	var/missing = missing_puzzle_ids()
	if(length(missing))
		. += span_warning("[length(missing)] of [length(required_puzzle_ids)] authorization slots are still empty. The breaker will not move.")
		return
	if(length(required_puzzle_ids))
		. += span_notice("Every authorisation slot is filled. The breaker is free.")
	. += span_notice("The breaker is <b>[breaker ? "engaged" : "pulled"]</b>. <b>Right-click</b> to throw it.")

/// puzzle_ids of every card currently in the reader.
/obj/machinery/unstable_field_generator/main/proc/accepted_puzzle_ids()
	var/list/ids = list()
	for(var/obj/item/keycard/card as anything in slotted_cards)
		ids += card.puzzle_id
	return ids

/// Which required puzzle_ids have no card in their slot yet.
/obj/machinery/unstable_field_generator/main/proc/missing_puzzle_ids()
	return required_puzzle_ids - accepted_puzzle_ids()

/obj/machinery/unstable_field_generator/main/attackby(obj/item/weapon, mob/user, list/modifiers, list/attack_modifiers)
	if(!istype(weapon, /obj/item/keycard))
		return ..()

	var/obj/item/keycard/key = weapon
	if(!(key.puzzle_id in required_puzzle_ids))
		balloon_alert(user, "card rejected")
		playsound(src, 'sound/machines/buzz/buzz-sigh.ogg', 45, TRUE)
		return TRUE
	if(key.puzzle_id in accepted_puzzle_ids())
		balloon_alert(user, "slot already filled")
		return TRUE
	if(!user.transferItemToLoc(key, src))
		balloon_alert(user, "card won't budge")
		return TRUE

	slotted_cards += key
	playsound(src, 'sound/machines/card_slide.ogg', 45, TRUE)
	var/remaining = length(missing_puzzle_ids())
	balloon_alert(user, remaining ? "[remaining] slot\s left" : "breaker unlocked")
	if(!remaining)
		playsound(src, 'sound/machines/beep/beep.ogg', 45, TRUE)
	return TRUE

/// Keeps the slot list honest if a card leaves by any route other than eject_card() — admin
/// yanking, the machine being taken apart, or anything else that empties our contents.
/obj/machinery/unstable_field_generator/main/Exited(atom/movable/gone, direction)
	. = ..()
	slotted_cards -= gone

/// Empty hand takes a card back out. The breaker is deliberately not on this input: throwing it
/// is irreversible, and the click that fills the last slot must not also be the one that fires it.
/obj/machinery/unstable_field_generator/main/interact(mob/user)
	. = ..()
	if(.)
		return
	return eject_card(user)

/// Pops the most recently slotted card back into the user's hands, re-locking its slot.
/obj/machinery/unstable_field_generator/main/proc/eject_card(mob/user)
	if(!length(slotted_cards))
		balloon_alert(user, "no cards slotted")
		return TRUE

	var/obj/item/keycard/card = slotted_cards[length(slotted_cards)]
	slotted_cards -= card
	card.forceMove(get_turf(src))
	user.put_in_hands(card)
	playsound(src, 'sound/machines/card_slide.ogg', 45, TRUE)
	balloon_alert(user, "card removed")
	return TRUE

/obj/machinery/unstable_field_generator/main/attack_hand_secondary(mob/user, list/modifiers)
	. = ..()
	if(. == SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN)
		return
	// interact() gets this for free from _try_interact; the secondary chain does not.
	if(!can_interact(user))
		return SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN
	pull_breaker(user)
	return SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN

/// Throws the breaker, if every slot is filled and it has not already been spent.
/obj/machinery/unstable_field_generator/main/proc/pull_breaker(mob/user)
	if(breaker_spent)
		balloon_alert(user, "breaker dead")
		playsound(src, 'sound/machines/buzz/buzz-sigh.ogg', 45, TRUE)
		return TRUE

	var/missing = length(missing_puzzle_ids())
	if(missing)
		balloon_alert(user, "[missing] slot\s left")
		playsound(src, 'sound/machines/buzz/buzz-sigh.ogg', 45, TRUE)
		return TRUE

	breaker = !breaker
	balloon_alert(user, breaker ? "breaker engaged" : "breaker pulled")
	playsound(src, 'sound/machines/click.ogg', 50, TRUE)
	set_power()
	return TRUE

/// Points the ramp at whichever end the breaker calls for.
/obj/machinery/unstable_field_generator/main/proc/set_power()
	charging_state = (breaker && !breaker_spent && !(machine_stat & BROKEN)) ? FIELD_POWER_UP : FIELD_POWER_DOWN
	update_appearance()

/obj/machinery/unstable_field_generator/main/atom_break(damage_flag)
	. = ..()
	breaker = FALSE
	set_power()

/obj/machinery/unstable_field_generator/main/proc/enable()
	charging_state = FIELD_POWER_IDLE
	on = TRUE
	add_unstable_bluespace_source(src)
	update_appearance()

/obj/machinery/unstable_field_generator/main/proc/disable()
	charging_state = FIELD_POWER_IDLE
	on = FALSE
	breaker = FALSE
	breaker_spent = TRUE
	remove_unstable_bluespace_source(src)
	release_blast_doors()
	update_appearance()

/obj/machinery/unstable_field_generator/main/proc/release_blast_doors()
	if(!length(blast_door_ids))
		return
	var/turf/our_turf = get_turf(src)
	if(isnull(our_turf))
		return
	for(var/obj/machinery/door/poddoor/door as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/door/poddoor))
		if(!(door.id in blast_door_ids) || door.z != our_turf.z)
			continue
		INVOKE_ASYNC(door, TYPE_PROC_REF(/obj/machinery/door, open))

/obj/machinery/unstable_field_generator/main/process()
	if(charging_state == FIELD_POWER_IDLE)
		return

	var/climbing = (charging_state == FIELD_POWER_UP)
	charge_count = clamp(charge_count + (climbing ? charge_rate : -discharge_rate), 0, 100)

	// Dumping is loud on every tick because it only lasts a handful of them. Climbing is spread
	// out so a long spin-up does not turn into a continuous racket.
	if(climbing ? (charge_count % 4 == 0 && prob(75)) : prob(75))
		playsound(src, 'sound/effects/empulse.ogg', 100, TRUE)
	update_core_overlay()

	// Checked after the step, so the bank finishes on the tick it actually reaches the rail
	// rather than idling through one more.
	if(climbing && charge_count >= 100)
		enable()
		return
	if(!climbing && charge_count <= 0)
		announce_collapse()
		disable()

/// Mirrors the gravity generator's charge animation so the machine reads as the same hardware.
/obj/machinery/unstable_field_generator/main/proc/update_core_overlay()
	var/overlay_state
	switch(charge_count)
		if(0 to 20)
			overlay_state = null
		if(21 to 40)
			overlay_state = "startup"
		if(41 to 60)
			overlay_state = "idle"
		if(61 to 80)
			overlay_state = "activating"
		if(81 to 100)
			overlay_state = "activated"

	if(overlay_state == current_overlay)
		return
	current_overlay = overlay_state
	if(isnull(center_part))
		return
	center_part.cut_overlays()
	if(overlay_state)
		center_part.add_overlay(overlay_state)

/// Lets everyone who has been suffering through the field know that it just dropped.
/obj/machinery/unstable_field_generator/main/proc/announce_collapse()
	if(!on)
		return
	visible_message(span_boldnotice("[src] winds down, and the air stops tasting like static."))
	playsound(src, 'sound/machines/synth/synth_yes.ogg', 100, TRUE)

#undef FIELD_POWER_IDLE
#undef FIELD_POWER_UP
#undef FIELD_POWER_DOWN
