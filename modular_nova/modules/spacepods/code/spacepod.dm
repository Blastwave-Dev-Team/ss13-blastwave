// MODULE ID: SPACEPODS
// Ported from Whitesands (whitesands/code/modules/spacepods/spacepod.dm).
//
// Spacepods are single-occupant local-Z vehicles for EVA, mining, and salvage.
// Differences from the Paradise originals they derive from:
// - no spacepod fabricator; parts come from techfabs and frames from metal rods.
// - velocity/acceleration physics instead of tile-based movement (see physics.dm).
// - high-speed impacts deal damage instead of simply stopping.
// - they don't explode when destroyed.

GLOBAL_LIST_EMPTY(spacepods_list)

GLOBAL_LIST_INIT(spacepod_verb_list, list(
	/obj/spacepod/verb/exit_pod,
	/obj/spacepod/verb/lock_pod,
	/obj/spacepod/verb/toggle_brakes,
	/obj/spacepod/verb/toggle_lights,
	/obj/spacepod/verb/toggle_doors,
	/obj/spacepod/verb/unload_cargo,
))

/obj/spacepod
	name = "space pod"
	desc = "A frame for a spacepod."
	icon = 'modular_nova/modules/spacepods/icons/construction_2x2.dmi'
	icon_state = "pod_1"
	density = TRUE
	opacity = FALSE
	dir = NORTH // always points north because why not; we rotate via transform.
	layer = SPACEPOD_LAYER
	bound_width = 64
	bound_height = 64
	animate_movement = NO_STEPS
	anchored = TRUE
	resistance_flags = LAVA_PROOF | FIRE_PROOF | UNACIDABLE | ACID_PROOF // it floats above lava or something, I dunno

	uses_integrity = TRUE
	max_integrity = 50
	integrity_failure = 0.2

	var/list/equipment = list()
	var/list/equipment_slot_limits = list(
		SPACEPOD_SLOT_MISC = 1,
		SPACEPOD_SLOT_CARGO = 2,
		SPACEPOD_SLOT_WEAPON = 1,
		SPACEPOD_SLOT_LOCK = 1,
	)
	var/obj/item/spacepod_equipment/lock/lock
	var/obj/item/spacepod_equipment/weaponry/weapon
	var/next_firetime = 0
	var/locked = FALSE
	var/hatch_open = FALSE
	var/construction_state = SPACEPOD_EMPTY
	var/obj/item/pod_parts/armor/pod_armor = null
	var/obj/item/stock_parts/power_store/cell/cell = null
	var/datum/gas_mixture/cabin_air
	var/obj/machinery/portable_atmospherics/canister/internal_tank
	var/last_slowprocess = 0

	var/mob/living/pilot
	var/list/passengers = list()
	var/max_passengers = 0
	/// Assoc list of mob -> list of granted /datum/action/spacepod instances.
	var/list/occupant_actions = list()

	var/velocity_x = 0 // tiles per second.
	var/velocity_y = 0
	var/offset_x = 0 // fractional-tile physics accumulator; rendered via step_x/step_y
	var/offset_y = 0
	var/angle = 0 // degrees, clockwise
	var/desired_angle = null // set by the pilot aiming
	var/angular_velocity = 0 // degrees per second
	var/max_angular_acceleration = 360 // in degrees per second per second
	var/last_thrust_forward = 0
	var/last_thrust_right = 0
	var/last_rotate = 0

	var/brakes = TRUE
	var/user_thrust_dir = 0
	var/forward_maxthrust = 6
	var/backward_maxthrust = 3
	var/side_maxthrust = 1

	var/lights = FALSE
	var/lights_power = 6
	var/static/list/icon_light_color = list(
		"pod_civ" = LIGHT_COLOR_HALOGEN,
		"pod_mil" = LIGHT_COLOR_GREEN,
		"pod_synd" = LIGHT_COLOR_FLARE,
		"pod_gold" = LIGHT_COLOR_HALOGEN,
		"pod_black" = LIGHT_COLOR_DARK_BLUE,
		"pod_industrial" = LIGHT_COLOR_TUNGSTEN,
	)

	var/bump_impulse = 0.6
	var/bounce_factor = 0.2 // how much of our velocity to keep on collision
	var/lateral_bounce_factor = 0.95 // mostly there to slow you down when you drive down a 2x2 corridor

/obj/spacepod/Initialize(mapload)
	. = ..()
	GLOB.spacepods_list += src
	START_PROCESSING(SSfastprocess, src)
	cabin_air = new
	cabin_air.set_temperature(T20C)
	cabin_air.volume = 200

/obj/spacepod/Destroy()
	GLOB.spacepods_list -= src
	STOP_PROCESSING(SSfastprocess, src)
	for(var/mob/rider in occupant_actions)
		remove_actions(rider)
	QDEL_NULL(pilot)
	QDEL_LIST(passengers)
	QDEL_LIST(equipment)
	QDEL_NULL(cabin_air)
	QDEL_NULL(cell)
	return ..()

/obj/spacepod/attackby(obj/item/weapon, mob/living/user, list/modifiers, list/attack_modifiers)
	if(user.combat_mode)
		return ..()
	if(construction_state != SPACEPOD_ARMOR_WELDED)
		. = handle_spacepod_construction(weapon, user)
		if(.)
			return
		return ..()
	// fully built: maintenance interactions
	if(weapon.tool_behaviour == TOOL_CROWBAR)
		if(hatch_open || !locked)
			hatch_open = !hatch_open
			weapon.play_tool_sound(src)
			to_chat(user, span_notice("You [hatch_open ? "open" : "close"] the maintenance hatch."))
		else
			to_chat(user, span_warning("The hatch is locked shut!"))
		return TRUE
	if(istype(weapon, /obj/item/stock_parts/power_store/cell))
		if(!hatch_open)
			to_chat(user, span_warning("The maintenance hatch is closed!"))
			return TRUE
		if(cell)
			to_chat(user, span_notice("The pod already has a battery."))
			return TRUE
		if(user.transferItemToLoc(weapon, src))
			to_chat(user, span_notice("You insert [weapon] into the pod."))
			cell = weapon
		return TRUE
	if(istype(weapon, /obj/item/spacepod_equipment))
		if(!hatch_open)
			to_chat(user, span_warning("The maintenance hatch is closed!"))
			return TRUE
		var/obj/item/spacepod_equipment/equip = weapon
		if(equip.can_install(src, user) && user.temporarilyRemoveItemFromInventory(equip))
			equip.forceMove(src)
			equip.on_install(src)
		return TRUE
	if(lock && istype(weapon, /obj/item/lock_buster))
		var/obj/item/lock_buster/buster = weapon
		if(buster.on)
			user.visible_message(span_warning("[user] is drilling through [src]'s lock!"),
				span_notice("You start drilling through [src]'s lock!"))
			if(do_after(user, 10 SECONDS * weapon.toolspeed, target = src))
				if(lock)
					var/obj/old_lock = lock
					lock.on_uninstall()
					qdel(old_lock)
					user.visible_message(span_warning("[user] has destroyed [src]'s lock!"),
						span_notice("You destroy [src]'s lock!"))
			else
				user.visible_message(span_warning("[user] fails to break through [src]'s lock!"),
					span_notice("You were unable to break through [src]'s lock!"))
			return TRUE
		to_chat(user, span_notice("Turn the [buster] on first."))
		return TRUE
	if(weapon.tool_behaviour == TOOL_WELDER)
		var/repairing = cell || internal_tank || length(equipment) || (get_integrity() < max_integrity) || pilot || length(passengers)
		if(!hatch_open)
			to_chat(user, span_warning("You must open the maintenance hatch before [repairing ? "attempting repairs" : "unwelding the armor"]."))
			return TRUE
		if(repairing && get_integrity() >= max_integrity)
			to_chat(user, span_warning("[src] is fully repaired!"))
			return TRUE
		to_chat(user, span_notice("You start [repairing ? "repairing [src]" : "slicing off [src]'s armor"]."))
		if(weapon.use_tool(src, user, 50, amount = 3, volume = 50))
			if(repairing)
				repair_damage(10)
				to_chat(user, span_notice("You mend some [pick("dents", "bumps", "damage")] with [weapon]."))
			else if(!cell && !internal_tank && !length(equipment) && !pilot && !length(passengers) && construction_state == SPACEPOD_ARMOR_WELDED)
				user.visible_message(span_notice("[user] slices off [src]'s armor."), span_notice("You slice off [src]'s armor."))
				construction_state = SPACEPOD_ARMOR_SECURED
				update_icon()
		return TRUE
	return ..()

/obj/spacepod/attack_hand(mob/living/user, list/modifiers)
	if(user.combat_mode && !locked)
		var/mob/living/target
		if(pilot)
			target = pilot
		else if(length(passengers))
			target = passengers[1]

		if(istype(target))
			visible_message(span_warning("[user] is trying to rip the door open and pull [target] out of [src]!"),
				span_warning("You see [user] outside the door trying to rip it open!"))
			if(do_after(user, 5 SECONDS, target = src) && construction_state == SPACEPOD_ARMOR_WELDED)
				if(remove_rider(target))
					target.Stun(2 SECONDS)
					target.visible_message(span_warning("[user] flings the door open and tears [target] out of [src]!"),
						span_warning("The door flies open and you are thrown out of [src] and to the ground!"))
				return
			target.visible_message(span_warning("[user] was unable to get the door open!"),
				span_warning("You manage to keep [user] out of [src]!"))

	if(!hatch_open)
		return ..()
	var/list/items = list(cell, internal_tank)
	items += equipment
	var/list/item_map = list()
	var/list/used_key_list = list()
	for(var/obj/item_in_pod in items)
		item_map[avoid_assoc_duplicate_keys(item_in_pod.name, used_key_list)] = item_in_pod
	var/selection = tgui_input_list(user, "Remove which equipment?", "Spacepod", item_map)
	var/obj/chosen = item_map[selection]
	if(!chosen || !(chosen in contents))
		return
	if(chosen == cell)
		cell = null
	else if(chosen == internal_tank)
		internal_tank = null
	else if(chosen in equipment)
		var/obj/item/spacepod_equipment/equip = chosen
		if(!equip.can_uninstall(user))
			return
		equip.on_uninstall()
	else
		return
	chosen.forceMove(loc)
	if(isitem(chosen))
		user.put_in_hands(chosen)

/obj/spacepod/proc/add_armor(obj/item/pod_parts/armor/armor)
	desc = armor.pod_desc
	max_integrity = armor.pod_integrity
	update_integrity(max_integrity)
	pod_armor = armor
	update_icon()

/obj/spacepod/proc/remove_armor()
	max_integrity = initial(max_integrity)
	update_integrity(max_integrity)
	desc = initial(desc)
	pod_armor = null
	update_icon()

/// Click intercept set on the pilot: aim toward the clicked target and fire.
/obj/spacepod/proc/InterceptClickOn(mob/user, params, atom/target)
	var/list/params_list = params2list(params)
	if(target == src || istype(target, /atom/movable/screen) || (target in user.get_all_contents()) || user != pilot || params_list["shift"] || params_list["alt"] || params_list["ctrl"])
		return FALSE
	var/turf/our_turf = get_turf(src)
	var/turf/target_turf = get_turf(target)
	if(our_turf && target_turf && our_turf != target_turf)
		desired_angle = 90 - ATAN2(target_turf.x - our_turf.x, target_turf.y - our_turf.y)
	if(weapon)
		weapon.fire_weapons(target)
	return TRUE

/// Mouse move handler: continuously aims the pod toward the cursor.
/obj/spacepod/proc/on_mouse_move(mob/user, params)
	if(user != pilot || !pilot.client || pilot.incapacitated)
		return
	var/list/params_list = params2list(params)
	var/screen_loc_raw = params_list["screen-loc"]
	if(!screen_loc_raw)
		return
	var/list/sl_parts = splittext(screen_loc_raw, ",")
	if(length(sl_parts) < 2)
		return
	var/list/sl_x_parts = splittext(sl_parts[1], ":")
	var/list/sl_y_parts = splittext(sl_parts[2], ":")
	var/list/view_size = getviewsize(pilot.client.view)
	var/dx = text2num(sl_x_parts[1]) + (text2num(sl_x_parts[2]) / ICON_SIZE_X) - 1 - view_size[1] / 2
	var/dy = text2num(sl_y_parts[1]) + (text2num(sl_y_parts[2]) / ICON_SIZE_Y) - 1 - view_size[2] / 2
	if(sqrt(dx * dx + dy * dy) > 1)
		desired_angle = 90 - ATAN2(dx, dy)
	else
		desired_angle = null

/// Forward client mouse movement to the spacepod for continuous aiming.
/client/MouseMove(object, location, control, params)
	. = ..()
	if(isspacepod(mob?.loc))
		var/obj/spacepod/pod = mob.loc
		pod.on_mouse_move(mob, params)

/obj/spacepod/on_update_integrity(old_value, new_value)
	. = ..()
	update_icon()

/obj/spacepod/return_air()
	return cabin_air

/obj/spacepod/remove_air(amount)
	return cabin_air.remove(amount)

/obj/spacepod/proc/slowprocess()
	if(cabin_air && cabin_air.return_volume() > 0)
		var/delta = cabin_air.return_temperature() - T20C
		cabin_air.set_temperature(cabin_air.return_temperature() - max(-10, min(10, round(delta / 4, 0.1))))
	if(internal_tank && cabin_air)
		var/datum/gas_mixture/tank_air = internal_tank.return_air()
		var/release_pressure = ONE_ATMOSPHERE
		var/cabin_pressure = cabin_air.return_pressure()
		var/pressure_delta = min(release_pressure - cabin_pressure, (tank_air.return_pressure() - cabin_pressure) / 2)
		var/transfer_moles = 0
		if(pressure_delta > 0) // cabin pressure lower than release pressure
			if(tank_air.return_temperature() > 0)
				transfer_moles = pressure_delta * cabin_air.return_volume() / (cabin_air.return_temperature() * R_IDEAL_GAS_EQUATION)
				var/datum/gas_mixture/removed = tank_air.remove(transfer_moles)
				cabin_air.merge(removed)
		else if(pressure_delta < 0) // cabin pressure higher than release pressure
			var/turf/our_turf = get_turf(src)
			var/datum/gas_mixture/turf_air = our_turf?.return_air()
			pressure_delta = cabin_pressure - release_pressure
			if(turf_air)
				pressure_delta = min(cabin_pressure - turf_air.return_pressure(), pressure_delta)
			if(pressure_delta > 0) // if location pressure is lower than cabin pressure
				transfer_moles = pressure_delta * cabin_air.return_volume() / (cabin_air.return_temperature() * R_IDEAL_GAS_EQUATION)
				var/datum/gas_mixture/removed = cabin_air.remove(transfer_moles)
				if(our_turf)
					our_turf.assume_air(removed)
				else // just delete the cabin gas, we're in space or some shit
					qdel(removed)

/mob/get_status_tab_items()
	. = ..()
	if(!isspacepod(loc))
		return
	var/obj/spacepod/pod = loc
	. += ""
	. += "Spacepod Charge: [pod.cell ? "[round(pod.cell.charge, 0.1)]/[pod.cell.maxcharge] kJ" : "NONE"]"
	. += "Spacepod Integrity: [round(pod.get_integrity(), 0.1)]/[pod.max_integrity]"
	. += "Spacepod Velocity: [round(sqrt(pod.velocity_x * pod.velocity_x + pod.velocity_y * pod.velocity_y), 0.1)] m/s"

/obj/spacepod/atom_break(damage_flag)
	. = ..()
	if(construction_state < SPACEPOD_ARMOR_LOOSE)
		return
	if(pod_armor)
		var/obj/old_armor = pod_armor
		remove_armor()
		qdel(old_armor)
		if(prob(40))
			new /obj/item/stack/sheet/iron/five(loc)
	if(prob(40))
		new /obj/item/stack/sheet/iron/five(loc)
	construction_state = SPACEPOD_CORE_SECURED
	if(cabin_air)
		var/datum/gas_mixture/dumped = cabin_air.remove_ratio(1)
		var/turf/our_turf = get_turf(src)
		if(dumped && our_turf)
			our_turf.assume_air(dumped)
	cell = null
	internal_tank = null
	for(var/atom/movable/thing as anything in contents)
		if(thing in equipment)
			var/obj/item/spacepod_equipment/equip = thing
			if(istype(equip))
				equip.on_uninstall()
		if(isliving(thing))
			remove_rider(thing)
		else if(prob(60))
			thing.forceMove(loc)
		else if(isitem(thing) || !isobj(thing))
			qdel(thing)
		else
			var/obj/wreck = thing
			wreck.forceMove(loc)
			wreck.deconstruct(FALSE)

/obj/spacepod/handle_deconstruct(disassembled)
	if(!get_turf(src))
		return
	remove_rider(pilot)
	while(length(passengers))
		remove_rider(passengers[1])
	passengers.Cut()
	if(!disassembled)
		return
	// give the frame pieces back, aligned to our current facing.
	var/clamped_angle = (round(angle, 90) % 360 + 360) % 360
	var/target_dir = NORTH
	switch(clamped_angle)
		if(0)
			target_dir = NORTH
		if(90)
			target_dir = EAST
		if(180)
			target_dir = SOUTH
		if(270)
			target_dir = WEST

	var/list/frame_piece_types = list(
		/obj/item/pod_parts/pod_frame/aft_port,
		/obj/item/pod_parts/pod_frame/aft_starboard,
		/obj/item/pod_parts/pod_frame/fore_port,
		/obj/item/pod_parts/pod_frame/fore_starboard,
	)
	var/obj/item/pod_parts/pod_frame/current_piece = null
	var/turf/current_turf = get_turf(src)
	var/list/frame_pieces = list()
	for(var/frame_type in frame_piece_types)
		var/obj/item/pod_parts/pod_frame/frame = new frame_type
		frame.setDir(target_dir)
		frame.anchored = TRUE
		if(NORTH == turn(frame.dir, -frame.link_angle))
			current_piece = frame
		frame_pieces += frame
	while(current_piece && !current_piece.loc)
		if(!current_turf)
			break
		current_piece.forceMove(current_turf)
		current_turf = get_step(current_turf, turn(current_piece.dir, -current_piece.link_angle))
		current_piece = locate(current_piece.link_to) in frame_pieces

/obj/spacepod/update_icon()
	cut_overlays()
	if(construction_state != SPACEPOD_ARMOR_WELDED)
		icon = 'modular_nova/modules/spacepods/icons/construction_2x2.dmi'
		icon_state = "pod_[construction_state]"
		if(pod_armor && construction_state >= SPACEPOD_ARMOR_LOOSE)
			var/mutable_appearance/masked_armor = mutable_appearance('modular_nova/modules/spacepods/icons/construction_2x2.dmi', "armor_mask")
			var/mutable_appearance/armor_appearance = mutable_appearance(pod_armor.pod_icon, pod_armor.pod_icon_state)
			armor_appearance.blend_mode = BLEND_MULTIPLY
			masked_armor.overlays = list(armor_appearance)
			masked_armor.appearance_flags = KEEP_TOGETHER
			add_overlay(masked_armor)
		return

	if(pod_armor)
		icon = pod_armor.pod_icon
		icon_state = pod_armor.pod_icon_state
	else
		icon = 'modular_nova/modules/spacepods/icons/2x2.dmi'
		icon_state = initial(icon_state)

	if(get_integrity() <= max_integrity / 2)
		add_overlay(image(icon = 'modular_nova/modules/spacepods/icons/2x2.dmi', icon_state = "pod_damage"))
		if(get_integrity() <= max_integrity / 4)
			add_overlay(image(icon = 'modular_nova/modules/spacepods/icons/2x2.dmi', icon_state = "pod_fire"))

	if(weapon && weapon.overlay_icon_state)
		add_overlay(image(icon = weapon.overlay_icon, icon_state = weapon.overlay_icon_state))

	light_color = icon_light_color[icon_state] || LIGHT_COLOR_HALOGEN

	// Thrust overlays!
	var/list/left_thrusts = new /list(8)
	var/list/right_thrusts = new /list(8)
	for(var/cdir in GLOB.cardinals)
		left_thrusts[cdir] = 0
		right_thrusts[cdir] = 0
	var/back_thrust = 0
	if(last_thrust_right != 0)
		var/tdir = last_thrust_right > 0 ? WEST : EAST
		left_thrusts[tdir] = abs(last_thrust_right) / side_maxthrust
		right_thrusts[tdir] = abs(last_thrust_right) / side_maxthrust
	if(last_thrust_forward > 0)
		back_thrust = last_thrust_forward / forward_maxthrust
	if(last_thrust_forward < 0)
		left_thrusts[NORTH] = -last_thrust_forward / backward_maxthrust
		right_thrusts[NORTH] = -last_thrust_forward / backward_maxthrust
	if(last_rotate != 0)
		var/frac = abs(last_rotate) / max_angular_acceleration
		for(var/cdir in GLOB.cardinals)
			if(last_rotate > 0)
				right_thrusts[cdir] += frac
			else
				left_thrusts[cdir] += frac
	for(var/cdir in GLOB.cardinals)
		if(left_thrusts[cdir])
			add_overlay(image(icon = 'modular_nova/modules/spacepods/icons/overlays_2x2.dmi', icon_state = "rcs_left", dir = cdir))
		if(right_thrusts[cdir])
			add_overlay(image(icon = 'modular_nova/modules/spacepods/icons/overlays_2x2.dmi', icon_state = "rcs_right", dir = cdir))
	if(back_thrust)
		var/image/thrust_image = image(icon = 'modular_nova/modules/spacepods/icons/overlays_2x2.dmi', icon_state = "thrust")
		thrust_image.transform = matrix(1, 0, 0, 0, 1, -32)
		add_overlay(thrust_image)

/obj/spacepod/mouse_drop_receive(atom/movable/dropped, mob/user, params)
	if(user == pilot || (user in passengers) || construction_state != SPACEPOD_ARMOR_WELDED)
		return

	if(istype(dropped, /obj/machinery/portable_atmospherics/canister))
		if(internal_tank)
			to_chat(user, span_warning("[src] already has an internal tank!"))
			return
		if(!dropped.Adjacent(src))
			to_chat(user, span_warning("The canister is not close enough!"))
			return
		if(hatch_open)
			to_chat(user, span_warning("The hatch is shut!"))
		to_chat(user, span_notice("You begin inserting the canister into [src]."))
		if(do_after(user, 5 SECONDS, target = src) && construction_state == SPACEPOD_ARMOR_WELDED)
			to_chat(user, span_notice("You insert the canister into [src]."))
			dropped.forceMove(src)
			internal_tank = dropped
		return

	if(isliving(dropped))
		var/mob/living/target = dropped
		if(target != user && !locked)
			if(length(passengers) >= max_passengers && !pilot)
				to_chat(user, span_danger("[target.p_They()] can't fly the pod!"))
				return
			if(length(passengers) < max_passengers)
				visible_message(span_danger("[user] starts loading [target] into [src]!"))
				if(do_after(user, 5 SECONDS, target = src) && construction_state == SPACEPOD_ARMOR_WELDED)
					add_rider(target, FALSE)
			return
		if(target == user)
			enter_pod(user)
			return

	return ..()

/obj/spacepod/proc/enter_pod(mob/living/user)
	if(user.stat != CONSCIOUS)
		return FALSE
	if(locked)
		to_chat(user, span_warning("[src]'s doors are locked!"))
		return FALSE
	if(!istype(user))
		return FALSE
	if(user.incapacitated)
		return FALSE
	if(!ishuman(user))
		return FALSE

	if(length(passengers) <= max_passengers || !pilot)
		visible_message(span_notice("[user] starts to climb into [src]."))
		if(do_after(user, 4 SECONDS, target = src) && construction_state == SPACEPOD_ARMOR_WELDED)
			var/success = add_rider(user)
			if(!success)
				to_chat(user, span_notice("You were too slow. Try better next time, loser."))
			return success
		to_chat(user, span_notice("You stop entering [src]."))
	else
		to_chat(user, span_danger("You can't fit in [src], it's full!"))
	return FALSE

/obj/spacepod/proc/verb_check(require_pilot = TRUE, mob/user)
	if(!user)
		user = usr
	if(require_pilot && user != pilot)
		to_chat(user, span_notice("You can't reach the controls from your chair."))
		return FALSE
	return !user.incapacitated && isliving(user)

/obj/spacepod/verb/exit_pod()
	set name = "Exit pod"
	set category = "Spacepod"
	set src = usr.loc

	if(!isliving(usr) || usr.stat > CONSCIOUS)
		return

	if(HAS_TRAIT(usr, TRAIT_HANDS_BLOCKED))
		to_chat(usr, span_notice("You attempt to stumble out of [src]. This will take two minutes."))
		if(pilot)
			to_chat(pilot, span_warning("[usr] is trying to escape [src]."))
		if(!do_after(usr, 2 MINUTES, target = src))
			return

	if(remove_rider(usr))
		to_chat(usr, span_notice("You climb out of [src]."))

/obj/spacepod/verb/lock_pod()
	set name = "Lock Doors"
	set category = "Spacepod"
	set src = usr.loc

	if(!verb_check(FALSE))
		return

	if(!lock)
		to_chat(usr, span_warning("[src] has no locking mechanism."))
		locked = FALSE // should never be TRUE without a lock, but force-unlock if it somehow happens.
	else
		locked = !locked
		to_chat(usr, span_warning("You [locked ? "lock" : "unlock"] the doors."))

/obj/spacepod/verb/toggle_brakes()
	set name = "Toggle Brakes"
	set category = "Spacepod"
	set src = usr.loc

	if(!verb_check())
		return
	brakes = !brakes
	to_chat(usr, span_notice("You toggle the brakes [brakes ? "on" : "off"]."))

/obj/spacepod/verb/toggle_lights()
	set name = "Toggle Lights"
	set category = "Spacepod"
	set src = usr.loc

	if(!verb_check())
		return

	lights = !lights
	set_light(lights ? lights_power : 0)
	to_chat(usr, "Lights toggled [lights ? "on" : "off"].")
	for(var/mob/passenger in passengers)
		to_chat(passenger, "Lights toggled [lights ? "on" : "off"].")

/obj/spacepod/verb/toggle_doors()
	set name = "Toggle Nearby Pod Doors"
	set category = "Spacepod"
	set src = usr.loc

	if(!verb_check())
		return

	for(var/obj/machinery/door/poddoor/pod_door in orange(3, src))
		for(var/mob/living/carbon/human/occupant in contents)
			if(pod_door.check_access(occupant.get_active_held_item()) || pod_door.check_access(occupant.wear_id))
				if(pod_door.density)
					pod_door.open()
				else
					pod_door.close()
				return TRUE
		to_chat(usr, span_warning("Access denied."))
		return

	to_chat(usr, span_warning("You are not close to any pod doors."))

/obj/spacepod/proc/add_rider(mob/living/rider, allow_pilot = TRUE)
	if(rider == pilot || (rider in passengers))
		return FALSE
	if(!pilot && allow_pilot)
		pilot = rider
		rider.click_intercept = src
	else if(length(passengers) < max_passengers)
		passengers += rider
	else
		return FALSE
	rider.stop_pulling()
	rider.forceMove(src)
	grant_actions(rider)
	playsound(src, 'sound/machines/windowdoor.ogg', 50, TRUE)
	return TRUE

/obj/spacepod/proc/remove_rider(mob/living/rider)
	if(!rider)
		return
	remove_actions(rider)
	if(rider == pilot)
		pilot = null
		if(rider.click_intercept == src)
			rider.click_intercept = null
		desired_angle = null
	else if(rider in passengers)
		passengers -= rider
	else
		return FALSE
	if(rider.loc == src)
		rider.forceMove(loc)
	if(rider.client)
		rider.client.pixel_x = 0
		rider.client.pixel_y = 0
	return TRUE

/// All action types a pilot gets.
/obj/spacepod/var/static/list/pilot_action_types = list(
	/datum/action/spacepod/exit_pod,
	/datum/action/spacepod/toggle_brakes,
	/datum/action/spacepod/toggle_lights,
	/datum/action/spacepod/lock_pod,
	/datum/action/spacepod/toggle_doors,
	/datum/action/spacepod/unload_cargo,
)

/// Action types passengers get.
/obj/spacepod/var/static/list/passenger_action_types = list(
	/datum/action/spacepod/exit_pod,
	/datum/action/spacepod/lock_pod,
)

/obj/spacepod/proc/grant_actions(mob/rider)
	var/list/types = (rider == pilot) ? pilot_action_types : passenger_action_types
	var/list/actions = list()
	for(var/action_type in types)
		var/datum/action/spacepod/act = new action_type(src)
		act.Grant(rider)
		actions += act
	occupant_actions[rider] = actions

/obj/spacepod/proc/remove_actions(mob/rider)
	var/list/actions = occupant_actions[rider]
	if(!actions)
		return
	for(var/datum/action/act in actions)
		qdel(act)
	occupant_actions -= rider

/obj/spacepod/relaymove(mob/living/user, direction)
	if(user != pilot || pilot.incapacitated)
		return
	user_thrust_dir = direction
