// MODULE ID: OVERMAP
// The counter a player files a ship at and retrieves it from.
//
// The only thing in the module that touches the registry, the ledger and the
// disk together. Teardown and retrieval know how to put a hull on and off the
// disk, the registry knows who owns what, pricing knows what it costs; this
// orders them. Ships belong to a character, by the UUID on their mind, rather
// than to the player's ckey.

/// How long an action holds the console. Loading a map sleeps, and a second
/// click landing mid-load would otherwise run the whole action again.
#define SHIP_REGISTRAR_BUSY_TIMEOUT (30 SECONDS)

/obj/machinery/computer/ship_registrar
	name = "ship registrar"
	desc = "A vessel registry terminal. Files a landed personal ship into long-term storage against its owner's ledger, and calls it back to the pad later."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	circuit = /obj/item/circuitboard/computer/ship_registrar
	req_access = list()
	req_one_access = list()
	// `authenticated` is the parent's, and means the same thing here.
	/// ID record captured at login, for the operator name on screen.
	var/alist/operator_id_data
	/// Character the session files and retrieves for.
	var/operator_uuid
	var/operator_ckey
	var/character_name
	/// Landing controller supplying the pad this console works over.
	var/datum/weakref/linked_controller
	/// Survey data for the last surveyed hull, in the shape the UI reads.
	var/list/survey
	var/datum/weakref/surveyed_hull
	/// Owner's ship list and balance, refreshed on login and after anything that
	/// changes them. Held rather than queried per `ui_data`, which runs every tick.
	var/list/datum/player_ship_record/known_ships
	var/ledger_balance
	var/registry_online = FALSE
	var/ledger_online = FALSE
	/// The occupant's refusal, rechecked at most once a second: it walks every
	/// tile of the hull, which is too much to do on every UI tick.
	var/list/cached_refusal
	var/datum/weakref/refusal_hull
	COOLDOWN_DECLARE(refusal_recheck)
	/// list("kind" = "good" or "bad", "text" = ...), or null.
	var/list/status_message
	/// world.time until which a file or retrieve is still running.
	var/busy_until = 0

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

/// Open a session for `user`'s character.
/obj/machinery/computer/ship_registrar/proc/start_session(mob/user)
	authenticated = TRUE
	operator_id_data = ID_DATA(user)
	operator_uuid = user.mind?.character_uuid
	operator_ckey = user.ckey
	character_name = user.real_name
	status_message = null
	if(!operator_uuid)
		set_status(FALSE, "No persistent identity is on record for [user.real_name]. Filing and retrieval are unavailable.")
	refresh_session()

/obj/machinery/computer/ship_registrar/proc/end_session()
	authenticated = FALSE
	operator_id_data = null
	operator_uuid = null
	operator_ckey = null
	character_name = null
	known_ships = null
	ledger_balance = null
	survey = null
	surveyed_hull = null
	status_message = null

/// Re-read everything `ui_data` shows from the registry and the ledger.
/obj/machinery/computer/ship_registrar/proc/refresh_session()
	registry_online = GLOB.ship_registry.is_online()
	ledger_online = SScharacter_ledger.is_available()
	known_ships = registry_online ? GLOB.ship_registry.list_for_owner(operator_uuid) : list()
	ledger_balance = (ledger_online && operator_uuid) ? SScharacter_ledger.get_balance(operator_uuid) : null
	COOLDOWN_RESET(src, refusal_recheck)

/obj/machinery/computer/ship_registrar/proc/set_status(good, text)
	status_message = list("kind" = good ? "good" : "bad", "text" = text)

/// The pad this console works over, or null when nothing is linked.
/obj/machinery/computer/ship_registrar/proc/active_zone()
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	if(QDELETED(controller?.active_zone))
		return null
	return controller.active_zone

/// Why the hull on the pad cannot be filed by this operator, recomputed at most
/// once a second.
/obj/machinery/computer/ship_registrar/proc/occupant_refusal(obj/docking_port/mobile/hull, obj/effect/landmark/overmap_landing_zone/zone)
	if(!hull)
		return null
	if(refusal_hull?.resolve() != hull || COOLDOWN_FINISHED(src, refusal_recheck))
		refusal_hull = WEAKREF(hull)
		cached_refusal = shipyard_file_refusal(hull, zone, operator_uuid)
		COOLDOWN_START(src, refusal_recheck, 1 SECONDS)
	return cached_refusal

/obj/machinery/computer/ship_registrar/proc/has_session(mob/user)
	return (authenticated && isliving(user)) || isAdminGhostAI(user)

/obj/machinery/computer/ship_registrar/ui_data(mob/user)
	var/list/data = list()
	var/session = has_session(user)
	data["authenticated"] = session
	data["operatorName"] = operator_id_data?["name"]
	data["characterName"] = character_name
	data["registryOnline"] = registry_online
	data["ledgerOnline"] = ledger_online
	if(!session)
		return data

	data["ledgerBalance"] = ledger_balance
	var/obj/effect/landmark/overmap_landing_zone/zone = active_zone()
	var/obj/docking_port/mobile/hull = zone?.get_occupant()
	var/list/occupant
	if(hull)
		occupant = list(
			"name" = hull.name,
			"ownership" = hull.ship_ownership,
			"ownedByOperator" = !!(operator_uuid && hull.ship_owner_id == operator_uuid),
			"registryId" = hull.ship_registry_id,
		)
	data["zone"] = list(
		"linked" = !!zone,
		"name" = zone?.zone_name,
		"width" = zone?.zone_width || 0,
		"height" = zone?.zone_height || 0,
		"occupant" = occupant,
	)
	var/list/refusal = occupant_refusal(hull, zone)
	var/blocks_survey = refusal && shipyard_refusal_blocks_survey(refusal["code"])
	data["refusal"] = refusal ? list(
		"code" = refusal["code"],
		"text" = refusal["text"],
		"blocksSurvey" = blocks_survey,
	) : null
	data["survey"] = (hull && !blocks_survey && surveyed_hull?.resolve() == hull) ? survey : null

	var/list/ships = list()
	for(var/datum/player_ship_record/record as anything in known_ships)
		ships += list(list(
			"id" = record.id,
			"name" = record.ship_name,
			"revision" = record.revision,
			"tiles" = record.tile_count,
			"lockboxCount" = length(record.stored_contents),
			"salvageEstimate" = record.salvage_estimate,
			"status" = record.status,
			"insured" = record.insured,
			"retrievedThisRound" = record.retrieved_this_round(),
			"revertedFromLoss" = record.reverted_from_loss(),
			"quote" = shipyard_retrieval_quote(record),
		))
	data["ships"] = ships
	data["statusMessage"] = status_message
	return data

/obj/machinery/computer/ship_registrar/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/ui_state)
	. = ..()
	if(.)
		return
	var/mob/living/user = usr

	switch(action)
		if("login")
			if(isAdminGhostAI(user) || secure_login(user))
				start_session(user)
			return TRUE
		if("logout")
			end_session()
			balloon_alert(user, "logged out")
			playsound(src, 'sound/machines/terminal/terminal_off.ogg', 70, TRUE)
			return TRUE

	// Mirror ui_data: admin ghosts can act without a living login session.
	if(!has_session(user))
		return FALSE

	switch(action)
		if("refresh")
			refresh_session()
			return TRUE
		if("survey")
			status_message = null
			run_survey(docked_hull(), active_zone())
			return TRUE
		if("file")
			status_message = null
			file_hull(docked_hull(), active_zone(), user)
			refresh_session()
			return TRUE
		if("retrieve")
			status_message = null
			retrieve_record(params["id"], !!text2num("[params["insured"]]"), active_zone(), user)
			refresh_session()
			return TRUE

/// The hull standing on the pad, which is the one filing acts on.
/obj/machinery/computer/ship_registrar/proc/docked_hull()
	var/obj/effect/landmark/overmap_landing_zone/zone = active_zone()
	return zone?.get_occupant()

/// What the checkout this hull came out on paid for insurance, which filing it
/// again hands back.
/obj/machinery/computer/ship_registrar/proc/pending_insurance_refund(datum/player_ship_record/record)
	if(!record || record.status != SHIP_STATUS_CHECKED_OUT || !record.insured)
		return 0
	return record.insurance_fee_paid

/**
 * Describe the docked hull without touching it.
 *
 * A real dry run rather than a summary: it builds the same `/datum/ship_teardown`
 * filing will, so the report names every object that will not come back. Filing
 * is gated behind this having run for this hull, so nobody loses a ship's worth
 * of loose cargo to a single click.
 */
/obj/machinery/computer/ship_registrar/proc/run_survey(obj/docking_port/mobile/hull, obj/effect/landmark/overmap_landing_zone/zone)
	survey = null
	surveyed_hull = null
	if(!hull)
		set_status(FALSE, "No vessel is standing on the pad.")
		return FALSE
	var/list/refusal = shipyard_file_refusal(hull, zone, operator_uuid)
	if(refusal && shipyard_refusal_blocks_survey(refusal["code"]))
		set_status(FALSE, refusal["text"])
		return FALSE
	var/datum/ship_teardown/teardown = new(hull)
	if(teardown.refusal)
		set_status(FALSE, "This vessel cannot be filed: [teardown.refusal].")
		qdel(teardown)
		return FALSE
	var/datum/player_ship_record/record = hull.ship_registry_id ? GLOB.ship_registry.get_record(hull.ship_registry_id, operator_uuid) : null
	survey = build_survey(teardown, pending_insurance_refund(record))
	surveyed_hull = WEAKREF(hull)
	qdel(teardown)
	playsound(src, 'sound/machines/terminal/terminal_processing.ogg', 40, TRUE)
	return TRUE

/// The survey as the UI reads it: what is kept, what is lost, and the quote.
/obj/machinery/computer/ship_registrar/proc/build_survey(datum/ship_teardown/teardown, insurance_refund)
	var/list/appraisal = shipyard_appraise_lockbox(teardown.lockbox_items)
	var/tile_count = length(teardown.cells)
	var/list/footprint_tiles = list()
	for(var/tile_y in teardown.height to 1 step -1)
		for(var/tile_x in 1 to teardown.width)
			var/list/fate = teardown.tile_fates["[tile_x],[tile_y]"]
			footprint_tiles += list(fate ? list("fate" = fate["fate"], "objects" = fate["objects"]) : null)
	return list(
		"tiles" = tile_count,
		"kept" = list("Hull and floors: [tile_count] tiles") + shipyard_count_lines(teardown.kept_names),
		"lost" = shipyard_count_lines(teardown.lost_names),
		"unrouted" = shipyard_count_lines(teardown.unrouted_names),
		"lostDecals" = teardown.lost_decals,
		"lockbox" = appraisal["lines"],
		"footprint" = list(
			"width" = teardown.width,
			"height" = teardown.height,
			"tiles" = footprint_tiles,
		),
		"quote" = shipyard_storage_quote(tile_count, appraisal["total"], insurance_refund),
	)

/// "name" or "name xN" for each entry of a name-to-count tally.
/proc/shipyard_count_lines(list/names)
	var/list/lines = list()
	for(var/name in names)
		var/count = names[name]
		lines += count > 1 ? "[name] x[count]" : name
	return lines

/**
 * Serialize a hull, charge for it, record where it went, and take it out of the
 * world.
 *
 * The row is claimed first because the file path is derived from its id; the
 * storage fee is charged before anything is written; the ship is only released
 * once the write has landed; the row is only pointed at the file once the ship
 * is gone. A failure before the release refunds the fee and leaves the ship on
 * the pad. Returns TRUE when the hull was filed.
 */
/obj/machinery/computer/ship_registrar/proc/file_hull(obj/docking_port/mobile/hull, obj/effect/landmark/overmap_landing_zone/zone, mob/user)
	if(world.time < busy_until)
		set_status(FALSE, "The registrar is still working on the last request.")
		return FALSE
	busy_until = world.time + SHIP_REGISTRAR_BUSY_TIMEOUT
	. = do_file_hull(hull, zone, user)
	busy_until = 0

/obj/machinery/computer/ship_registrar/proc/do_file_hull(obj/docking_port/mobile/hull, obj/effect/landmark/overmap_landing_zone/zone, mob/user)
	PRIVATE_PROC(TRUE)
	if(!hull)
		set_status(FALSE, "No vessel is standing on the pad.")
		return FALSE
	if(surveyed_hull?.resolve() != hull)
		set_status(FALSE, "Survey this vessel before filing it.")
		return FALSE
	if(!operator_uuid)
		set_status(FALSE, "No persistent identity is on record for this operator.")
		return FALSE
	if(!GLOB.ship_registry.is_online())
		set_status(FALSE, "The hangar registry is offline. Filing is unavailable.")
		return FALSE
	if(!SScharacter_ledger.is_available())
		set_status(FALSE, "The ledger is offline. Fees cannot be charged.")
		return FALSE
	var/list/refusal = shipyard_file_refusal(hull, zone, operator_uuid)
	if(refusal)
		set_status(FALSE, refusal["text"])
		return FALSE
	var/datum/ship_teardown/teardown = new(hull)
	if(teardown.refusal)
		set_status(FALSE, "This vessel cannot be filed: [teardown.refusal].")
		qdel(teardown)
		return FALSE

	var/hull_name = teardown.name
	var/tile_count = length(teardown.cells)
	// A ship that was retrieved from a row goes back into that row as its next
	// revision. Without this every trip through the registrar would leave
	// another record behind.
	var/datum/player_ship_record/record = hull.ship_registry_id ? GLOB.ship_registry.get_record(hull.ship_registry_id, operator_uuid) : null
	var/record_id = record?.id
	var/revision = record ? record.revision + 1 : 1
	var/list/appraisal = shipyard_appraise_lockbox(teardown.lockbox_items)
	var/list/quote = shipyard_storage_quote(tile_count, appraisal["total"], pending_insurance_refund(record))
	var/net = quote["net"]
	if(!record_id)
		record_id = GLOB.ship_registry.insert_record(operator_uuid, operator_ckey, hull_name)
		if(!record_id)
			set_status(FALSE, "The registry would not accept a new record.")
			qdel(teardown)
			return FALSE

	var/charge_reason = "Ship storage: [hull_name] (record [record_id], revision [revision])"
	if(net > 0)
		var/datum/character_ledger_result/charge = shipyard_charge_fee(operator_uuid, net, LEDGER_CHANNEL_SHIP_STORAGE, charge_reason, record_id, revision, "file")
		if(!charge.success)
			if(!record)
				GLOB.ship_registry.discard(record_id)
			set_status(FALSE, "Filing refused: [shipyard_ledger_refusal_text(charge)]")
			qdel(teardown)
			return FALSE

	var/file_path = shipyard_ship_file_path(operator_uuid, record_id, revision)
	// Copied before the release, which deletes the items it describes.
	var/list/stored_contents = teardown.stored_contents.Copy()
	var/written = shipyard_write_and_release(hull, teardown, file_path)
	qdel(teardown)
	if(!written)
		if(net > 0)
			shipyard_refund_fee(operator_uuid, net, LEDGER_CHANNEL_SHIP_STORAGE, "Refund: [charge_reason]", record_id, revision, "file")
		if(!record)
			GLOB.ship_registry.discard(record_id)
		set_status(FALSE, "[hull_name] could not be written to storage. It has been left on the pad[net > 0 ? " and the fee refunded" : ""].")
		return FALSE

	var/salvage = shipyard_salvage_estimate(file_path)
	var/checksum = rustg_hash_file(RUSTG_HASH_SHA256, file_path)
	if(!GLOB.ship_registry.store_revision(record_id, revision, file_path, checksum, stored_contents, tile_count, hull_name, salvage))
		// The hull is already off the pad and on disk. Nothing automatic can put
		// it right, so an admin has to see it.
		log_admin("Ship registry: [key_name(user)] filed [hull_name] to [file_path] but record [record_id] could not be updated to revision [revision].")
		message_admins("Ship registry: [hull_name] (record [record_id]) was written to [file_path] but its registry row was not updated. The owner's ship is not in their garage.")
		set_status(FALSE, "[hull_name] left the pad, but the registry did not record it. An administrator has been notified.")
		return FALSE

	var/credited = 0
	if(net < 0)
		credited = -net
		shipyard_credit_fee(operator_uuid, credited, LEDGER_CHANNEL_SHIP_INSURANCE, "Insurance refund surplus: [hull_name] (record [record_id], revision [revision])", record_id, revision, "insurance-surplus")
	log_admin("Ship registry: [key_name(user)] filed [hull_name] as record [record_id] revision [revision] ([tile_count] tiles, [length(stored_contents)] lockbox items, salvage [salvage] cr) to [file_path]. Storage [quote["storage"]] cr, insurance refund [quote["insuranceRefund"]] cr, net [net] cr.")
	survey = null
	surveyed_hull = null
	var/money_text = net > 0 ? "Charged [net] cr." : (credited ? "Credited [credited] cr of unused insurance." : "No charge.")
	set_status(TRUE, "[hull_name] filed as revision [revision]. [money_text]")
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return TRUE

/**
 * Charge for a filed ship and call it back onto the pad.
 *
 * The fee is taken before anything loads and handed back if the hull does not
 * land, and the row is flipped to checked-out only once a registered port
 * exists, so a refusal leaves the record filed, the file untouched and the
 * ledger where it was. Returns the retrieved port, or null.
 */
/obj/machinery/computer/ship_registrar/proc/retrieve_record(record_id, insured, obj/effect/landmark/overmap_landing_zone/zone, mob/user)
	if(world.time < busy_until)
		set_status(FALSE, "The registrar is still working on the last request.")
		return null
	busy_until = world.time + SHIP_REGISTRAR_BUSY_TIMEOUT
	. = do_retrieve_record(record_id, insured, zone, user)
	busy_until = 0

/obj/machinery/computer/ship_registrar/proc/do_retrieve_record(record_id, insured, obj/effect/landmark/overmap_landing_zone/zone, mob/user)
	PRIVATE_PROC(TRUE)
	if(!zone)
		set_status(FALSE, "No landing pad is linked. Use a multitool on a landing controller, then on this console.")
		return null
	if(zone.get_occupant())
		set_status(FALSE, "[zone.zone_name] is occupied. Clear the pad first.")
		return null
	if(!operator_uuid)
		set_status(FALSE, "No persistent identity is on record for this operator.")
		return null
	if(!GLOB.ship_registry.is_online())
		set_status(FALSE, "The hangar registry is offline. Retrieval is unavailable.")
		return null
	if(!SScharacter_ledger.is_available())
		set_status(FALSE, "The ledger is offline. Fees cannot be charged.")
		return null
	var/datum/player_ship_record/record = GLOB.ship_registry.get_record(record_id, operator_uuid)
	if(!record)
		set_status(FALSE, "No such vessel is registered to you.")
		return null
	switch(record.status)
		if(SHIP_STATUS_CHECKED_OUT)
			set_status(FALSE, "[record.ship_name] is already deployed.")
			return null
		if(SHIP_STATUS_LOST)
			set_status(FALSE, "[record.ship_name] was lost and cannot be retrieved.")
			return null
	if(!record.is_retrievable())
		set_status(FALSE, "[record.ship_name] has no saved hull to retrieve.")
		return null
	if(record.map_checksum && rustg_hash_file(RUSTG_HASH_SHA256, record.map_path) != record.map_checksum)
		log_admin("Ship registry: [key_name(user)] tried to retrieve [record.ship_name] (record [record.id]) but [record.map_path] does not match its checksum.")
		set_status(FALSE, "The stored hull for [record.ship_name] failed its integrity check. An administrator will need to look at it.")
		return null

	var/fee = insured ? shipyard_insurance_fee(record.salvage_estimate) : shipyard_uninsured_fee()
	var/channel = insured ? LEDGER_CHANNEL_SHIP_INSURANCE : LEDGER_CHANNEL_SHIP_RETRIEVE
	var/charge_reason = "Ship retrieval, [insured ? "insured" : "uninsured"]: [record.ship_name] (record [record.id], revision [record.revision])"
	var/datum/character_ledger_result/charge = shipyard_charge_fee(operator_uuid, fee, channel, charge_reason, record.id, record.revision, "retrieve")
	if(!charge.success)
		set_status(FALSE, "Retrieval refused: [shipyard_ledger_refusal_text(charge)]")
		return null

	var/obj/docking_port/mobile/hull = shipyard_retrieve_hull(record.map_path, record.ship_name, zone, record.stored_contents)
	if(!hull)
		var/refunded = shipyard_refund_fee(operator_uuid, fee, channel, "Refund: [charge_reason]", record.id, record.revision, "retrieve")
		set_status(FALSE, "Retrieval refused: [record.ship_name] could not be set down on [zone.zone_name]. It may not fit the pad, or the pad may be obstructed.[fee > 0 ? (refunded ? " Your [fee] cr fee was refunded." : " Your fee could not be refunded automatically; an administrator has the record.") : ""]")
		return null
	hull.ship_ownership = SHIP_OWNERSHIP_PERSONAL
	hull.ship_owner_id = operator_uuid
	hull.ship_registry_id = record.id
	if(!GLOB.ship_registry.checkout(record.id, insured, insured ? fee : 0))
		// A hull out in the world against a row that still says filed could be
		// retrieved a second time. Undo the retrieval rather than allow that.
		hull.jumpToNullSpace()
		shipyard_refund_fee(operator_uuid, fee, channel, "Refund: [charge_reason]", record.id, record.revision, "retrieve")
		log_admin("Ship registry: checkout of [record.ship_name] (record [record.id]) for [key_name(user)] could not be recorded; the retrieval was undone.")
		set_status(FALSE, "The registry could not record the checkout, so [record.ship_name] was sent back to storage. Any fee was refunded.")
		return null
	log_admin("Ship registry: [key_name(user)] retrieved [record.ship_name] (record [record.id], revision [record.revision]) onto [zone.zone_name], [insured ? "insured" : "uninsured"], for [fee] cr.")
	set_status(TRUE, "[record.ship_name] is landing on [zone.zone_name], [insured ? "insured" : "uninsured"]. Charged [fee] cr.")
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return hull

/// A ledger refusal in words a player can act on.
/proc/shipyard_ledger_refusal_text(datum/character_ledger_result/result)
	switch(result.status)
		if(LEDGER_STATUS_INSUFFICIENT)
			return "not enough credits in your ledger."
		if(LEDGER_STATUS_OFFLINE)
			return "the ledger is offline."
		if(LEDGER_STATUS_NO_IDENTITY)
			return "no ledger identity is registered for this character."
	return result.reason || "the ledger refused the charge."

#undef SHIP_REGISTRAR_BUSY_TIMEOUT
