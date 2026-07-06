/obj/item/wallframe/apc
	var/mount_mode = WALLFRAME_APC

/obj/item/wallframe/apc/add_context(atom/source, list/context, obj/item/held_item, mob/user)
	. = ..()
	if(held_item == src)
		context[SCREENTIP_CONTEXT_LMB] = "Switch mount mode"
		return CONTEXTUAL_SCREENTIP_SET

/obj/item/wallframe/apc/examine(mob/user)
	. = ..()
	var/mode_name = (mount_mode == WALLFRAME_MEGACELL_CHARGER) ? "megacell charger frame" : "APC frame"
	. += span_notice("Mount mode: [mode_name]. [EXAMINE_HINT("Activate")] in hand to switch modes.")

/obj/item/wallframe/apc/attack_self(mob/user)
	mount_mode = (mount_mode == WALLFRAME_APC) ? WALLFRAME_MEGACELL_CHARGER : WALLFRAME_APC
	playsound(src, 'sound/machines/click.ogg', 50, TRUE)
	var/mode_name = (mount_mode == WALLFRAME_MEGACELL_CHARGER) ? "megacell charger frame" : "APC frame"
	balloon_alert(user, mode_name)

/obj/item/wallframe/apc/try_build(atom/support, mob/user)
	if(mount_mode == WALLFRAME_MEGACELL_CHARGER)
		var/area/place_area = get_area(user)
		if(!place_area.requires_power || place_area.always_unpowered)
			to_chat(user, span_warning("You cannot place [src] in this area!"))
			return FALSE
		var/turf/place_turf = get_turf(support)
		for(var/obj/machinery/power/terminal/terminal in place_turf)
			if(terminal.master)
				to_chat(user, span_warning("There is another network terminal here!"))
				return FALSE
		if(get_dist(support, user) > 1)
			balloon_alert(user, "you are too far!")
			return FALSE
		var/floor_to_support = get_dir(user, support)
		if(!(floor_to_support in GLOB.cardinals))
			balloon_alert(user, "stand in line with wall!")
			return FALSE
		var/turf/user_turf = get_turf(user)
		if(!isfloorturf(user_turf))
			balloon_alert(user, "cannot place here!")
			return FALSE
		if(check_wall_item(user_turf, floor_to_support, wall_external))
			balloon_alert(user, "already something here!")
			return FALSE
		return TRUE

	return ..()

/obj/item/wallframe/apc/interact_with_atom(atom/interacting_with, mob/living/user, list/modifiers)
	if(mount_mode != WALLFRAME_MEGACELL_CHARGER)
		return ..()

	var/static/charger_result = /obj/machinery/power/megacell_charger
	var/old_result_path = result_path
	result_path = charger_result
	. = ..()
	result_path = old_result_path
	return .
