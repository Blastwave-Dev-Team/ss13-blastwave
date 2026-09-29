// MODULE ID: OVERMAP
// The load-side mirror of the shipyard teardown: take a saved .dmm back off the
// disk and stand it up on a landing pad as a registered, flyable ship.
//
// Retrieval owns its own load rather than routing through SSshuttle.action_load().
// Two reasons, both structural rather than stylistic:
//
// action_load() reports every failure by CRASH()ing - a failed reservation, a
// canDock() mismatch, a map with no mobile port. DM has no exception handling, so
// a CRASH unwinds the console's ui_act along with it: there is no way to turn any
// of that into a refusal a player can read, and no way to clean up the hull left
// staged in transit space on the way out.
//
// It also stages through SSshuttle.preview_shuttle and preview_template, which is
// the shuttle manipulator's own slot. Borrowing it means a player clicking
// Retrieve can nullspace a hull an admin has staged for preview. Nothing here is
// shared, so two retrievals cannot collide.
//
// The staging and commit helpers take a template and a zone, never a registry
// record, so anything else that delivers a hull - a dealership, an admin tool -
// reuses them unchanged.

/**
 * Stamp the template's identity onto the port the saved map carries.
 *
 * A saved hull deliberately records no identity - see `describe_port()` - because
 * the id a retrieval registers under belongs to that retrieval. The mapped port
 * type may well carry one anyway: a hull printed from a typed blueprint saves as
 * something like `/obj/docking_port/mobile/overmap/frigate/nt_personal`, which
 * hardcodes `shuttle_id`, so without this every retrieved hull of that type
 * would try to register as a second copy of the mapped ship.
 *
 * `dispatch()` is the hook because `Initialize()` is where a port both uniquifies
 * its id and binds its overmap ship, and dispatch runs immediately before that.
 */
/datum/map_template/shuttle/runtime/dispatch(list/turfs, register = TRUE)
	for(var/turf/place as anything in turfs)
		for(var/obj/docking_port/mobile/port in place)
			port.shuttle_id = shuttle_id
			port.name = name
	. = ..()
	fit_loaded_ports_to_hull(turfs)

/**
 * What a retrieval has taken out on loan, so that an abort can hand all of it
 * back. DM has no `finally`, and the alternative is repeating the cleanup at
 * every early return until one of them forgets a piece.
 */
/datum/shipyard_staging
	var/datum/turf_reservation/reservation
	var/obj/docking_port/mobile/hull

/// Give up on a staged hull: the ship ceases, the reservation is handed back.
/datum/shipyard_staging/proc/abandon()
	if(!QDELETED(hull))
		hull.jumpToNullSpace()
	release()

/// Release the reservation, leaving whatever has already moved off it alone.
/datum/shipyard_staging/proc/release()
	hull = null
	QDEL_NULL(reservation)

/**
 * Load a shuttle template into a transit reservation of its own.
 *
 * This is `SSshuttle.load_template()` with the global side effects and the
 * crashes taken out. Returns the staged mobile port, or null. Whatever it did
 * manage to take is recorded on `staging` for the caller to hand back.
 */
/proc/shipyard_stage_hull(datum/map_template/shuttle/template, datum/shipyard_staging/staging)
	// A template pointed at a file that is not there preloads as zero by zero,
	// and a zero-sized reservation request fails somewhere much less obvious.
	if(!template.width || !template.height)
		return null
	var/datum/turf_reservation/reservation = SSmapping.request_turf_block_reservation(
		template.width,
		template.height,
		1,
		reservation_type = /datum/turf_reservation/transit,
	)
	if(!reservation)
		return null
	staging.reservation = reservation
	var/turf/bottom_left = reservation.bottom_left_turfs[1]
	if(!template.load(bottom_left, centered = FALSE, register = FALSE))
		return null

	var/obj/docking_port/mobile/found
	for(var/turf/place as anything in template.get_affected_turfs(bottom_left, centered = FALSE))
		for(var/obj/docking_port/mobile/port in place)
			if(found)
				// Two hearts is not a ship. Refusing beats picking one and
				// leaving the other registered to nothing.
				staging.hull = found
				return null
			found = port
	staging.hull = found
	return found

/**
 * Register a staged hull and fly it onto its pad.
 *
 * This is the middle of `action_load()` copied deliberately, and every line of it
 * earns its place: `post_load()` runs `linkup()`, which is what populates
 * `engine_list` and re-preps the bound overmap ship; the zeroed `movement_force`
 * stops arrival from knocking down anyone standing on the pad; `SHUTTLE_PREARRIVAL`
 * keeps the move from being read as an idle drift and having its dock reaped.
 *
 * The one deviation is how failure is reported. Keep this thin, and keep the unit
 * test driving it, so that an upstream reorder surfaces as a test failure rather
 * than as a subtly broken ship.
 */
/proc/shipyard_commit_hull(datum/map_template/shuttle/template, obj/docking_port/mobile/hull, obj/docking_port/stationary/pad)
	var/dockable = hull.canDock(pad)
	// Someone else being docked is fine: we are about to take their place.
	if(dockable != SHUTTLE_CAN_DOCK && dockable != SHUTTLE_SOMEONE_ELSE_DOCKED)
		return null
	// action_load() registers without this flag, which for us would be wrong: a
	// /custom port that never reaches SSshuttle.custom_shuttles has dead
	// blueprints and does not count against the shuttle cap.
	hull.register(custom = istype(hull, /obj/docking_port/mobile/custom))
	template.post_load(hull)
	var/list/force_memory = hull.movement_force
	hull.movement_force = list("KNOCKDOWN" = 0, "THROW" = 0)
	hull.mode = SHUTTLE_PREARRIVAL
	// Forced, which action_load() does not do, because a custom port consents to
	// move only under its own engine power - and a hull being set down by the
	// shipyard is not flying itself in. An engineless or unfuelled ship has to be
	// retrievable, or filing it away is a one-way trip. What force skips is
	// check_dock() and the footprint, both already run when the pad was built.
	var/docked = hull.initiate_docking(pad, force = TRUE)
	hull.movement_force = force_memory
	hull.mode = SHUTTLE_IDLE
	// Checked, unlike action_load(), which crashes instead. A silently refused
	// dock leaves a registered ship sitting in the staging reservation.
	if(docked != DOCKING_SUCCESS)
		hull.unregister()
		return null
	hull.postregister()
	remount_shuttle_wallmounts(hull.return_turfs())
	return hull

/// Put back what the lockbox was holding when the ship was filed. By type path
/// only: an item's own state is not part of what a ship remembers yet.
/proc/shipyard_restore_stored_contents(obj/docking_port/mobile/hull, list/stored_contents)
	if(!length(stored_contents))
		return 0
	var/obj/structure/closet/secure_closet/ship_lockbox/target
	for(var/turf/deck as anything in hull.return_turfs())
		if(!hull.shuttle_areas[deck.loc])
			continue
		for(var/obj/structure/closet/secure_closet/ship_lockbox/lockbox in deck)
			if(lockbox.loc == deck)
				target = lockbox
				break
		if(target)
			break
	if(!target)
		return 0
	var/restored = 0
	for(var/list/entry as anything in stored_contents)
		var/obj/item/path = entry["path"]
		if(!ispath(path, /obj/item))
			continue
		new path(target)
		restored++
	return restored

/**
 * Stand a saved ship up on a landing pad.
 *
 * Deliberately takes a path and a manifest rather than a registry record: the
 * whole load path is then exercisable without a database, which is what lets the
 * unit test cover it. Returns the registered port, or null on any refusal, having
 * left nothing staged behind.
 */
/proc/shipyard_retrieve_hull(file_path, ship_name, obj/effect/landmark/overmap_landing_zone/zone, list/stored_contents)
	if(!file_path || !zone)
		return null
	if(!fexists(file_path))
		return null
	var/datum/map_template/shuttle/runtime/template = new(file_path)
	if(ship_name)
		template.name = ship_name
	var/datum/shipyard_staging/staging = new()
	var/obj/docking_port/mobile/hull = shipyard_stage_hull(template, staging)
	if(!hull)
		staging.abandon()
		qdel(template)
		return null
	var/obj/docking_port/stationary/pad = zone.create_landing_port(hull)
	if(!pad)
		staging.abandon()
		qdel(template)
		return null
	if(!shipyard_commit_hull(template, hull, pad))
		qdel(pad)
		staging.abandon()
		qdel(template)
		return null
	shipyard_restore_stored_contents(hull, stored_contents)
	// The hull has moved off the reservation, so only the reservation is left to
	// release; the ship itself is now the world's.
	staging.release()
	qdel(template)
	return hull

// --- Record delivery --------------------------------------------------------

/// What `shipyard_deliver_record()` did, and the words to tell the player.
/datum/shipyard_delivery
	var/success = FALSE
	var/obj/docking_port/mobile/hull
	/// What the checkout was charged.
	var/fee = 0
	var/message

/datum/shipyard_delivery/proc/refuse(text)
	success = FALSE
	message = text
	return src

/**
 * Charge for a filed ship and set it down on a pad, checked out to its owner.
 *
 * The one path from a registry row to a ship in the world, shared by the
 * registrar's retrieval and the broker's pad delivery. The fee is taken before
 * anything loads and handed back if the hull does not land, and the row is
 * flipped to checked-out only once a registered port exists, so a refusal
 * leaves the record filed, the file untouched and the ledger where it was.
 *
 * `waive_uninsured_fee` is for a broker delivery, whose hull price already
 * covers the trip to the pad; insurance is still its own charge.
 */
/proc/shipyard_deliver_record(datum/player_ship_record/record, obj/effect/landmark/overmap_landing_zone/zone, insured, owner_uuid, actor, waive_uninsured_fee = FALSE)
	var/datum/shipyard_delivery/delivery = new()
	if(!zone)
		return delivery.refuse("No landing pad is linked. Use a multitool on a landing controller, then on this console.")
	if(zone.get_occupant())
		return delivery.refuse("[zone.zone_name] is occupied. Clear the pad first.")
	if(!owner_uuid)
		return delivery.refuse("No persistent identity is on record for this operator.")
	if(!GLOB.ship_registry.is_online())
		return delivery.refuse("The hangar registry is offline. Retrieval is unavailable.")
	if(!SScharacter_ledger.is_available())
		return delivery.refuse("The ledger is offline. Fees cannot be charged.")
	if(!record)
		return delivery.refuse("No such vessel is registered to you.")
	switch(record.status)
		if(SHIP_STATUS_CHECKED_OUT)
			return delivery.refuse("[record.ship_name] is already deployed.")
		if(SHIP_STATUS_LOST)
			return delivery.refuse("[record.ship_name] was lost and cannot be retrieved.")
	if(!record.is_retrievable())
		return delivery.refuse("[record.ship_name] has no saved hull to retrieve.")
	if(record.map_checksum && rustg_hash_file(RUSTG_HASH_SHA256, record.map_path) != record.map_checksum)
		log_admin("Ship registry: [key_name(actor)] tried to retrieve [record.ship_name] (record [record.id]) but [record.map_path] does not match its checksum.")
		return delivery.refuse("The stored hull for [record.ship_name] failed its integrity check. An administrator will need to look at it.")

	var/fee = insured ? shipyard_insurance_fee(record.salvage_estimate) : (waive_uninsured_fee ? 0 : shipyard_uninsured_fee())
	var/channel = insured ? LEDGER_CHANNEL_SHIP_INSURANCE : LEDGER_CHANNEL_SHIP_RETRIEVE
	var/charge_reason = "Ship retrieval, [insured ? "insured" : "uninsured"]: [record.ship_name] (record [record.id], revision [record.revision])"
	var/datum/character_ledger_result/charge = shipyard_charge_fee(owner_uuid, fee, channel, charge_reason, record.id, record.revision, "retrieve")
	if(!charge.success)
		return delivery.refuse("Retrieval refused: [shipyard_ledger_refusal_text(charge)]")

	var/obj/docking_port/mobile/hull = shipyard_retrieve_hull(record.map_path, record.ship_name, zone, record.stored_contents)
	if(!hull)
		var/refunded = shipyard_refund_fee(owner_uuid, fee, channel, "Refund: [charge_reason]", record.id, record.revision, "retrieve")
		return delivery.refuse("Retrieval refused: [record.ship_name] could not be set down on [zone.zone_name]. It may not fit the pad, or the pad may be obstructed.[fee > 0 ? (refunded ? " Your [fee] cr fee was refunded." : " Your fee could not be refunded automatically; an administrator has the record.") : ""]")
	hull.ship_ownership = SHIP_OWNERSHIP_PERSONAL
	hull.ship_owner_id = owner_uuid
	hull.ship_registry_id = record.id
	if(!GLOB.ship_registry.checkout(record.id, insured, insured ? fee : 0))
		// A hull out in the world against a row that still says filed could be
		// retrieved a second time. Undo the retrieval rather than allow that.
		hull.jumpToNullSpace()
		shipyard_refund_fee(owner_uuid, fee, channel, "Refund: [charge_reason]", record.id, record.revision, "retrieve")
		log_admin("Ship registry: checkout of [record.ship_name] (record [record.id]) for [key_name(actor)] could not be recorded; the retrieval was undone.")
		return delivery.refuse("The registry could not record the checkout, so [record.ship_name] was sent back to storage. Any fee was refunded.")
	log_admin("Ship registry: [key_name(actor)] retrieved [record.ship_name] (record [record.id], revision [record.revision]) onto [zone.zone_name], [insured ? "insured" : "uninsured"], for [fee] cr.")
	delivery.success = TRUE
	delivery.hull = hull
	delivery.fee = fee
	delivery.message = "[record.ship_name] is landing on [zone.zone_name], [insured ? "insured" : "uninsured"]. Charged [fee] cr."
	return delivery

// --- Admin tooling ----------------------------------------------------------

ADMIN_VERB(ship_retrieve, R_DEBUG, "Ship Retrieve", "Load a saved ship .dmm onto the nearest landing zone.", ADMIN_CATEGORY_DEBUG)
	var/file_path = tgui_input_text(user, "Path to the saved ship map, relative to the server root.", "Ship Retrieve", max_length = MAX_MESSAGE_LEN)
	if(!file_path)
		return
	if(!fexists(file_path))
		to_chat(user, span_warning("No file at [file_path]."))
		return
	var/turf/standing = get_turf(user.mob)
	var/obj/effect/landmark/overmap_landing_zone/nearest
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in SSovermap.landing_zones)
		if(zone.z != standing?.z)
			continue
		if(!nearest || get_dist(standing, zone) < get_dist(standing, nearest))
			nearest = zone
	if(!nearest)
		to_chat(user, span_warning("No landing zone on this Z level to retrieve onto."))
		return
	var/obj/docking_port/mobile/retrieved = shipyard_retrieve_hull(file_path, null, nearest)
	if(!retrieved)
		to_chat(user, span_warning("Retrieval refused. The hull may not fit the zone, the pad may be occupied, or the map may hold no docking port."))
		return
	// An admin-loaded file has no owner to answer to, so it lands as station
	// property and the registrar will not file it into anyone's garage.
	retrieved.ship_ownership = SHIP_OWNERSHIP_STATION
	log_admin("[key_name(user)] retrieved a ship from [file_path] onto [nearest.zone_name].")
	to_chat(user, span_notice("Retrieved [retrieved.name] ([retrieved.shuttle_id]) onto [nearest.zone_name]."))
