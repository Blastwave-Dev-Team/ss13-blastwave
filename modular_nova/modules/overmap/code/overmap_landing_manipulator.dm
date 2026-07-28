// MODULE ID: OVERMAP
// Admin Landing Zone Manipulator — Shuttle Manipulator–style TGUI on SSovermap.

/datum/controller/subsystem/overmap/ui_state(mob/user)
	return ADMIN_STATE(R_ADMIN)

/datum/controller/subsystem/overmap/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "LandingZoneManipulator")
		ui.open()

/datum/controller/subsystem/overmap/ui_data(mob/user)
	var/list/data = list()
	data["overmap_factions"] = get_overmap_faction_ui_options()
	data["cap"] = CONFIG_GET(number/max_overmap_landing_zone_dimension)

	var/list/zones = list()
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in landing_zones)
		if(QDELETED(zone))
			continue
		var/obj/machinery/computer/landing_controller/manager = find_landing_controller_for_zone(zone)
		var/obj/docking_port/mobile/occupant = zone.get_occupant()
		zones += list(list(
			"ref" = REF(zone),
			"name" = zone.zone_name,
			"width" = zone.zone_width,
			"height" = zone.zone_height,
			"x" = zone.x,
			"y" = zone.y,
			"z" = zone.z,
			"faction" = zone.dock_affiliation || "",
			"exit_direction" = zone.exit_direction,
			"occupied" = !isnull(occupant),
			"occupant_name" = occupant?.name,
			"managed" = !isnull(manager),
			"controller_ref" = manager ? REF(manager) : null,
		))
	data["zones"] = zones

	var/list/controllers = list()
	for(var/obj/machinery/computer/landing_controller/console as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/computer/landing_controller))
		if(QDELETED(console))
			continue
		var/occupant_name = console.get_zone_occupant()
		var/list/corner_entries = list()
		for(var/datum/weakref/corner_ref as anything in console.corners)
			var/obj/machinery/landing_corner/corner = corner_ref.resolve()
			if(QDELETED(corner))
				continue
			var/turf/corner_turf = get_turf(corner)
			corner_entries += list(list(
				"ref" = REF(corner),
				"x" = corner_turf?.x,
				"y" = corner_turf?.y,
				"z" = corner_turf?.z,
			))
		controllers += list(list(
			"ref" = REF(console),
			"name" = console.name,
			"label" = console.zone_label,
			"type" = "[console.type]",
			"x" = console.x,
			"y" = console.y,
			"z" = console.z,
			"faction" = console.dock_affiliation || "",
			"exit_direction" = console.exit_direction,
			"corners" = length(console.corners),
			"corner_list" = corner_entries,
			"active" = !QDELETED(console.active_zone),
			"invalid_reason" = console.invalid_reason,
			"width" = console.zone_width_cache,
			"height" = console.zone_height_cache,
			"powered" = console.is_operational,
			"force_power" = console.admin_force_operational,
			"occupied" = !isnull(occupant_name),
			"occupant_name" = occupant_name,
			"dock_policy" = console.get_dock_policy_label(),
			"zone_ref" = !QDELETED(console.active_zone) ? REF(console.active_zone) : null,
		))
	data["controllers"] = controllers
	return data

/datum/controller/subsystem/overmap/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	var/mob/user = usr
	if(!check_rights_for(user.client, R_ADMIN))
		return FALSE

	switch(action)
		if("jump_to")
			var/atom/target = locate(params["ref"])
			if(QDELETED(target))
				return FALSE
			user.forceMove(get_turf(target))
			return TRUE

		if("set_zone_name")
			var/obj/effect/landmark/overmap_landing_zone/zone = locate(params["ref"])
			if(QDELETED(zone))
				return FALSE
			var/new_label = trim(strip_html(params["name"], MAX_NAME_LEN))
			if(!length(new_label))
				return FALSE
			var/obj/machinery/computer/landing_controller/manager = find_landing_controller_for_zone(zone)
			if(manager)
				manager.zone_label = new_label
			zone.zone_name = new_label
			log_landing_manipulator(user, "renamed zone [zone] to [new_label]")
			return TRUE

		if("set_zone_faction")
			var/obj/effect/landmark/overmap_landing_zone/zone = locate(params["ref"])
			if(QDELETED(zone))
				return FALSE
			var/faction = normalize_landing_manipulator_faction(params["faction"])
			if(faction && !get_overmap_faction(faction))
				return FALSE
			var/obj/machinery/computer/landing_controller/manager = find_landing_controller_for_zone(zone)
			if(manager)
				manager.set_dock_affiliation(faction)
				apply_programmable_faction_lock(manager, faction)
			else
				zone.dock_affiliation = faction
			log_landing_manipulator(user, "set zone [zone] faction to [faction || "open"]")
			return TRUE

		if("set_zone_exit")
			var/obj/effect/landmark/overmap_landing_zone/zone = locate(params["ref"])
			if(QDELETED(zone))
				return FALSE
			var/new_dir = text2num(params["dir"])
			if(new_dir && !(new_dir in GLOB.cardinals))
				return FALSE
			var/obj/machinery/computer/landing_controller/manager = find_landing_controller_for_zone(zone)
			if(manager)
				manager.exit_direction = new_dir
			zone.exit_direction = new_dir
			log_landing_manipulator(user, "set zone [zone] exit to [new_dir ? dir2text(new_dir) : "none"]")
			return TRUE

		if("delete_zone")
			var/obj/effect/landmark/overmap_landing_zone/zone = locate(params["ref"])
			if(QDELETED(zone))
				return FALSE
			var/obj/machinery/computer/landing_controller/manager = find_landing_controller_for_zone(zone)
			if(manager)
				to_chat(user, span_warning("That zone is managed by a controller — clear or unlink it there instead."))
				return FALSE
			log_landing_manipulator(user, "deleted unmanaged zone [zone]")
			qdel(zone)
			return TRUE

		if("set_controller_name")
			var/obj/machinery/computer/landing_controller/console = locate(params["ref"])
			if(QDELETED(console))
				return FALSE
			var/new_label = trim(strip_html(params["name"], MAX_NAME_LEN))
			if(!length(new_label))
				return FALSE
			console.zone_label = new_label
			if(!QDELETED(console.active_zone))
				console.active_zone.zone_name = new_label
			log_landing_manipulator(user, "renamed controller [console] zone to [new_label]")
			return TRUE

		if("set_controller_faction")
			var/obj/machinery/computer/landing_controller/console = locate(params["ref"])
			if(QDELETED(console))
				return FALSE
			var/faction = normalize_landing_manipulator_faction(params["faction"])
			if(faction && !get_overmap_faction(faction))
				return FALSE
			console.set_dock_affiliation(faction)
			apply_programmable_faction_lock(console, faction)
			log_landing_manipulator(user, "set controller [console] faction to [faction || "open"]")
			return TRUE

		if("set_controller_exit")
			var/obj/machinery/computer/landing_controller/console = locate(params["ref"])
			if(QDELETED(console))
				return FALSE
			var/new_dir = text2num(params["dir"])
			if(new_dir && !(new_dir in GLOB.cardinals))
				return FALSE
			console.exit_direction = new_dir
			if(!QDELETED(console.active_zone))
				console.active_zone.exit_direction = new_dir
			log_landing_manipulator(user, "set controller [console] exit to [new_dir ? dir2text(new_dir) : "none"]")
			return TRUE

		if("toggle_force_power")
			var/obj/machinery/computer/landing_controller/console = locate(params["ref"])
			if(QDELETED(console))
				return FALSE
			console.admin_force_operational = !console.admin_force_operational
			console.recompute_zone()
			log_landing_manipulator(user, "[console.admin_force_operational ? "enabled" : "disabled"] force-power on [console]")
			return TRUE

		if("validate_controller")
			var/obj/machinery/computer/landing_controller/console = locate(params["ref"])
			if(QDELETED(console))
				return FALSE
			console.recompute_zone()
			return TRUE

		if("clear_controller_corners")
			var/obj/machinery/computer/landing_controller/console = locate(params["ref"])
			if(QDELETED(console))
				return FALSE
			console.clear_corner_backrefs()
			console.corners.Cut()
			console.recompute_zone()
			log_landing_manipulator(user, "cleared corners on [console]")
			return TRUE

		if("link_marked_corner")
			var/obj/machinery/computer/landing_controller/console = locate(params["ref"])
			if(QDELETED(console))
				return FALSE
			var/obj/machinery/landing_corner/corner = user.client?.holder?.marked_datum
			if(!istype(corner))
				to_chat(user, span_warning("Mark a landing zone corner beacon first (VV → Mark Object)."))
				return FALSE
			var/result = console.toggle_corner(corner)
			to_chat(user, span_notice("[corner] → [console]: [result]"))
			log_landing_manipulator(user, "linked marked corner [corner] to [console]: [result]")
			return TRUE

		if("spawn_kit")
			return admin_spawn_landing_kit(user, params)

		if("spawn_linked_zone")
			return admin_spawn_linked_landing_zone(user, params)

	return FALSE

/datum/controller/subsystem/overmap/proc/find_landing_controller_for_zone(obj/effect/landmark/overmap_landing_zone/zone)
	if(QDELETED(zone))
		return null
	for(var/obj/machinery/computer/landing_controller/console as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/computer/landing_controller))
		if(console.active_zone == zone)
			return console
	return null

/proc/normalize_landing_manipulator_faction(faction)
	if(isnull(faction) || faction == "" || faction == "open")
		return null
	return faction

/proc/apply_programmable_faction_lock(obj/machinery/computer/landing_controller/console, faction)
	var/obj/machinery/computer/landing_controller/programmable/programmable = console
	if(!istype(programmable))
		return
	if(isnull(faction))
		programmable.lock_mode = null
		programmable.owner_account_id = null
		programmable.owner_name = null
		return
	programmable.lock_mode = LANDING_CONTROLLER_LOCK_FACTION
	programmable.owner_account_id = null
	programmable.owner_name = null

/proc/log_landing_manipulator(mob/user, message)
	message_admins("[key_name_admin(user)] landing zone manipulator: [message]")
	log_admin("[key_name(user)] landing zone manipulator: [message]")
	SSblackbox.record_feedback("text", "landing_zone_manipulator", 1, message)

/proc/resolve_landing_controller_spawn_type(console_type)
	switch(console_type)
		if("nanotrasen")
			return /obj/machinery/computer/landing_controller/nanotrasen
		if("programmable")
			return /obj/machinery/computer/landing_controller/programmable
	return /obj/machinery/computer/landing_controller

/proc/admin_configure_spawned_controller(obj/machinery/computer/landing_controller/console, label, faction, exit_dir)
	console.admin_force_operational = TRUE
	if(length(label))
		console.zone_label = label
	if(exit_dir && (exit_dir in GLOB.cardinals))
		console.exit_direction = exit_dir
	console.set_dock_affiliation(faction)
	apply_programmable_faction_lock(console, faction)

/proc/admin_spawn_landing_kit(mob/user, list/params)
	var/turf/spawn_turf = get_turf(user)
	if(isnull(spawn_turf))
		return FALSE
	var/console_path = resolve_landing_controller_spawn_type(params["console_type"])
	var/faction = normalize_landing_manipulator_faction(params["faction"])
	if(faction && !get_overmap_faction(faction))
		return FALSE
	var/label = trim(strip_html(params["name"], MAX_NAME_LEN))
	var/exit_dir = text2num(params["exit_direction"])
	var/obj/machinery/computer/landing_controller/console = new console_path(spawn_turf)
	admin_configure_spawned_controller(console, label, faction, exit_dir)
	for(var/i in 1 to 4)
		new /obj/machinery/landing_corner(spawn_turf)
	user.forceMove(spawn_turf)
	log_landing_manipulator(user, "spawned unlinked LZ kit ([console_path]) at ([spawn_turf.x], [spawn_turf.y], [spawn_turf.z])")
	return TRUE

/proc/admin_spawn_linked_landing_zone(mob/user, list/params)
	var/turf/origin = get_turf(user)
	if(isnull(origin))
		return FALSE
	var/width = text2num(params["width"])
	var/height = text2num(params["height"])
	var/cap = CONFIG_GET(number/max_overmap_landing_zone_dimension)
	if(!isnum(width) || !isnum(height) || width < 2 || height < 2)
		to_chat(user, span_warning("Width and height must be at least 2."))
		return FALSE
	if(width > cap || height > cap)
		to_chat(user, span_warning("Zone exceeds cap ([cap])."))
		return FALSE
	var/max_x = origin.x + width - 1
	var/max_y = origin.y + height - 1
	if(max_x > world.maxx || max_y > world.maxy)
		to_chat(user, span_warning("Zone would leave the map bounds."))
		return FALSE

	var/faction = normalize_landing_manipulator_faction(params["faction"])
	if(faction && !get_overmap_faction(faction))
		return FALSE
	var/label = trim(strip_html(params["name"], MAX_NAME_LEN))
	if(!length(label))
		label = "Admin LZ ([get_area_name(origin)])"
	var/exit_dir = text2num(params["exit_direction"])
	var/console_path = resolve_landing_controller_spawn_type(params["console_type"])

	var/turf/console_turf = get_step(origin, WEST) || origin
	var/obj/machinery/computer/landing_controller/console = new console_path(console_turf)
	admin_configure_spawned_controller(console, label, faction, exit_dir)

	var/list/corner_turfs = list(
		origin,
		locate(max_x, origin.y, origin.z),
		locate(origin.x, max_y, origin.z),
		locate(max_x, max_y, origin.z),
	)
	for(var/turf/corner_turf as anything in corner_turfs)
		if(isnull(corner_turf))
			qdel(console)
			to_chat(user, span_warning("Failed to resolve a corner turf."))
			return FALSE
		var/obj/machinery/landing_corner/corner = new(corner_turf)
		console.toggle_corner(corner)

	user.forceMove(console_turf)
	log_landing_manipulator(user, "spawned linked [width]x[height] LZ ([label], faction=[faction || "open"]) at ([origin.x], [origin.y], [origin.z])")
	return TRUE
