// MODULE ID: OVERMAP
// The counter a player files a ship at and retrieves it from.
//
// The only thing in the module that touches both halves: the registry knows who
// owns what, the teardown and retrieval paths know how to put a hull on and off
// the disk, and this bridges them. Ownership is per-ckey rather than per-character,
// so the ckey is captured at login alongside the ID record the rest of the console
// conventions expect.

/obj/machinery/computer/ship_registrar
	name = "ship registrar"
	desc = "A vessel registry terminal. Files a docked ship into long-term storage against its owner's account, and calls it back to the pad later."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	circuit = /obj/item/circuitboard/computer/ship_registrar
	req_access = list()
	req_one_access = list()
	// `authenticated` is the parent's, and means the same thing here.
	/// ID record captured at login, for the operator name on screen.
	var/alist/operator_id_data
	/// Account the session files and retrieves against. Ships are owned by ckey.
	var/operator_ckey
	/// Landing controller supplying the pad this console works over.
	var/datum/weakref/linked_controller
	/// Report from the last survey, and the hull it described.
	var/list/survey_report
	var/datum/weakref/surveyed_hull
	/// Owner's ship list, refreshed on login and after anything that changes it.
	/// Held rather than queried per `ui_data`, which runs on every UI tick.
	var/list/datum/player_ship_record/known_ships
	/// Last thing the console has to say about a refused action.
	var/status_message

/obj/machinery/computer/ship_registrar/Initialize(mapload)
	. = ..()
	register_context()

/obj/machinery/computer/ship_registrar/multitool_act(mob/living/user, obj/item/multitool/tool)
	if(istype(tool.buffer, /obj/machinery/computer/landing_controller))
		var/obj/machinery/computer/landing_controller/controller = tool.buffer
		if(controller.z != z)
			balloon_alert(user, "controller off-Z")
			return ITEM_INTERACT_BLOCKING
		linked_controller = WEAKREF(controller)
		balloon_alert(user, "landing zone linked")
		return ITEM_INTERACT_SUCCESS
	return ..()

/obj/machinery/computer/ship_registrar/examine(mob/user)
	. = ..()
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	. += span_notice("Landing zone: [controller ? controller.zone_label : "unlinked"].")

/obj/machinery/computer/ship_registrar/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(ui)
		return
	ui = new(user, src, "ShipRegistrar", name)
	ui.open()

/// Secure login mirroring the fabricator: checks reach, power and access.
/obj/machinery/computer/ship_registrar/proc/secure_login(mob/user)
	if(!user.can_perform_action(src, ALLOW_SILICON_REACH) || !is_operational)
		return FALSE
	if(!allowed(user))
		balloon_alert(user, "access denied")
		playsound(src, 'sound/machines/terminal/terminal_error.ogg', 70, TRUE)
		return FALSE
	balloon_alert(user, "logged in")
	playsound(src, 'sound/machines/terminal/terminal_on.ogg', 70, TRUE)
	return TRUE

/// The pad this console works over, or null when nothing is linked.
/obj/machinery/computer/ship_registrar/proc/active_zone()
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	if(QDELETED(controller?.active_zone))
		return null
	return controller.active_zone

/// The hull standing on the pad, which is the one filing acts on.
/obj/machinery/computer/ship_registrar/proc/docked_hull()
	var/obj/effect/landmark/overmap_landing_zone/zone = active_zone()
	return zone?.get_occupant()

/obj/machinery/computer/ship_registrar/proc/refresh_ship_list()
	known_ships = shipyard_registry_list(operator_ckey)

/obj/machinery/computer/ship_registrar/ui_data(mob/user)
	var/list/data = list()
	var/has_session = (authenticated && isliving(user)) || isAdminGhostAI(user)
	data["authenticated"] = has_session
	data["operatorName"] = operator_id_data?["name"]
	if(!has_session)
		return data

	var/obj/effect/landmark/overmap_landing_zone/zone = active_zone()
	var/obj/docking_port/mobile/hull = zone?.get_occupant()
	data["operatorCkey"] = operator_ckey
	data["registryOnline"] = SSdbcore.IsConnected()
	data["statusMessage"] = status_message
	data["zoneLinked"] = !!linked_controller?.resolve()
	data["zoneActive"] = !!zone
	data["zoneName"] = zone?.zone_name
	data["zoneWidth"] = zone?.zone_width || 0
	data["zoneHeight"] = zone?.zone_height || 0
	data["hullName"] = hull?.name
	data["hullFilable"] = hull ? !shipyard_file_refusal(hull, zone) : FALSE
	data["hullRefusal"] = hull ? shipyard_file_refusal(hull, zone) : null
	data["surveyReport"] = survey_report
	data["surveyMatchesHull"] = hull && surveyed_hull?.resolve() == hull

	var/list/ships = list()
	for(var/datum/player_ship_record/record as anything in known_ships)
		ships += list(list(
			"id" = record.id,
			"name" = record.ship_name,
			"tiles" = record.tile_count,
			"stored" = length(record.stored_contents),
			"status" = record.status_label(),
			"retrievable" = record.is_retrievable(),
		))
	data["ships"] = ships
	return data

/obj/machinery/computer/ship_registrar/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/ui_state)
	. = ..()
	if(.)
		return
	var/mob/living/user = usr
	var/admin_ghost = isAdminGhostAI(user)

	switch(action)
		if("login")
			if(admin_ghost)
				authenticated = TRUE
				operator_ckey = user.ckey
				refresh_ship_list()
				return TRUE
			authenticated = secure_login(user)
			if(authenticated)
				operator_id_data = ID_DATA(user)
				operator_ckey = user.ckey
				status_message = null
				refresh_ship_list()
			return TRUE
		if("logout")
			authenticated = FALSE
			operator_id_data = null
			operator_ckey = null
			known_ships = null
			survey_report = null
			surveyed_hull = null
			status_message = null
			balloon_alert(user, "logged out")
			playsound(src, 'sound/machines/terminal/terminal_off.ogg', 70, TRUE)
			return TRUE

	// Mirror ui_data: admin ghosts can act without a living login session.
	if(!((authenticated && isliving(user)) || admin_ghost))
		return FALSE

	switch(action)
		if("refresh")
			refresh_ship_list()
			return TRUE
		if("survey")
			return run_survey()
		if("file")
			return file_docked_hull(user)
		if("retrieve")
			return retrieve_ship(user, params["id"])

/**
 * Describe the docked hull without touching it.
 *
 * A real dry run rather than a summary: it builds the same `/datum/ship_teardown`
 * filing will, so the report names every object that has no construction route
 * and will therefore not come back. Filing is gated behind this having run for
 * this hull, so nobody loses a ship's worth of loose cargo to a single click.
 */
/obj/machinery/computer/ship_registrar/proc/run_survey()
	var/obj/docking_port/mobile/hull = docked_hull()
	survey_report = null
	surveyed_hull = null
	if(!hull)
		status_message = "No vessel is standing on the pad."
		return TRUE
	var/datum/ship_teardown/teardown = new(hull)
	survey_report = teardown.report()
	var/refusal = teardown.refusal || shipyard_file_refusal(hull, active_zone())
	if(refusal)
		status_message = "This vessel cannot be filed: [refusal]."
	else
		surveyed_hull = WEAKREF(hull)
		status_message = null
	qdel(teardown)
	playsound(src, 'sound/machines/terminal/terminal_processing.ogg', 40, TRUE)
	return TRUE

/**
 * Serialize the docked hull, record where it went, and take it out of the world.
 *
 * Ordering is what matters here. The row is claimed first because the file path
 * is derived from its id; the ship is only released once the write has landed; the
 * row is only pointed at the file once the ship is gone. A failure at any step
 * leaves either a soft-deleted row and an untouched ship, or a ship on disk that
 * the player can be handed back - never a row promising a file that is not there.
 */
/obj/machinery/computer/ship_registrar/proc/file_docked_hull(mob/living/user)
	var/obj/effect/landmark/overmap_landing_zone/zone = active_zone()
	var/obj/docking_port/mobile/hull = zone?.get_occupant()
	if(!hull)
		status_message = "No vessel is standing on the pad."
		return TRUE
	if(surveyed_hull?.resolve() != hull)
		status_message = "Survey this vessel before filing it."
		return TRUE
	if(!shipyard_registry_online())
		status_message = "The registry is offline. Filing is unavailable."
		return TRUE
	var/datum/ship_teardown/teardown = new(hull)
	var/refusal = teardown.refusal || shipyard_file_refusal(hull, zone)
	if(refusal)
		status_message = "This vessel cannot be filed: [refusal]."
		qdel(teardown)
		return TRUE

	var/hull_name = teardown.name
	var/tile_count = length(teardown.cells)
	// A ship that was retrieved from a row goes back into that row. Without this
	// every trip through the registrar would leave another record behind, each
	// pointing at a file the next one overwrote.
	var/existing_id = hull.ship_registry_id
	var/record_id = existing_id || shipyard_registry_insert(operator_ckey, hull_name, tile_count)
	if(!record_id)
		status_message = "The registry would not accept a new record."
		qdel(teardown)
		return TRUE

	var/file_path = shipyard_ship_file_path(operator_ckey, record_id)
	var/list/stored_contents = teardown.stored_contents.Copy()
	var/written = shipyard_write_and_release(hull, teardown, file_path)
	qdel(teardown)
	if(!written)
		if(!existing_id)
			shipyard_registry_discard(record_id)
		status_message = "The vessel could not be written to storage. It has been left on the pad."
		return TRUE
	shipyard_registry_store(record_id, file_path, stored_contents, tile_count, hull_name)
	survey_report = null
	surveyed_hull = null
	status_message = "[hull_name] filed. [length(stored_contents)] item(s) held in its lockbox."
	log_game("[key_name(user)] filed the ship [hull_name] to [file_path] as player_ships record [record_id].")
	refresh_ship_list()
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return TRUE

/**
 * Call a filed ship back onto the pad.
 *
 * The row is flipped to checked-out only once a registered port exists, so a
 * refusal leaves the record filed and the file untouched and the player simply
 * tries again somewhere the hull fits.
 */
/obj/machinery/computer/ship_registrar/proc/retrieve_ship(mob/living/user, record_id)
	var/obj/effect/landmark/overmap_landing_zone/zone = active_zone()
	if(!zone)
		status_message = "Link a controller with an active landing zone."
		return TRUE
	if(zone.get_occupant())
		status_message = "The pad is occupied."
		return TRUE
	if(!shipyard_registry_online())
		status_message = "The registry is offline. Retrieval is unavailable."
		return TRUE
	var/datum/player_ship_record/record = shipyard_registry_get(record_id, operator_ckey)
	if(!record)
		status_message = "No such vessel is registered to this account."
		return TRUE
	if(!record.is_retrievable())
		status_message = "[record.ship_name] is already in service."
		return TRUE

	var/obj/docking_port/mobile/retrieved = shipyard_retrieve_hull(
		record.map_path,
		record.ship_name,
		zone,
		record.stored_contents,
	)
	if(!retrieved)
		status_message = "[record.ship_name] could not be brought in. It may not fit this pad, or the pad may be obstructed."
		return TRUE
	retrieved.ship_registry_id = record.id
	shipyard_registry_checkout(record.id)
	status_message = "[record.ship_name] is on the pad."
	log_game("[key_name(user)] retrieved the ship [record.ship_name] (player_ships record [record.id]) onto [zone.zone_name].")
	refresh_ship_list()
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return TRUE
