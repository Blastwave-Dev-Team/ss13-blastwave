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
// Retrieve can nullspace a hull an admin has staged for preview, and would force a
// lock to prevent it. Nothing here is shared, so two retrievals cannot collide.
//
// action_load() itself is left alone and the manipulator keeps using it. Retrieved
// ships still show up in its status panel, which reads mobile_docking_ports and is
// populated by register() either way.

/**
 * Stamp the template's identity onto the port the saved map carries.
 *
 * A saved hull deliberately records no identity - see `describe_port()` - because
 * the id a retrieval registers under belongs to that retrieval. The mapped port
 * type may well carry one anyway: a hull printed from a typed blueprint saves as
 * something like `/obj/docking_port/mobile/overmap/frigate/solfed_patrol`, which
 * hardcodes `shuttle_id`, so without this every retrieved patrol boat would try
 * to register as a second copy of the mapped SolFed patrol.
 *
 * `dispatch()` is the hook because `Initialize()` is where a port both uniquifies
 * its id and binds its overmap ship, and dispatch runs immediately before that.
 */
/datum/map_template/shuttle/runtime/dispatch(list/turfs, register = TRUE)
	for(var/turf/place as anything in turfs)
		for(var/obj/docking_port/mobile/port in place)
			port.shuttle_id = shuttle_id
			port.name = name
	return ..()

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
	hull = null
	release()

/// Release the reservation, leaving whatever has already moved off it alone.
/datum/shipyard_staging/proc/release()
	hull = null
	QDEL_NULL(reservation)

/**
 * Load a saved hull into a transit reservation of its own.
 *
 * This is `SSshuttle.load_template()` with the global side effects and the
 * crashes taken out. Returns the staged mobile port, or null having cleaned up
 * after itself.
 */
/proc/shipyard_stage_hull(datum/map_template/shuttle/runtime/template, datum/shipyard_staging/staging)
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
				return null
			found = port
	return found

/**
 * A one-shot stationary port centered in `zone`, sized to the staged hull.
 *
 * The centering math is `create_landing_zone_port()` in overmap_ships.dm lifted
 * standalone, because that one hangs off an overmap ship that is already flyable
 * and a hull in transit space has no such thing yet. Returns null when the hull
 * does not fit or the pad is not clear, which is a refusal rather than a fault.
 */
/proc/shipyard_landing_pad_port(obj/docking_port/mobile/hull, obj/effect/landmark/overmap_landing_zone/zone)
	if(!hull || !zone)
		return null
	var/list/bounds = hull.return_coords()
	var/bbox_x1 = min(bounds[1], bounds[3])
	var/bbox_y1 = min(bounds[2], bounds[4])
	var/hull_width = max(bounds[1], bounds[3]) - bbox_x1 + 1
	var/hull_height = max(bounds[2], bounds[4]) - bbox_y1 + 1
	if(hull_width > zone.zone_width || hull_height > zone.zone_height)
		return null
	if(zone.get_occupant(hull))
		return null
	// Offset of the port tile inside its own bbox. With the pad sharing the
	// hull's dir and dimensions, landing reproduces the same bbox relative to
	// the port tile, so this places the ship centered in the zone.
	var/port_off_x = hull.x - bbox_x1
	var/port_off_y = hull.y - bbox_y1
	var/dest_x = zone.x + round((zone.zone_width - hull_width) / 2) + port_off_x
	var/dest_y = zone.y + round((zone.zone_height - hull_height) / 2) + port_off_y
	var/turf/destination = locate(dest_x, dest_y, zone.z)
	if(!destination)
		return null
	var/obj/docking_port/stationary/pad = new()
	pad.unregister()
	pad.delete_after = TRUE
	pad.name = zone.zone_name
	pad.shuttle_id = "[hull.shuttle_id]_lz"
	pad.width = hull.width
	pad.height = hull.height
	pad.dwidth = hull.dwidth
	pad.dheight = hull.dheight
	pad.register(TRUE)
	pad.setDir(hull.dir)
	pad.forceMove(destination)
	if(!hull.check_dock(pad, TRUE) || !SSovermap.dock_footprint_is_clear(pad))
		qdel(pad)
		return null
	return pad

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
/proc/shipyard_commit_hull(datum/map_template/shuttle/runtime/template, obj/docking_port/mobile/hull, obj/docking_port/stationary/pad)
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
		return null
	hull.postregister()
	return hull

/// Put back what the lockbox was holding when the ship was filed. By type path
/// only: an item's own state is not part of what a ship remembers.
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
	staging.hull = hull
	if(!hull)
		staging.abandon()
		qdel(template)
		return null
	var/obj/docking_port/stationary/pad = shipyard_landing_pad_port(hull, zone)
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
	log_admin("[key_name(user)] retrieved a ship from [file_path] onto [nearest.zone_name].")
	to_chat(user, span_notice("Retrieved [retrieved.name] ([retrieved.shuttle_id]) onto [nearest.zone_name]."))
