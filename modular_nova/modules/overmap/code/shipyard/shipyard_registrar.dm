// MODULE ID: OVERMAP
// The counter a player files a ship at and retrieves it from.
//
// The only thing in the module that touches the registry, the ledger and the
// disk together. Teardown and retrieval know how to put a hull on and off the
// disk, the registry knows who owns what, pricing knows what it costs; this
// orders them. Ships belong to a character, by the UUID on their mind, rather
// than to the player's ckey; garage slots are the ckey's, shared by all of them.

/obj/machinery/computer/ship_registrar
	name = "ship registrar"
	desc = "A vessel registry terminal. Files a landed personal ship into long-term storage against its owner's ledger, and calls it back to the pad later."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	circuit = /obj/item/circuitboard/computer/ship_registrar
	req_access = list()
	req_one_access = list()
	// `authenticated` is the parent's, and means the same thing here.
	/// Operator, ledger and pad state, shared with the broker.
	var/datum/shipyard_session/session
	/// Survey data for the last surveyed hull, in the shape the UI reads.
	var/list/survey
	var/datum/weakref/surveyed_hull
	/// Owner's ship list, garage slots and derived prices, refreshed on login and
	/// after anything that changes them. Held rather than queried per `ui_data`,
	/// which runs every tick.
	var/list/datum/player_ship_record/known_ships
	var/list/slots
	/// record id -> scrap payout, which appraises the lockbox roster item by item.
	var/list/scrap_values
	/// The occupant's refusal, rechecked at most once a second: it walks every
	/// tile of the hull, which is too much to do on every UI tick.
	var/list/cached_refusal
	var/datum/weakref/refusal_hull
	COOLDOWN_DECLARE(refusal_recheck)
	/// Survey walks every object aboard without yielding, so clicks sent while it
	/// runs are queued and arrive after it has finished; this swallows them.
	COOLDOWN_DECLARE(survey_repeat)

/obj/machinery/computer/ship_registrar/Initialize(mapload, obj/item/circuitboard/C)
	. = ..()
	session = new(src)

/obj/machinery/computer/ship_registrar/Destroy()
	QDEL_NULL(session)
	return ..()

/obj/machinery/computer/ship_registrar/multitool_act(mob/living/user, obj/item/multitool/tool)
	var/result = session.try_link(user, tool)
	return isnull(result) ? ..() : result

/obj/machinery/computer/ship_registrar/examine(mob/user)
	. = ..()
	. += session.examine_line()

/obj/machinery/computer/ship_registrar/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(ui)
		return
	// The login screen reports registry state too, and a login has not refreshed it yet.
	session.refresh()
	ui = new(user, src, "ShipRegistrar", name)
	ui.open()

/obj/machinery/computer/ship_registrar/ui_close(mob/user)
	. = ..()
	session.on_operator_leave(user)
	if(!authenticated)
		known_ships = null
		slots = null
		scrap_values = null
		survey = null
		surveyed_hull = null

/obj/machinery/computer/ship_registrar/proc/start_session(mob/user)
	session.start(user)
	refresh_session()

/obj/machinery/computer/ship_registrar/proc/end_session()
	session.end()
	known_ships = null
	slots = null
	scrap_values = null
	survey = null
	surveyed_hull = null

/// Re-read everything `ui_data` shows from the registry and the ledger.
/obj/machinery/computer/ship_registrar/proc/refresh_session()
	session.refresh()
	known_ships = session.registry_online ? GLOB.ship_registry.list_for_owner(session.operator_uuid) : list()
	slots = session.registry_online ? session.slot_usage() : null
	scrap_values = list()
	for(var/datum/player_ship_record/record as anything in known_ships)
		if(record.status == SHIP_STATUS_FILED)
			scrap_values["[record.id]"] = shipyard_scrap_value(record)
	COOLDOWN_RESET(src, refusal_recheck)

/obj/machinery/computer/ship_registrar/proc/set_status(good, text)
	session.set_status(good, text)

/// The pad this console works over, or null when nothing is linked.
/obj/machinery/computer/ship_registrar/proc/active_zone()
	return session.active_zone()

/// Why the hull on the pad cannot be filed by this operator, recomputed at most
/// once a second.
/obj/machinery/computer/ship_registrar/proc/occupant_refusal(obj/docking_port/mobile/hull, obj/effect/landmark/overmap_landing_zone/zone)
	if(!hull)
		return null
	if(refusal_hull?.resolve() != hull || COOLDOWN_FINISHED(src, refusal_recheck))
		refusal_hull = WEAKREF(hull)
		cached_refusal = shipyard_file_refusal(hull, zone, session.operator_uuid)
		COOLDOWN_START(src, refusal_recheck, 1 SECONDS)
	return cached_refusal

/// One of the operator's records from the last refresh, by id.
/obj/machinery/computer/ship_registrar/proc/known_record(record_id)
	record_id = text2num("[record_id]")
	for(var/datum/player_ship_record/record as anything in known_ships)
		if(record.id == record_id)
			return record
	return null

/obj/machinery/computer/ship_registrar/ui_data(mob/user)
	var/list/data = session.base_ui_data(user)
	if(!data["authenticated"])
		return data

	data["ledgerBalance"] = session.ledger_balance
	var/obj/effect/landmark/overmap_landing_zone/zone = active_zone()
	var/obj/docking_port/mobile/hull = zone?.get_occupant()
	var/list/occupant
	if(hull)
		var/datum/player_ship_record/occupant_record = hull.ship_registry_id ? known_record(hull.ship_registry_id) : null
		occupant = list(
			"name" = hull.name,
			"ownership" = hull.ship_ownership,
			"ownedByOperator" = !!(session.operator_uuid && hull.ship_owner_id == session.operator_uuid),
			"registryId" = hull.ship_registry_id,
			"rebuilt" = occupant_record?.status == SHIP_STATUS_LOST,
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

	var/list/grants = list()
	var/list/grant_sources = list()
	for(var/datum/ship_slot_grant/grant as anything in GLOB.ship_garage_slots.list_grants(session.operator_ckey))
		grants += list(list("kind" = grant.kind, "source" = grant.source, "count" = grant.count))
		grant_sources["[grant.id]"] = grant.source
	data["slots"] = slots ? list(
		"base" = slots["base"],
		"grants" = grants,
		"total" = slots["total"],
		"used" = slots["used"],
		// Held by the player's other characters, which this one cannot see.
		"elsewhere" = max(0, slots["used"] - length(known_ships)),
	) : list("base" = 0, "grants" = grants, "total" = 0, "used" = 0, "elsewhere" = 0)

	var/list/ships = list()
	for(var/datum/player_ship_record/record as anything in known_ships)
		var/datum/hull_profile/profile = shipyard_hull_profile(record.map_path)
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
			"silhouette" = profile?.silhouette_data(),
			"scrapValue" = scrap_values?["[record.id]"] || 0,
			"blueprintPrinted" = GLOB.ship_registry.blueprint_printed(record.id),
			"blueprintFee" = shipyard_blueprint_fee(record),
			"grant" = record.grant_id ? grant_sources["[record.grant_id]"] : null,
		))
	data["ships"] = ships
	data["statusMessage"] = session.status_message
	return data

/obj/machinery/computer/ship_registrar/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/ui_state)
	. = ..()
	if(.)
		return
	var/mob/living/user = usr
	if(session.is_busy())
		return FALSE

	if(session.handle_login_act(action, user))
		if(authenticated)
			refresh_session()
		else
			end_session()
		return TRUE

	// Mirror ui_data: admin ghosts can act without a living login session.
	if(!session.has_session(user))
		return FALSE

	switch(action)
		if("refresh")
			refresh_session()
			return TRUE
		if("survey")
			if(!COOLDOWN_FINISHED(src, survey_repeat))
				return FALSE
			session.status_message = null
			run_survey(docked_hull(), active_zone())
			COOLDOWN_START(src, survey_repeat, 5 SECONDS)
			return TRUE
		if("file")
			session.status_message = null
			if(!session.require_pin(user, params["pin"]))
				return TRUE
			file_hull(docked_hull(), active_zone(), user)
			refresh_session()
			return TRUE
		if("retrieve")
			session.status_message = null
			if(!session.require_pin(user, params["pin"]))
				return TRUE
			retrieve_record(params["id"], !!text2num("[params["insured"]]"), active_zone(), user)
			refresh_session()
			return TRUE
		if("decommission")
			session.status_message = null
			decommission_record(params["id"], user)
			refresh_session()
			return TRUE
		if("print_blueprint")
			session.status_message = null
			if(!session.require_pin(user, params["pin"]))
				return TRUE
			print_blueprint(params["id"], user)
			refresh_session()
			return TRUE
		if("clear_slot")
			session.status_message = null
			clear_slot(params["id"], user)
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
	if(!session.begin_busy("Surveying [hull?.name || "the vessel"]..."))
		return FALSE
	. = do_run_survey(hull, zone)
	session.end_busy()

/obj/machinery/computer/ship_registrar/proc/do_run_survey(obj/docking_port/mobile/hull, obj/effect/landmark/overmap_landing_zone/zone)
	PRIVATE_PROC(TRUE)
	survey = null
	surveyed_hull = null
	if(!hull)
		set_status(FALSE, "No vessel is standing on the pad.")
		return FALSE
	var/list/refusal = shipyard_file_refusal(hull, zone, session.operator_uuid)
	if(refusal && shipyard_refusal_blocks_survey(refusal["code"]))
		set_status(FALSE, refusal["text"])
		return FALSE
	var/datum/ship_teardown/teardown = new(hull)
	if(teardown.refusal)
		set_status(FALSE, "This vessel cannot be filed: [teardown.refusal].")
		qdel(teardown)
		return FALSE
	var/datum/player_ship_record/record = hull.ship_registry_id ? GLOB.ship_registry.get_record(hull.ship_registry_id, session.operator_uuid) : null
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
 * Why a hull cannot take or keep a garage slot, or null when it can.
 *
 * A first filing needs a free slot. A hull filing back into its own row already
 * holds one, and is only turned away when the garage is over its limit: that is
 * how a player with more ships than slots is made to let one go.
 */
/obj/machinery/computer/ship_registrar/proc/slot_refusal(datum/player_ship_record/record)
	var/list/usage = session.slot_usage()
	if(!record)
		if(GLOB.ship_garage_slots.can_add(session.operator_ckey))
			return null
		return "Your garage is full ([usage["used"]] / [usage["total"]] slots). Clear or decommission a ship to free a slot."
	if(GLOB.ship_garage_slots.can_refile(session.operator_ckey, record))
		return null
	return "Garage over its slot limit ([usage["used"]] / [usage["total"]]). Clear or decommission another ship before filing this one back in."

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
	if(!session.begin_busy("Filing [hull?.name || "the vessel"] into storage..."))
		return FALSE
	. = do_file_hull(hull, zone, user)
	session.end_busy()

/obj/machinery/computer/ship_registrar/proc/do_file_hull(obj/docking_port/mobile/hull, obj/effect/landmark/overmap_landing_zone/zone, mob/user)
	PRIVATE_PROC(TRUE)
	var/operator_uuid = session.operator_uuid
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
	// A ship that was retrieved from a row, or rebuilt from one, goes back into
	// that row as its next revision. Without this every trip through the
	// registrar would leave another record behind.
	var/datum/player_ship_record/record = hull.ship_registry_id ? GLOB.ship_registry.get_record(hull.ship_registry_id, operator_uuid) : null
	var/slot_text = slot_refusal(record)
	if(slot_text)
		set_status(FALSE, slot_text)
		return FALSE
	var/datum/ship_teardown/teardown = new(hull)
	if(teardown.refusal)
		set_status(FALSE, "This vessel cannot be filed: [teardown.refusal].")
		qdel(teardown)
		return FALSE

	var/hull_name = teardown.name
	var/tile_count = length(teardown.cells)
	var/record_id = record?.id
	var/revision = record ? record.revision + 1 : 1
	var/list/appraisal = shipyard_appraise_lockbox(teardown.lockbox_items)
	var/list/quote = shipyard_storage_quote(tile_count, appraisal["total"], pending_insurance_refund(record))
	var/net = quote["net"]
	if(!record_id)
		record_id = GLOB.ship_registry.insert_record(operator_uuid, session.operator_ckey, hull_name)
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
 * Charge for a filed ship and call it back onto the pad. The work is
 * `shipyard_deliver_record()`, which the broker shares. Returns the retrieved
 * port, or null.
 */
/obj/machinery/computer/ship_registrar/proc/retrieve_record(record_id, insured, obj/effect/landmark/overmap_landing_zone/zone, mob/user)
	var/datum/player_ship_record/record = known_record(record_id)
	if(!session.begin_busy("Retrieving [record?.ship_name || "the vessel"] to [zone?.zone_name || "the pad"]..."))
		return null
	. = do_retrieve_record(record_id, insured, zone, user)
	session.end_busy()

/obj/machinery/computer/ship_registrar/proc/do_retrieve_record(record_id, insured, obj/effect/landmark/overmap_landing_zone/zone, mob/user)
	PRIVATE_PROC(TRUE)
	var/operator_uuid = session.operator_uuid
	var/datum/player_ship_record/record = (operator_uuid && GLOB.ship_registry.is_online()) ? GLOB.ship_registry.get_record(record_id, operator_uuid) : null
	var/datum/shipyard_delivery/delivery = shipyard_deliver_record(record, zone, insured, operator_uuid, user)
	set_status(delivery.success, delivery.message)
	if(!delivery.success)
		return null
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return delivery.hull

/// A stored record of the operator's, or null with the reason already on screen.
/obj/machinery/computer/ship_registrar/proc/owned_record(record_id, required_status)
	if(!session.operator_uuid)
		set_status(FALSE, "No persistent identity is on record for this operator.")
		return null
	if(!GLOB.ship_registry.is_online())
		set_status(FALSE, "The hangar registry is offline.")
		return null
	var/datum/player_ship_record/record = GLOB.ship_registry.get_record(record_id, session.operator_uuid)
	if(!record)
		set_status(FALSE, "No such vessel is registered to you.")
		return null
	if(record.status != required_status)
		switch(required_status)
			if(SHIP_STATUS_FILED)
				set_status(FALSE, "[record.ship_name] has to be in the garage for that.")
			if(SHIP_STATUS_LOST)
				set_status(FALSE, "[record.ship_name] is not lost.")
		return null
	return record

/**
 * Scrap a stored ship for a share of what it is worth, and free its slot.
 *
 * The payout is credited before the row goes, under a key that makes a retry
 * after a failed discard a duplicate rather than a second payment.
 */
/obj/machinery/computer/ship_registrar/proc/decommission_record(record_id, mob/user)
	var/datum/player_ship_record/record = owned_record(record_id, SHIP_STATUS_FILED)
	if(!record)
		return FALSE
	if(!SScharacter_ledger.is_available())
		set_status(FALSE, "The ledger is offline. The scrap payout cannot be credited.")
		return FALSE
	var/payout = shipyard_scrap_value(record)
	var/reason = "Ship decommissioned: [record.ship_name] (record [record.id], revision [record.revision])"
	var/datum/character_ledger_result/credit = shipyard_credit_fee(session.operator_uuid, payout, LEDGER_CHANNEL_SHIP_STORAGE, reason, record.id, record.revision, "scrap")
	if(!credit.success)
		set_status(FALSE, "Decommission refused: [shipyard_ledger_refusal_text(credit)]")
		return FALSE
	if(!GLOB.ship_registry.discard(record.id))
		message_admins("Ship registry: [record.ship_name] (record [record.id]) was scrapped for [payout] cr but its row could not be cleared.")
		set_status(FALSE, "[record.ship_name] was paid out, but the registry did not clear its slot. An administrator has been notified.")
		return FALSE
	log_admin("Ship registry: [key_name(user)] decommissioned [record.ship_name] (record [record.id], revision [record.revision]) for [payout] cr.")
	set_status(TRUE, "[record.ship_name] was scrapped for [payout] cr. Its garage slot is free.")
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return TRUE

/**
 * Print a lost ship's last filed revision onto a rebuild disk, once a shift.
 *
 * Costs the storage fee without the lockbox part, since nothing in the lockbox
 * comes back. A hull the owner builds from the disk files back into this row.
 */
/obj/machinery/computer/ship_registrar/proc/print_blueprint(record_id, mob/user)
	var/datum/player_ship_record/record = owned_record(record_id, SHIP_STATUS_LOST)
	if(!record)
		return null
	if(GLOB.ship_registry.blueprint_printed(record.id))
		set_status(FALSE, "A blueprint for [record.ship_name] has already been printed this shift.")
		return null
	if(!length(record.map_path) || !fexists(record.map_path))
		set_status(FALSE, "No filed survey of [record.ship_name] survives to print from.")
		return null
	var/fee = shipyard_blueprint_fee(record)
	var/reason = "Ship blueprint: [record.ship_name] (record [record.id], revision [record.revision])"
	var/datum/character_ledger_result/charge = shipyard_charge_fee(session.operator_uuid, fee, LEDGER_CHANNEL_SHIP_STORAGE, reason, record.id, record.revision, "blueprint")
	if(!charge.success)
		set_status(FALSE, "Printing refused: [shipyard_ledger_refusal_text(charge)]")
		return null
	var/obj/item/ship_blueprint_disk/registry_rebuild/disk = new(drop_location())
	disk.imprint(record)
	GLOB.ship_registry.note_blueprint_printed(record.id)
	log_admin("Ship registry: [key_name(user)] printed a rebuild blueprint of [record.ship_name] (record [record.id], revision [record.revision]) for [fee] cr.")
	set_status(TRUE, "A blueprint disk for [record.ship_name] (revision [record.revision]) was dispensed. Lockbox contents are not included. Charged [fee] cr. Build it at a shipyard fabricator and file it here to restore the slot.")
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return disk

/// Delete a lost ship's record, which is the only way its slot comes free.
/obj/machinery/computer/ship_registrar/proc/clear_slot(record_id, mob/user)
	var/datum/player_ship_record/record = owned_record(record_id, SHIP_STATUS_LOST)
	if(!record)
		return FALSE
	if(!GLOB.ship_registry.discard(record.id))
		set_status(FALSE, "The registry could not clear [record.ship_name]'s record.")
		return FALSE
	log_admin("Ship registry: [key_name(user)] cleared the record of lost ship [record.ship_name] (record [record.id]).")
	set_status(TRUE, "[record.ship_name]'s record was cleared. Its garage slot is free.")
	return TRUE

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

