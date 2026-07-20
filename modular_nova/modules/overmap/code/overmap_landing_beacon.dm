// MODULE ID: OVERMAP
// Player-constructable landing zones. Four `landing_corner` light beacons are
// linked to a `landing_controller` computer with a multitool; when the four
// corners form a valid axis-aligned rectangle within the configured size cap,
// the controller drives a managed `/obj/effect/landmark/overmap_landing_zone`
// so the existing nav console can target it. See the module readme.

/obj/machinery/landing_corner
	name = "landing zone corner beacon"
	desc = "A Prism-brand approach light, repurposed to mark a corner of a landing zone. Link it to a landing zone controller with a multitool."
	icon = 'icons/obj/mining.dmi'
	icon_state = "markercerulean-on"
	density = FALSE
	anchored = TRUE
	use_power = NO_POWER_USE
	circuit = /obj/item/circuitboard/machine/landing_corner
	max_integrity = 150
	/// Weakref to the `/obj/machinery/computer/landing_controller` we are linked to.
	var/datum/weakref/controller

/obj/machinery/landing_corner/Initialize(mapload)
	. = ..()
	set_light(2, 2, LIGHT_COLOR_BLUE)
	register_context()

/obj/machinery/landing_corner/Destroy()
	var/obj/machinery/computer/landing_controller/console = controller?.resolve()
	controller = null
	. = ..()
	console?.recompute_zone()

/obj/machinery/landing_corner/Moved(atom/old_loc, movement_dir, forced, list/old_locs, momentum_change)
	. = ..()
	var/obj/machinery/computer/landing_controller/console = controller?.resolve()
	console?.recompute_zone()

/obj/machinery/landing_corner/on_deconstruction(disassembled)
	var/obj/machinery/computer/landing_controller/console = controller?.resolve()
	controller = null
	console?.recompute_zone()
	return ..()

/obj/machinery/landing_corner/vv_get_dropdown()
	. = ..()
	VV_DROPDOWN_OPTION(VV_HK_LINK_MARKED_LANDING_CONTROLLER, "Link to Marked Landing Controller")

/obj/machinery/landing_corner/vv_do_topic(list/href_list)
	. = ..()
	if(href_list[VV_HK_LINK_MARKED_LANDING_CONTROLLER])
		vv_link_marked_landing_controller()

/// Admin VV helper: toggle-link this corner to the admin's marked landing controller.
/obj/machinery/landing_corner/proc/vv_link_marked_landing_controller()
	if(!check_rights(R_VAREDIT))
		return
	var/datum/admins/holder = usr.client?.holder
	if(!holder)
		return
	var/obj/machinery/computer/landing_controller/console = holder.marked_datum
	if(!istype(console))
		to_chat(usr, span_warning("Mark a landing zone controller first (VV → Mark Object)."))
		return
	var/result = console.toggle_corner(src)
	to_chat(usr, span_notice("[src] → [console]: [result]"))
	log_admin("[key_name(usr)] VV-linked [src] to [console]: [result]")
	message_admins(span_notice("[key_name_admin(usr)] VV-linked [ADMIN_VERBOSEJMP(src)] to [ADMIN_VERBOSEJMP(console)]: [result]"))

/obj/machinery/landing_corner/multitool_act(mob/living/user, obj/item/multitool/tool)
	if(!istype(tool.buffer, /obj/machinery/computer/landing_controller))
		balloon_alert(user, "buffer empty; use console first")
		return ITEM_INTERACT_BLOCKING
	var/obj/machinery/computer/landing_controller/console = tool.buffer
	balloon_alert(user, console.toggle_corner(src))
	return ITEM_INTERACT_SUCCESS

/obj/machinery/landing_corner/screwdriver_act(mob/living/user, obj/item/tool)
	return default_deconstruction_screwdriver(user, tool)

/obj/machinery/landing_corner/crowbar_act(mob/living/user, obj/item/tool)
	return default_deconstruction_crowbar(user, tool)

/obj/machinery/landing_corner/wrench_act(mob/living/user, obj/item/tool)
	if(default_unfasten_wrench(user, tool) == SUCCESSFUL_UNFASTEN)
		var/obj/machinery/computer/landing_controller/console = controller?.resolve()
		console?.recompute_zone()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/landing_corner/examine(mob/user)
	. = ..()
	var/obj/machinery/computer/landing_controller/console = controller?.resolve()
	. += span_notice("It is [console ? "linked to a landing zone controller" : "not linked to any controller"].")
	. += span_notice("<i>Multitool</i> a landing zone controller, then multitool this beacon to link or unlink it.")
	. += span_notice("A <i>screwdriver</i> toggles the panel; with the panel open a <i>wrench</i> unanchors and a <i>crowbar</i> deconstructs it.")

/obj/machinery/landing_corner/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(isnull(held_item))
		return NONE
	switch(held_item.tool_behaviour)
		if(TOOL_MULTITOOL)
			context[SCREENTIP_CONTEXT_LMB] = "Link to buffered controller"
			return CONTEXTUAL_SCREENTIP_SET
		if(TOOL_SCREWDRIVER)
			context[SCREENTIP_CONTEXT_LMB] = "[panel_open ? "Close" : "Open"] panel"
			return CONTEXTUAL_SCREENTIP_SET
		if(TOOL_WRENCH)
			context[SCREENTIP_CONTEXT_LMB] = "[anchored ? "Unanchor" : "Anchor"]"
			return CONTEXTUAL_SCREENTIP_SET
		if(TOOL_CROWBAR)
			if(panel_open)
				context[SCREENTIP_CONTEXT_LMB] = "Deconstruct"
				return CONTEXTUAL_SCREENTIP_SET
	return NONE


/obj/machinery/computer/landing_controller
	name = "landing zone controller"
	desc = "Designates a field landing zone from four linked corner beacons. Lacks any security features, like login requirements or landing restrictions."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	circuit = /obj/item/circuitboard/computer/landing_controller
	req_access = list()
	req_one_access = list()
	/// Overmap affiliation stamped onto the managed landmark (`OVERMAP_AFFILIATION_*`).
	/// Null = open docking (any affiliation).
	var/dock_affiliation
	/// Weakrefs to the linked `/obj/machinery/landing_corner` beacons (max 4).
	var/list/corners = list()
	/// The landmark we manage while the linked corners form a valid zone.
	var/obj/effect/landmark/overmap_landing_zone/active_zone
	/// Player-facing name pushed onto the managed landmark.
	var/zone_label
	/// Cardinal launch/exit direction pushed onto the managed landmark. The bay-exit
	/// check validates the shuttle's clearance toward this edge at undock time.
	var/exit_direction = NORTH
	/// Reason the zone is not currently valid, for the UI/examine. Null when valid.
	var/invalid_reason
	/// Last computed zone dimensions, cached for the UI/examine.
	var/zone_width_cache = 0
	var/zone_height_cache = 0
	/// TRUE when the last computed rectangle exceeded the size cap.
	var/oversized = FALSE
	/// Admin manipulator: treat the console as powered for zone validation.
	var/admin_force_operational = FALSE

/obj/machinery/computer/landing_controller/nanotrasen
	name = "landing zone controller"
	desc = "Designates a Nanotrasen-authorized landing zone from four linked corner beacons. Restricted to command and engineering personnel. May be restricted to Nanotrasen vessels only."
	circuit = /obj/item/circuitboard/computer/landing_controller/nanotrasen
	req_one_access = list(ACCESS_COMMAND, ACCESS_ENGINEERING)
	dock_affiliation = OVERMAP_AFFILIATION_NT

/obj/machinery/computer/landing_controller/programmable
	name = "landing zone controller"
	desc = "Designates a landing zone from four linked corner beacons. Program the circuit board with an ID before construction (faction or user lock)."
	circuit = /obj/item/circuitboard/computer/landing_controller/programmable
	/// Copied from the board: LANDING_CONTROLLER_LOCK_* or null when unprogrammed/open.
	var/lock_mode
	/// User-mode bound bank account id.
	var/owner_account_id
	/// User-mode display name.
	var/owner_name

/obj/machinery/computer/landing_controller/Initialize(mapload)
	. = ..()
	if(isnull(zone_label))
		zone_label = "Field LZ ([get_area_name(src)])"
	register_context()

/obj/machinery/computer/landing_controller/Destroy()
	clear_corner_backrefs()
	corners.Cut()
	QDEL_NULL(active_zone)
	return ..()

/obj/machinery/computer/landing_controller/on_deconstruction(disassembled)
	clear_corner_backrefs()
	corners.Cut()
	QDEL_NULL(active_zone)
	return ..()

/// Pushes dock affiliation onto the managed landmark when present.
/obj/machinery/computer/landing_controller/proc/set_dock_affiliation(new_affiliation)
	dock_affiliation = new_affiliation
	if(!QDELETED(active_zone))
		active_zone.dock_affiliation = new_affiliation

/obj/machinery/computer/landing_controller/programmable/set_dock_affiliation(new_affiliation)
	. = ..()
	refresh_faction_appearance()

/// Monitor overlay from the locked faction datum (e.g. DS2 red screen).
/obj/machinery/computer/landing_controller/programmable/proc/refresh_faction_appearance()
	var/datum/overmap_faction/faction = get_overmap_faction(dock_affiliation)
	if(faction?.console_icon_screen)
		icon_screen = faction.console_icon_screen
	else
		icon_screen = initial(icon_screen)
	update_appearance(UPDATE_OVERLAYS)

/obj/machinery/computer/landing_controller/programmable/on_construction(mob/user)
	. = ..()
	apply_board_program()

/obj/machinery/computer/landing_controller/programmable/proc/apply_board_program()
	var/obj/item/circuitboard/computer/landing_controller/programmable/board = circuit
	req_access = list()
	req_one_access = list()
	if(!istype(board) || !board.is_programmed())
		lock_mode = null
		owner_account_id = null
		owner_name = null
		set_dock_affiliation(null)
		return
	lock_mode = board.program_mode
	if(lock_mode == LANDING_CONTROLLER_LOCK_USER)
		owner_account_id = board.stored_owner_account_id
		owner_name = board.stored_owner_name
		set_dock_affiliation(null)
		return
	owner_account_id = null
	owner_name = null
	set_dock_affiliation(board.stored_dock_affiliation)

/obj/machinery/computer/landing_controller/programmable/on_deconstruction(disassembled)
	var/obj/item/circuitboard/computer/landing_controller/programmable/board = circuit
	if(istype(board))
		if(obj_flags & EMAGGED)
			board.program_mode = LANDING_CONTROLLER_LOCK_FACTION
			board.stored_dock_affiliation = OVERMAP_AFFILIATION_DS2
			board.stored_owner_account_id = null
			board.stored_owner_name = null
		else if(lock_mode == LANDING_CONTROLLER_LOCK_USER)
			board.program_mode = LANDING_CONTROLLER_LOCK_USER
			board.stored_owner_account_id = owner_account_id
			board.stored_owner_name = owner_name
			board.stored_dock_affiliation = null
		else if(lock_mode == LANDING_CONTROLLER_LOCK_FACTION)
			board.program_mode = LANDING_CONTROLLER_LOCK_FACTION
			board.stored_dock_affiliation = dock_affiliation
			board.stored_owner_account_id = null
			board.stored_owner_name = null
		else
			board.clear_program()
	return ..()

/// Faction/user locks live on the circuit board — not the built console.
/obj/machinery/computer/landing_controller/programmable/allowed(mob/accessor)
	if((obj_flags & EMAGGED) || isAdminGhostAI(accessor))
		return TRUE
	if(isnull(accessor))
		return FALSE
	if(HAS_SILICON_ACCESS(accessor))
		return TRUE
	if(isnull(lock_mode))
		return TRUE
	if(!isliving(accessor))
		return FALSE
	var/mob/living/living_accessor = accessor
	var/obj/item/card/id/id_card = living_accessor.get_idcard(TRUE)
	if(isnull(id_card))
		return FALSE
	if(lock_mode == LANDING_CONTROLLER_LOCK_USER)
		if(!isnull(owner_account_id) && id_card.registered_account?.account_id == owner_account_id)
			return TRUE
		if(length(owner_name) && id_card.registered_name == owner_name)
			return TRUE
		return FALSE
	if(lock_mode == LANDING_CONTROLLER_LOCK_FACTION)
		return get_id_overmap_faction(id_card) == dock_affiliation
	return TRUE

/// Emag opens console login and locks the pad to syndicate-aligned vessels.
/obj/machinery/computer/landing_controller/programmable/emag_act(mob/user, obj/item/card/emag/emag_card)
	if(obj_flags & EMAGGED)
		return FALSE
	obj_flags |= EMAGGED
	lock_mode = null
	owner_account_id = null
	owner_name = null
	authenticated = FALSE
	set_dock_affiliation(OVERMAP_AFFILIATION_DS2)
	balloon_alert(user, "pad syndie-locked")
	return TRUE

/// Emag clears console access and opens the pad so syndicate (and any) vessels may land.
/obj/machinery/computer/landing_controller/nanotrasen/emag_act(mob/user, obj/item/card/emag/emag_card)
	if(obj_flags & EMAGGED)
		return FALSE
	obj_flags |= EMAGGED
	req_access = list()
	req_one_access = list()
	authenticated = FALSE
	set_dock_affiliation(null)
	balloon_alert(user, "landing restrictions burned out")
	return TRUE

/obj/machinery/computer/landing_controller/power_change()
	. = ..()
	recompute_zone()

/obj/machinery/computer/landing_controller/multitool_act(mob/living/user, obj/item/multitool/tool)
	tool.buffer = src
	balloon_alert(user, "saved to buffer")
	return ITEM_INTERACT_SUCCESS

/// Clears the back-reference on every linked corner (used on teardown/clear).
/obj/machinery/computer/landing_controller/proc/clear_corner_backrefs()
	for(var/datum/weakref/corner_ref as anything in corners)
		var/obj/machinery/landing_corner/corner = corner_ref.resolve()
		if(corner)
			corner.controller = null

/// Adds or removes a corner from the linked set, updating its back-ref, then
/// recomputes. Returns a short balloon-alert string for player feedback.
/obj/machinery/computer/landing_controller/proc/toggle_corner(obj/machinery/landing_corner/corner)
	for(var/datum/weakref/corner_ref as anything in corners)
		if(corner_ref.resolve() == corner)
			corners -= corner_ref
			corner.controller = null
			recompute_zone()
			return "unlinked ([length(corners)]/4)"
	if(length(corners) >= 4)
		return "already linked 4 corners"
	corners += WEAKREF(corner)
	corner.controller = WEAKREF(src)
	recompute_zone()
	return "linked ([length(corners)]/4)"

/// Validates the linked corners and (re)positions or drops the managed
/// landmark. Caches dimensions + the failure reason for the UI/examine.
/obj/machinery/computer/landing_controller/proc/recompute_zone()
	// Prune dead corners and clear stale back-refs.
	var/list/live = list()
	for(var/datum/weakref/corner_ref as anything in corners)
		var/obj/machinery/landing_corner/corner = corner_ref.resolve()
		if(QDELETED(corner))
			continue
		live += corner_ref
	corners = live

	zone_width_cache = 0
	zone_height_cache = 0
	oversized = FALSE
	invalid_reason = null

	if(!is_operational && !admin_force_operational)
		invalid_reason = "no power"
	else if(length(corners) != 4)
		invalid_reason = "need 4 corners (have [length(corners)])"
	else
		var/list/xs = list()
		var/list/ys = list()
		var/list/zs = list()
		var/list/positions = list()
		var/missing_turf = FALSE
		for(var/datum/weakref/corner_ref as anything in corners)
			var/obj/machinery/landing_corner/corner = corner_ref.resolve()
			var/turf/corner_turf = get_turf(corner)
			if(isnull(corner_turf))
				missing_turf = TRUE
				break
			xs |= corner_turf.x
			ys |= corner_turf.y
			zs |= corner_turf.z
			positions |= "[corner_turf.x]-[corner_turf.y]"

		if(missing_turf)
			invalid_reason = "a corner is not on a tile"
		else if(length(zs) != 1)
			invalid_reason = "corners span multiple Z"
		else if(length(xs) != 2 || length(ys) != 2 || length(positions) != 4)
			invalid_reason = "corners are not a rectangle"
		else
			var/min_x = min(xs[1], xs[2])
			var/min_y = min(ys[1], ys[2])
			var/width = abs(xs[1] - xs[2]) + 1
			var/height = abs(ys[1] - ys[2]) + 1
			var/cap = CONFIG_GET(number/max_overmap_landing_zone_dimension)
			zone_width_cache = width
			zone_height_cache = height
			if(width > cap || height > cap)
				oversized = TRUE
				invalid_reason = "zone too large ([width]x[height] > [cap])"
			else
				apply_zone(min_x, min_y, zs[1], width, height)
				return

	// Reaching here means the zone is invalid - drop any managed landmark.
	if(active_zone)
		QDEL_NULL(active_zone)

/// Creates or repositions the managed landmark for a validated rectangle.
/obj/machinery/computer/landing_controller/proc/apply_zone(min_x, min_y, zone_z, width, height)
	var/turf/origin = locate(min_x, min_y, zone_z)
	if(isnull(origin))
		invalid_reason = "invalid zone origin"
		if(active_zone)
			QDEL_NULL(active_zone)
		return
	if(QDELETED(active_zone))
		active_zone = new(origin)
	else
		active_zone.forceMove(origin)
	active_zone.zone_width = width
	active_zone.zone_height = height
	active_zone.zone_name = zone_label
	active_zone.exit_direction = exit_direction
	active_zone.dock_affiliation = dock_affiliation

/// Returns the name of the shuttle currently occupying the active zone, if any.
/obj/machinery/computer/landing_controller/proc/get_zone_occupant()
	if(QDELETED(active_zone))
		return null
	var/obj/docking_port/mobile/occupant = active_zone.get_occupant()
	return occupant?.name

/// Human-readable dock policy for UI/examine.
/obj/machinery/computer/landing_controller/proc/get_dock_policy_label()
	var/datum/overmap_faction/faction = get_overmap_faction(dock_affiliation)
	if(faction)
		return "[faction.name] vessels"
	return "Open (any vessel)"

/// Console access summary for examine when locked/restricted/compromised.
/obj/machinery/computer/landing_controller/proc/get_access_status_label()
	if(obj_flags & EMAGGED)
		return "Compromised"
	if(length(req_access))
		return "ID locked"
	if(length(req_one_access))
		return "Restricted (command / engineering)"
	return null

/obj/machinery/computer/landing_controller/programmable/get_access_status_label()
	if(obj_flags & EMAGGED)
		return "Compromised"
	if(lock_mode == LANDING_CONTROLLER_LOCK_USER)
		return "User locked ([owner_name || "bound account"])"
	if(lock_mode == LANDING_CONTROLLER_LOCK_FACTION)
		var/datum/overmap_faction/faction = get_overmap_faction(dock_affiliation)
		if(faction)
			return "Faction locked ([faction.name])"
	return null

/obj/machinery/computer/landing_controller/examine(mob/user)
	. = ..()
	. += span_notice("Linked corners: [length(corners)]/4.")
	. += span_notice("Designated launch exit: [dir2text(exit_direction)].")
	. += span_notice("Docking policy: [get_dock_policy_label()].")
	var/access_status = get_access_status_label()
	if(access_status)
		. += span_notice("Console access: [access_status].")
	if(!QDELETED(active_zone))
		. += span_notice("Active landing zone: [zone_width_cache] x [zone_height_cache] tiles.")
	else if(invalid_reason)
		. += span_notice("Zone inactive: [invalid_reason].")
	. += span_notice("<i>Multitool</i> this console, then multitool corner beacons to link them.")

/obj/machinery/computer/landing_controller/programmable/examine(mob/user)
	. = ..()
	if(obj_flags & EMAGGED)
		. += span_warning("The ID reader is fried; the pad is locked to syndicate-aligned vessels.")
	else
		. += span_notice("Program locks on the circuit board (remove with screwdriver), not by swiping this console.")

/obj/machinery/computer/landing_controller/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	. = ..()
	if(isnull(held_item))
		return .
	if(held_item.tool_behaviour == TOOL_MULTITOOL)
		context[SCREENTIP_CONTEXT_LMB] = "Save to buffer"
		return CONTEXTUAL_SCREENTIP_SET
	return .

/// Secure login mirroring the records consoles: checks reach + access.
/obj/machinery/computer/landing_controller/proc/secure_login(mob/user)
	if(!user.can_perform_action(src, ALLOW_SILICON_REACH) || !is_operational)
		return FALSE
	if(!allowed(user))
		balloon_alert(user, "access denied")
		playsound(src, 'sound/machines/terminal/terminal_error.ogg', 70, TRUE)
		return FALSE
	balloon_alert(user, "logged in")
	playsound(src, 'sound/machines/terminal/terminal_on.ogg', 70, TRUE)
	return TRUE

/obj/machinery/computer/landing_controller/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "OvermapLandingController")
		ui.open()

/obj/machinery/computer/landing_controller/ui_data(mob/user)
	var/list/data = list()
	var/has_access = (authenticated && isliving(user)) || isAdminGhostAI(user)
	data["authenticated"] = has_access
	if(!has_access)
		return data

	data["zone_label"] = zone_label
	data["exit_direction"] = exit_direction
	data["exit_direction_name"] = dir2text(exit_direction)
	data["cap"] = CONFIG_GET(number/max_overmap_landing_zone_dimension)
	data["active"] = !QDELETED(active_zone)
	data["invalid_reason"] = invalid_reason
	data["width"] = zone_width_cache
	data["height"] = zone_height_cache
	data["has_dimensions"] = (zone_width_cache > 0 && zone_height_cache > 0)
	data["oversized"] = oversized
	data["dock_policy"] = get_dock_policy_label()

	var/occupant_name = get_zone_occupant()
	data["occupied"] = !isnull(occupant_name)
	data["occupant_name"] = occupant_name

	var/list/corner_data = list()
	var/active_z = !QDELETED(active_zone) ? active_zone.z : null
	for(var/datum/weakref/corner_ref as anything in corners)
		var/obj/machinery/landing_corner/corner = corner_ref.resolve()
		if(QDELETED(corner))
			continue
		var/turf/corner_turf = get_turf(corner)
		corner_data += list(list(
			"x" = corner_turf?.x,
			"y" = corner_turf?.y,
			"z" = corner_turf?.z,
			"resolved" = TRUE,
			"on_z" = isnull(active_z) ? TRUE : (corner_turf?.z == active_z),
		))
	data["corners"] = corner_data
	return data

/obj/machinery/computer/landing_controller/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/user = ui.user
	var/admin_ghost = isAdminGhostAI(user)

	switch(action)
		if("login")
			if(admin_ghost)
				authenticated = TRUE
				return TRUE
			authenticated = secure_login(user)
			return TRUE
		if("logout")
			authenticated = FALSE
			balloon_alert(user, "logged out")
			playsound(src, 'sound/machines/terminal/terminal_off.ogg', 70, TRUE)
			return TRUE

	// Mirror ui_data: admin ghosts can act without a living login session.
	if(!((authenticated && isliving(user)) || admin_ghost))
		return FALSE

	switch(action)
		if("set_name")
			var/new_label = trim(strip_html(params["name"], MAX_NAME_LEN))
			if(!length(new_label))
				return FALSE
			zone_label = new_label
			if(!QDELETED(active_zone))
				active_zone.zone_name = zone_label
			return TRUE
		if("set_exit_dir")
			var/new_dir = text2num(params["dir"])
			if(!(new_dir in GLOB.cardinals))
				return FALSE
			exit_direction = new_dir
			if(!QDELETED(active_zone))
				active_zone.exit_direction = exit_direction
			return TRUE
		if("validate")
			recompute_zone()
			return TRUE
		if("clear_corners")
			clear_corner_backrefs()
			corners.Cut()
			recompute_zone()
			return TRUE

	return FALSE
