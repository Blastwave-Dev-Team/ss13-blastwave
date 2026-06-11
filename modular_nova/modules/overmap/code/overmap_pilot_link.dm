// MODULE ID: OVERMAP
// Shared pilot link datum. Both the NIFSoft and neurohelm paths create one
// of these to handle the common piloting logic: perspective swap, relaymove
// intercept, screen HUD management, and unlink conditions.

/datum/overmap_pilot_link
	/// The mob currently linked as pilot.
	var/mob/living/linked_mob
	/// The ship being piloted.
	var/obj/structure/overmap/ship/linked_ship
	/// Screen HUD objects added to the client.
	var/list/atom/movable/screen/hud_objects
	/// Whether this link is currently active.
	var/active = FALSE

/datum/overmap_pilot_link/New(mob/living/pilot, obj/structure/overmap/ship/ship)
	. = ..()
	if(!pilot || !ship)
		qdel(src)
		return
	linked_mob = pilot
	linked_ship = ship

/datum/overmap_pilot_link/Destroy()
	if(active)
		unlink()
	linked_mob = null
	linked_ship = null
	return ..()

/// Activate the pilot link: perspective swap, register signals, add HUD.
/datum/overmap_pilot_link/proc/establish()
	if(!linked_mob || !linked_ship)
		return FALSE
	if(active)
		return FALSE

	// Check ship supports direct control
	if(!(linked_ship.control_flags & SHIP_CONTROL_DIRECT))
		to_chat(linked_mob, span_warning("This vessel does not support direct neural piloting."))
		return FALSE

	active = TRUE

	// Perspective swap to the ship on the overmap
	linked_mob.reset_perspective(linked_ship)

	// Register relaymove intercept
	RegisterSignal(linked_mob, COMSIG_MOB_CLIENT_PRE_LIVING_MOVE, PROC_REF(on_mob_move))

	// Register unlink conditions
	RegisterSignal(linked_mob, COMSIG_LIVING_DEATH, PROC_REF(on_death))
	RegisterSignal(linked_mob, COMSIG_MOB_LOGOUT, PROC_REF(on_logout))

	// Add pilot HUD screen objects
	add_pilot_hud()

	return TRUE

/// Deactivate the pilot link: restore perspective, remove signals, remove HUD.
/datum/overmap_pilot_link/proc/unlink()
	if(!active)
		return
	active = FALSE

	// Remove HUD
	remove_pilot_hud()

	// Unregister signals
	if(linked_mob)
		UnregisterSignal(linked_mob, list(
			COMSIG_MOB_CLIENT_PRE_LIVING_MOVE,
			COMSIG_LIVING_DEATH,
			COMSIG_MOB_LOGOUT,
		))
		// Restore normal perspective
		linked_mob.reset_perspective()

/// Signal handler: intercept mob movement and convert to ship thrust.
/datum/overmap_pilot_link/proc/on_mob_move(mob/source, list/move_args)
	SIGNAL_HANDLER
	if(!active || !linked_ship)
		return
	var/direction = move_args[2]
	if(!direction)
		return
	linked_ship.burn_direction(direction, 1)
	return COMSIG_MOB_CLIENT_BLOCK_PRE_LIVING_MOVE

/// Signal handler: unlink on death.
/datum/overmap_pilot_link/proc/on_death(mob/source)
	SIGNAL_HANDLER
	unlink()

/// Signal handler: unlink on logout.
/datum/overmap_pilot_link/proc/on_logout(mob/source)
	SIGNAL_HANDLER
	unlink()

/// Add screen objects for the pilot HUD overlay.
/datum/overmap_pilot_link/proc/add_pilot_hud()
	if(!linked_mob?.client)
		return
	hud_objects = list()
	var/atom/movable/screen/pilot_hud/brake/brake_btn = new
	brake_btn.parent_link = src
	hud_objects += brake_btn
	var/atom/movable/screen/pilot_hud/speed_readout/speed = new
	speed.parent_link = src
	hud_objects += speed
	for(var/atom/movable/screen/obj as anything in hud_objects)
		linked_mob.client.screen += obj

/// Remove screen objects for the pilot HUD overlay.
/datum/overmap_pilot_link/proc/remove_pilot_hud()
	if(linked_mob?.client && length(hud_objects))
		for(var/atom/movable/screen/obj as anything in hud_objects)
			linked_mob.client.screen -= obj
	QDEL_LIST(hud_objects)
	hud_objects = null
