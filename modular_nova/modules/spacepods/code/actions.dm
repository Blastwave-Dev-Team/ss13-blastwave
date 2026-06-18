// MODULE ID: SPACEPODS
// HUD action buttons for spacepod controls.
// These replace the old verb-panel approach with proper /datum/action buttons
// that appear on the pilot/passenger HUD.

/datum/action/spacepod
	check_flags = AB_CHECK_CONSCIOUS
	button_icon = 'icons/mob/actions/actions_mecha.dmi'
	button_icon_state = "mech_view_stats"
	/// The spacepod this action controls.
	var/obj/spacepod/pod
	/// If TRUE, only the pilot can see/use this action.
	var/pilot_only = TRUE

/datum/action/spacepod/New(Target)
	..()
	if(istype(Target, /obj/spacepod))
		pod = Target

/datum/action/spacepod/Destroy()
	pod = null
	return ..()

/datum/action/spacepod/IsAvailable(feedback)
	if(!pod || QDELETED(pod))
		return FALSE
	if(!(owner in pod.contents))
		return FALSE
	if(pilot_only && owner != pod.pilot)
		return FALSE
	return ..()

// ---- Exit Pod ----

/datum/action/spacepod/exit_pod
	name = "Exit Pod"
	button_icon = 'icons/mob/actions/actions_vehicle.dmi'
	button_icon_state = "car_eject"
	pilot_only = FALSE

/datum/action/spacepod/exit_pod/Trigger(trigger_flags)
	. = ..()
	if(!.)
		return
	var/mob/living/user = owner
	if(!istype(user) || user.stat > CONSCIOUS)
		return
	if(HAS_TRAIT(user, TRAIT_HANDS_BLOCKED))
		to_chat(user, span_notice("You attempt to stumble out of [pod]. This will take two minutes."))
		if(pod.pilot)
			to_chat(pod.pilot, span_warning("[user] is trying to escape [pod]."))
		if(!do_after(user, 2 MINUTES, target = pod))
			return
	if(pod.remove_rider(user))
		to_chat(user, span_notice("You climb out of [pod]."))

// ---- Toggle Brakes ----

/datum/action/spacepod/toggle_brakes
	name = "Toggle Brakes"
	button_icon_state = "mech_safeties_on"

/datum/action/spacepod/toggle_brakes/Trigger(trigger_flags)
	. = ..()
	if(!.)
		return
	if(owner.incapacitated)
		return
	pod.brakes = !pod.brakes
	button_icon_state = "mech_safeties_[pod.brakes ? "on" : "off"]"
	build_all_button_icons()
	to_chat(owner, span_notice("You toggle the brakes [pod.brakes ? "on" : "off"]."))

// ---- Toggle Lights ----

/datum/action/spacepod/toggle_lights
	name = "Toggle Lights"
	button_icon_state = "mech_lights_off"

/datum/action/spacepod/toggle_lights/Trigger(trigger_flags)
	. = ..()
	if(!.)
		return
	if(owner.incapacitated)
		return
	pod.lights = !pod.lights
	pod.set_light(pod.lights ? pod.lights_power : 0)
	button_icon_state = "mech_lights_[pod.lights ? "on" : "off"]"
	build_all_button_icons()
	to_chat(owner, "Lights toggled [pod.lights ? "on" : "off"].")
	for(var/mob/passenger in pod.passengers)
		to_chat(passenger, "Lights toggled [pod.lights ? "on" : "off"].")

// ---- Lock Doors ----

/datum/action/spacepod/lock_pod
	name = "Lock Doors"
	button_icon = 'icons/mob/actions/actions_vehicle.dmi'
	button_icon_state = "car_removekey"
	pilot_only = FALSE

/datum/action/spacepod/lock_pod/Trigger(trigger_flags)
	. = ..()
	if(!.)
		return
	if(owner.incapacitated)
		return
	if(!pod.lock)
		to_chat(owner, span_warning("[pod] has no locking mechanism."))
		pod.locked = FALSE
	else
		pod.locked = !pod.locked
		to_chat(owner, span_warning("You [pod.locked ? "lock" : "unlock"] the doors."))

// ---- Toggle Nearby Pod Doors ----

/datum/action/spacepod/toggle_doors
	name = "Toggle Nearby Pod Doors"
	button_icon_state = "mech_cabin_open"

/datum/action/spacepod/toggle_doors/Trigger(trigger_flags)
	. = ..()
	if(!.)
		return
	if(owner.incapacitated)
		return
	for(var/obj/machinery/door/poddoor/pod_door in orange(3, pod))
		for(var/mob/living/carbon/human/occupant in pod.contents)
			if(pod_door.check_access(occupant.get_active_held_item()) || pod_door.check_access(occupant.wear_id))
				if(pod_door.density)
					pod_door.open()
				else
					pod_door.close()
				return
		to_chat(owner, span_warning("Access denied."))
		return
	to_chat(owner, span_warning("You are not close to any pod doors."))

// ---- Unload Cargo ----

/datum/action/spacepod/unload_cargo
	name = "Unload Cargo"
	button_icon = 'icons/mob/actions/actions_vehicle.dmi'
	button_icon_state = "car_dump"

/datum/action/spacepod/unload_cargo/Trigger(trigger_flags)
	. = ..()
	if(!.)
		return
	if(owner.incapacitated)
		return
	var/list/used_key_list = list()
	var/list/cargo_map = list()
	for(var/obj/item/spacepod_equipment/cargo/large/cargo_system in pod.equipment)
		if(!cargo_system.storage)
			continue
		cargo_map[avoid_assoc_duplicate_keys("[cargo_system.name] ([cargo_system.storage.name])", used_key_list)] = cargo_system
	if(!length(cargo_map))
		to_chat(owner, span_warning("There's no cargo to unload."))
		return
	var/selection = tgui_input_list(owner, "Unload which cargo?", "Spacepod", cargo_map)
	var/obj/item/spacepod_equipment/cargo/large/chosen = cargo_map[selection]
	if(!selection || owner.incapacitated || !(owner in pod.contents) || !chosen || !(chosen in pod.equipment) || !chosen.storage)
		return
	chosen.storage.forceMove(pod.loc)
	chosen.storage = null
	to_chat(owner, span_notice("Cargo ejected."))
