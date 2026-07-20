/// Resolve the simulated overmap ship linked to the shuttle at `user`'s mob location.
/proc/overmap_debug_ship_from_mob(client/user)
	var/mob/mob_ref = user.mob
	if(!mob_ref)
		to_chat(user, span_warning("No mob found."))
		return null
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(mob_ref)
	if(!port)
		to_chat(user, span_warning("No shuttle at your location."))
		return null
	if(!port.current_ship)
		SSovermap.setup_shuttle_ship(port)
	if(!port.current_ship)
		to_chat(user, span_warning("Could not resolve overmap ship for shuttle [port.shuttle_id]."))
		return null
	if(!istype(port.current_ship, /obj/structure/overmap/ship/simulated))
		to_chat(user, span_warning("Overmap object [port.current_ship] is not a simulated ship."))
		return null
	return port.current_ship

/// Admin fast-path: force a docked/idle ship into flight so physics can run.
/proc/overmap_debug_ensure_flying(obj/structure/overmap/ship/simulated/ship, client/user)
	if(ship.state == OVERMAP_SHIP_FLYING && !ship.docked)
		return TRUE
	ship.all_stop()
	if(ship.docked)
		var/turf/departure = get_turf(ship.docked) || SSovermap.get_unused_overmap_square()
		if(departure)
			ship.overmap_reset_visual_offset()
			ship.forceMove(departure)
		ship.docked = null
	ship.state = OVERMAP_SHIP_FLYING
	ship.prepare_for_flight()
	to_chat(user, span_notice("Forced [ship.name] into flight (debug)."))
	if(ship.avg_fuel_amnt <= 0)
		to_chat(user, span_warning("[ship.name] has no fuel — engines may not produce thrust."))
	return TRUE

/proc/overmap_debug_burn_direction(client/user, direction, dir_label)
	var/obj/structure/overmap/ship/simulated/ship = overmap_debug_ship_from_mob(user)
	if(!ship)
		return
	if(!overmap_debug_ensure_flying(ship, user))
		return
	ship.diag_hold_physics = FALSE
	ship.burn_direction(direction, 1)
	var/shuttle_id = ship.shuttle?.shuttle_id || "unknown"
	to_chat(user, span_notice("Burning [dir_label] at full throttle on [ship.name] ([shuttle_id])."))
	message_admins("[key_name_admin(user)] overmap burn [dir_label] on [ship.name] ([shuttle_id]).")
	log_admin("[key_name(user)] overmap burn [dir_label] on [ship.name] ([shuttle_id]).")

ADMIN_VERB(overmap_activate_physics, R_DEBUG, "Overmap Activate Physics", "Start SSfastprocess on the area shuttle with zero velocity (no burn).", ADMIN_CATEGORY_DEBUG)
	var/obj/structure/overmap/ship/simulated/ship = overmap_debug_ship_from_mob(user)
	if(!ship)
		return
	if(!overmap_debug_ensure_flying(ship, user))
		return
	ship.all_stop()
	ship.diag_hold_physics = TRUE
	ship.activate_physics()
	var/shuttle_id = ship.shuttle?.shuttle_id || "unknown"
	to_chat(user, span_notice("Activated physics (hold, no thrust) on [ship.name] ([shuttle_id]). Walk around and test glide."))
	message_admins("[key_name_admin(user)] overmap activate physics (hold) on [ship.name] ([shuttle_id]).")
	log_admin("[key_name(user)] overmap activate physics (hold) on [ship.name] ([shuttle_id]).")

ADMIN_VERB(overmap_deactivate_physics, R_DEBUG, "Overmap Deactivate Physics", "Stop SSfastprocess on the area shuttle and clear diag hold.", ADMIN_CATEGORY_DEBUG)
	var/obj/structure/overmap/ship/simulated/ship = overmap_debug_ship_from_mob(user)
	if(!ship)
		return
	ship.diag_hold_physics = FALSE
	ship.deactivate_physics()
	var/shuttle_id = ship.shuttle?.shuttle_id || "unknown"
	to_chat(user, span_notice("Deactivated physics on [ship.name] ([shuttle_id])."))
	message_admins("[key_name_admin(user)] overmap deactivate physics on [ship.name] ([shuttle_id]).")
	log_admin("[key_name(user)] overmap deactivate physics on [ship.name] ([shuttle_id]).")

ADMIN_VERB(overmap_burn_north, R_DEBUG, "Overmap Burn North", "Burn due north at full throttle on the shuttle in your current area.", ADMIN_CATEGORY_DEBUG)
	overmap_debug_burn_direction(user, NORTH, "north")

ADMIN_VERB(overmap_burn_east, R_DEBUG, "Overmap Burn East", "Burn due east at full throttle on the shuttle in your current area.", ADMIN_CATEGORY_DEBUG)
	overmap_debug_burn_direction(user, EAST, "east")

ADMIN_VERB(overmap_burn_south, R_DEBUG, "Overmap Burn South", "Burn due south at full throttle on the shuttle in your current area.", ADMIN_CATEGORY_DEBUG)
	overmap_debug_burn_direction(user, SOUTH, "south")

ADMIN_VERB(overmap_burn_west, R_DEBUG, "Overmap Burn West", "Burn due west at full throttle on the shuttle in your current area.", ADMIN_CATEGORY_DEBUG)
	overmap_debug_burn_direction(user, WEST, "west")

ADMIN_VERB(overmap_all_stop, R_DEBUG, "Overmap All Stop", "All-stop the shuttle in your current area.", ADMIN_CATEGORY_DEBUG)
	var/obj/structure/overmap/ship/simulated/ship = overmap_debug_ship_from_mob(user)
	if(!ship)
		return
	ship.diag_hold_physics = FALSE
	ship.all_stop()
	var/shuttle_id = ship.shuttle?.shuttle_id || "unknown"
	to_chat(user, span_notice("All-stop on [ship.name] ([shuttle_id])."))
	message_admins("[key_name_admin(user)] overmap all stop on [ship.name] ([shuttle_id]).")
	log_admin("[key_name(user)] overmap all stop on [ship.name] ([shuttle_id]).")

ADMIN_VERB(landing_zone_panel, R_ADMIN, "Landing Zone Manipulator", "Opens the landing zone manipulator UI.", ADMIN_CATEGORY_SHUTTLE)
	SSovermap.ui_interact(user.mob)
