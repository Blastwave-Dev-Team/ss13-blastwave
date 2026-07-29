// MODULE ID: OVERMAP
// The reverse of the shipyard build: walk a registered hull back into the map
// cells it would have been printed from, and render those to TGM.
//
// The pivot is the cell model rather than the file. A hull exported here will
// never be byte-identical to the blueprint it was printed from - the key
// dictionary orders differently and the variable set is filtered to what the
// printer can actually read back - so the property worth holding is that the
// manifest built from the export matches the manifest built from the source,
// and that a second export of the same hull is byte-identical to the first.

/// The fabricator currently building this hull, if any. A hull under the
/// printer refuses teardown: its claim and operation index would go stale.
/obj/docking_port/mobile/var/datum/weakref/shipyard_build_claim

/// The registry row this hull was retrieved from, so filing it again updates
/// that record instead of leaving a second one behind pointing at a dead file.
/obj/docking_port/mobile/var/ship_registry_id

/**
 * One registered hull, described as the map that would rebuild it.
 *
 * Cells are keyed by 1-based coordinates relative to the hull's bounding box.
 * A coordinate inside the box that is not part of the ship simply has no cell,
 * and renders as a no-op the way an irregular shuttle template does.
 */
/datum/ship_teardown
	var/name = "Unnamed vessel"
	var/width = 0
	var/height = 0
	/// Relative "x,y" to list("objects", "turf_path", "turf_vars", "area_path").
	var/list/cells = list()
	/// Detail the walk could not name, reported rather than silently dropped.
	var/list/lost_detail = list()
	/// Lockbox payload. The only contents of a ship that survive being filed.
	var/list/stored_contents = list()
	/// Why this hull cannot be torn down at all, or null when it can.
	var/refusal

/**
 * Describe a live hull, or nothing at all.
 *
 * Constructed without a port this is an empty description for something else to
 * fill in, which is how a saved map is read back without a ship to walk.
 */
/datum/ship_teardown/New(obj/docking_port/mobile/port)
	. = ..()
	if(isnull(port))
		return
	if(!istype(port))
		refusal = "what was handed over is not a registered hull"
		return
	if(port.shipyard_build_claim?.resolve())
		refusal = "the hull is still under a shipyard fabricator"
		return
	if(!length(port.shuttle_areas))
		refusal = "the hull holds no shuttle areas"
		return

	name = port.name || name
	var/list/coords = port.return_coords()
	var/min_x = min(coords[1], coords[3])
	var/min_y = min(coords[2], coords[4])
	var/max_x = max(coords[1], coords[3])
	var/max_y = max(coords[2], coords[4])
	width = max_x - min_x + 1
	height = max_y - min_y + 1

	// Deliberately does not yield. A hull is a moving object with people on it,
	// and a walk that sleeps between tiles describes a ship that was never in
	// any one of the states it writes down.
	for(var/tile_x in min_x to max_x)
		for(var/tile_y in min_y to max_y)
			describe_tile(locate(tile_x, tile_y, port.z), tile_x - min_x + 1, tile_y - min_y + 1, port)
	describe_port(port, min_x, min_y)
	if(!length(cells))
		refusal = "the hull described no tiles"

/// Walk one tile into a cell model, or leave it absent if it is not ours.
/datum/ship_teardown/proc/describe_tile(turf/tile, rel_x, rel_y, obj/docking_port/mobile/port)
	if(!tile || !port.shuttle_areas[tile.loc])
		return
	var/area/tile_area = tile.loc

	var/list/objects = list()
	for(var/obj/thing in tile)
		// A wide atom lists itself in the contents of every tile it overlaps,
		// so only its anchor tile writes it down. Holograms are not there.
		if(thing.loc != tile || (thing.flags_1 & HOLOGRAM_1))
			continue
		var/datum/shipyard_route/route = get_shipyard_route(thing.type)
		if(!route)
			lost_detail += "([tile.x], [tile.y]): [thing.type] has no construction route"
			continue
		var/list/described = route.describe(thing)
		if(described)
			objects += list(described)
	objects += shipyard_describe_turf_decals(tile, lost_detail)
	shipyard_collapse_spawners(objects)
	collect_stored_contents(tile)

	var/list/turf_vars = list()
	var/list/turf_helpers = list()
	tile.shipyard_describe(turf_vars, turf_helpers)
	cells["[rel_x],[rel_y]"] = list(
		"objects" = objects,
		"turf_path" = tile.type,
		"turf_vars" = turf_vars,
		"turf_helpers" = turf_helpers,
		"area_path" = tile_area.type,
	)

/**
 * Add the mobile port back onto its own tile.
 *
 * Registration is what creates a port, so the live one is omitted by its route
 * on the way out and synthesized here instead: without it the export is a room,
 * not a shuttle template. Its identity is deliberately left off, since the id a
 * retrieval registers under belongs to that retrieval and not to this one.
 */
/datum/ship_teardown/proc/describe_port(obj/docking_port/mobile/port, min_x, min_y)
	var/list/cell = cells["[port.x - min_x + 1],[port.y - min_y + 1]"]
	if(!cell)
		lost_detail += "the docking port stands on a tile the hull does not own"
		return
	cell["objects"] += list(list(
		"path" = port.type,
		"vars" = list(
			"dir" = port.dir,
			"dwidth" = port.dwidth,
			"dheight" = port.dheight,
			"width" = port.width,
			"height" = port.height,
			"port_direction" = port.port_direction,
			"preferred_direction" = port.preferred_direction,
		),
		"helpers" = list(),
	))

/// Roster the contents of any lockbox on this tile. Everything else aboard,
/// loose or in a locker, is left behind when the ship is filed away.
/datum/ship_teardown/proc/collect_stored_contents(turf/tile)
	for(var/obj/structure/closet/secure_closet/ship_lockbox/lockbox in tile)
		if(lockbox.loc != tile)
			continue
		for(var/obj/item/stored in lockbox)
			stored_contents += list(list(
				"path" = stored.type,
				"name" = stored.name,
			))

/// Operator-facing summary of what the walk could and could not account for.
/datum/ship_teardown/proc/report()
	if(refusal)
		return list("Teardown refused: [refusal]")
	var/list/summary = list("[name]: [length(cells)] tiles across [width]x[height], [length(stored_contents)] stored item(s).")
	return summary + unique_list(lost_detail)

// --- TGM rendering ----------------------------------------------------------

/**
 * Render the cell models to TGM text.
 *
 * The encoder and the key dictionary come from the map exporter in
 * [code/modules/admin/verbs/map_export.dm]; what is not borrowed is its
 * philosophy, which is to write down everything it can see. A ship is written
 * from what the routes say can be built again.
 */
/datum/ship_teardown/proc/write_ship_tgm()
	if(refusal)
		return null
	var/list/header = list()
	var/list/header_keys = list()
	var/list/contents = list()
	var/key_index = 1
	var/key_length = max(1, FLOOR(log(length(GLOB.save_file_chars), max(width * height, 2)) + 0.999, 1))

	for(var/tile_x in 1 to width)
		contents += "\n([tile_x],1,1) = {\"\n"
		for(var/tile_y in height to 1 step -1)
			CHECK_TICK
			var/cell_text = render_cell(cells["[tile_x],[tile_y]"])
			var/key = header_keys[cell_text]
			if(!key)
				key = calculate_tgm_header_index(key_index, key_length)
				key_index++
				header += "\"[key]\" = [cell_text]"
				header_keys[cell_text] = key
			contents += "[key]\n"
		contents += "\"}"
	return "//[DMM2TGM_MESSAGE]\n[header.Join()][contents.Join()]"

/// One cell as the parenthesised member list TGM keys point at.
/datum/ship_teardown/proc/render_cell(list/cell)
	var/list/lines = list("(\n")
	if(cell)
		for(var/list/member as anything in cell["objects"])
			lines += "[member["path"]][shipyard_tgm_metadata(member["vars"])],\n"
			for(var/list/helper as anything in member["helpers"])
				lines += "[helper["path"]][shipyard_tgm_metadata(helper["vars"])],\n"
		// A helper the turf asked for goes last, next to what it acts on.
		for(var/list/helper as anything in cell["turf_helpers"])
			lines += "[helper["path"]][shipyard_tgm_metadata(helper["vars"])],\n"
		lines += "[cell["turf_path"]][shipyard_tgm_metadata(cell["turf_vars"])],\n"
		lines += "[cell["area_path"]])\n"
	else
		lines += "[/turf/template_noop],\n[/area/template_noop])\n"
	return lines.Join()

/// A variable override block, or an empty string when there is nothing to say.
/proc/shipyard_tgm_metadata(list/described_vars)
	if(!length(described_vars))
		return ""
	var/list/encoded = list()
	for(var/var_name in described_vars)
		encoded += "[var_name] = [tgm_encode(described_vars[var_name])]"
	return "{\n\t[encoded.Join(";\n\t")]\n\t}"

// --- Reading a saved hull back ----------------------------------------------

/**
 * Rebuild the cell models a saved map describes, without loading it.
 *
 * This is what makes the export checkable: rendering these cells again has to
 * produce the file they came from, byte for byte. A generation that is not a
 * fixed point is one that drifts, and a ship saved and retrieved often enough
 * would drift arbitrarily far from the hull the player parked.
 */
/proc/shipyard_teardown_from_parsed(datum/parsed_map/parsed)
	var/datum/ship_teardown/rebuilt = new()
	if(!parsed?.bounds)
		rebuilt.refusal = "the saved map could not be parsed"
		return rebuilt
	var/list/model_cache = parsed.build_cache()
	var/min_x = parsed.bounds[MAP_MINX]
	var/min_y = parsed.bounds[MAP_MINY]
	var/min_z = parsed.bounds[MAP_MINZ]
	rebuilt.width = parsed.bounds[MAP_MAXX] - min_x + 1
	rebuilt.height = parsed.bounds[MAP_MAXY] - min_y + 1

	for(var/datum/grid_set/grid_set as anything in parsed.gridSets)
		if(grid_set.zcrd != min_z)
			continue
		var/map_y = grid_set.ycrd
		for(var/line in grid_set.gridLines)
			var/map_x = grid_set.xcrd
			for(var/position in 1 to length(line) step parsed.key_len)
				var/list/model = model_cache[copytext(line, position, position + parsed.key_len)]
				if(model)
					rebuilt.adopt_model(model, map_x - min_x + 1, map_y - min_y + 1)
				map_x++
			map_y--
	if(!length(rebuilt.cells))
		rebuilt.refusal = "the saved map described no tiles"
	return rebuilt

/// Turn one parsed map cell back into the model that would render it. Helpers
/// follow the member they belong to, which is the order they were written in.
/datum/ship_teardown/proc/adopt_model(list/model, rel_x, rel_y)
	var/list/members = model[1]
	var/list/member_attributes = model[2]
	var/turf_path
	var/list/turf_vars = list()
	var/list/turf_helpers = list()
	var/area_path
	var/list/objects = list()
	for(var/index in 1 to length(members))
		var/member_path = members[index]
		var/list/member_vars = member_attributes[index]
		member_vars = islist(member_vars) ? member_vars.Copy() : list()
		if(ispath(member_path, /turf))
			turf_path = member_path
			turf_vars = member_vars
			continue
		if(ispath(member_path, /area))
			area_path = member_path
			continue
		if(ispath(member_path, /obj/effect/mapping_helpers))
			var/list/helper = list("path" = member_path, "vars" = member_vars)
			// A helper belongs to whatever was written immediately before it,
			// and a helper written before anything belongs to the turf.
			if(length(objects))
				var/list/owner = objects[length(objects)]
				owner["helpers"] += list(helper)
			else
				turf_helpers += list(helper)
			continue
		objects += list(list("path" = member_path, "vars" = member_vars, "helpers" = list()))
	// A no-op tile is a hole in the hull's bounding box, and a hole is written
	// by leaving the cell out rather than by describing it.
	if(!turf_path || ispath(turf_path, /turf/template_noop))
		return
	cells["[rel_x],[rel_y]"] = list(
		"objects" = objects,
		"turf_path" = turf_path,
		"turf_vars" = turf_vars,
		"turf_helpers" = turf_helpers,
		"area_path" = area_path || /area/template_noop,
	)

/// Where a saved hull lives on disk, sharded the way player saves are.
/proc/shipyard_ship_file_path(owner_ckey, ship_id)
	var/ckey_key = ckey(owner_ckey) || "unowned"
	return "data/player_ships/[copytext(ckey_key, 1, 2)]/[ckey_key]/[ship_id].dmm"

/// Write rendered TGM to disk. Returns the path written, or null.
/proc/shipyard_write_ship_file(map_text, file_path)
	if(!map_text || !file_path)
		return null
	rustg_file_write(map_text, file_path)
	return file_path

// --- Filing -----------------------------------------------------------------

/**
 * Why this hull cannot be filed away right now, or null when it can.
 *
 * Filing ends in `jumpToNullSpace()`, which calls `turf.empty(FALSE)` and so
 * qdels every living mob and every item that is not inside a lockbox. That makes
 * these checks the difference between putting a ship away and destroying one,
 * which is why they are refusals in their own right rather than warnings on the
 * way past. `/datum/ship_teardown` already refuses a hull under the printer or
 * one holding no areas; this adds what only matters because the hull is about to
 * stop existing.
 */
/proc/shipyard_file_refusal(obj/docking_port/mobile/port, obj/effect/landmark/overmap_landing_zone/zone)
	if(!istype(port))
		return "there is no registered hull to file"
	if(!length(port.shuttle_areas))
		return "the hull holds no shuttle areas"
	if(port.shipyard_build_claim?.resolve())
		return "the hull is still under a shipyard fabricator"
	var/obj/structure/overmap/ship/simulated/ship = port.current_ship
	if(ship && ship.state != OVERMAP_SHIP_IDLE)
		return "the vessel is under way and has to be docked before it can be filed"
	if(zone)
		var/list/coords = port.return_coords()
		var/contained = zone.contains_bbox(
			min(coords[1], coords[3]),
			min(coords[2], coords[4]),
			max(coords[1], coords[3]),
			max(coords[2], coords[4]),
			port.z,
		)
		if(!contained)
			return "the hull does not sit entirely inside the landing zone"
	for(var/turf/deck as anything in port.return_turfs())
		// The bounding box is not the hull: an irregular ship leaves tiles in
		// its own box that belong to whatever it is parked on.
		if(!port.shuttle_areas[deck.loc])
			continue
		// Recursive, because a mob inside a locker is still a mob that would be
		// deleted, and it is exactly the case nobody would think to check for.
		for(var/mob/living/aboard in deck.get_all_contents())
			return "[aboard] is still aboard"
	return null

/**
 * Write a described hull out to disk and take it out of the world.
 *
 * Split from the registry bookkeeping on purpose: this is the half that can be
 * exercised, and got wrong, without a database anywhere in sight. Returns the
 * path written, or null having touched neither the disk nor the ship.
 */
/proc/shipyard_write_and_release(obj/docking_port/mobile/port, datum/ship_teardown/teardown, file_path)
	if(!istype(port) || !istype(teardown) || !file_path)
		return null
	var/map_text = teardown.write_ship_tgm()
	if(!map_text)
		return null
	if(!shipyard_write_ship_file(map_text, file_path))
		return null
	// A hull's dock is transient by design: `create_shuttle()` leaves one behind
	// wherever a ship was printed, and a landing zone pad is built to be reaped
	// when its ship next departs. Filing is a departure, and nothing else will
	// collect them. Left alone they pile up one per cycle on the same tile, and
	// since `get_docked()` is just the first stationary port it finds there, the
	// ship starts answering with a phantom that carries no id at all.
	var/list/spent_docks = list()
	var/turf/port_tile = get_turf(port)
	for(var/obj/docking_port/stationary/dock in port_tile)
		if(dock.delete_after)
			spent_docks += dock
	// Only now, with the ship safely on disk. A failed write leaves the hull
	// standing, which is a retry; the reverse would be a loss.
	port.jumpToNullSpace()
	for(var/obj/docking_port/stationary/dock as anything in spent_docks)
		qdel(dock, force = TRUE)
	return file_path

// --- Reloading --------------------------------------------------------------

/**
 * A shuttle template built around a map path decided at runtime.
 *
 * `/datum/map_template/shuttle/New()` derives its own path from a compile-time
 * prefix and suffix, so a saved ship has nowhere to state where it lives. This
 * subtype exists to give it one; the parent now forwards a supplied path rather
 * than overwriting it, which is also why the admin shuttle-upload verb was
 * quietly ignoring the file it was handed.
 *
 * Deliberately has no `suffix`: that is what `preloadShuttleTemplates()` reads to
 * decide a template describes a shuttle shipped with the codebase, and this one
 * describes a ship that did not exist when the round started.
 */
/datum/map_template/shuttle/runtime
	name = "Retrieved Vessel"
	port_id = "runtime"

/datum/map_template/shuttle/runtime/New(path, rename, cache = TRUE)
	if(!path)
		CRASH("A runtime shuttle template needs a map path to load from.")
	. = ..()
	// One retrieval is one vessel: two of the same saved ship in a round must
	// not collide on an id, or registering the second unregisters the first.
	shuttle_id = "retrieved_[REF(src)]"

// --- Admin tooling ----------------------------------------------------------

ADMIN_VERB(ship_teardown, R_DEBUG, "Ship Teardown", "Write the shuttle you are standing on out as a .dmm.", ADMIN_CATEGORY_DEBUG)
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(user.mob)
	if(!port)
		to_chat(user, span_warning("You are not standing on a registered shuttle."))
		return
	var/datum/ship_teardown/teardown = new(port)
	if(teardown.refusal)
		to_chat(user, span_warning("Teardown refused: [teardown.refusal]"))
		return
	var/map_text = teardown.write_ship_tgm()
	if(!map_text)
		to_chat(user, span_warning("Teardown produced no map text."))
		return
	var/file_name = sanitize_filename("ship_teardown_[time2text(world.timeofday, "YYYY-MM-DD_hh-mm-ss", TIMEZONE_UTC)]")
	log_admin("[key_name(user)] tore down [port.name] ([port.shuttle_id]) to [file_name].dmm")
	for(var/line in teardown.report())
		to_chat(user, span_notice(line))
	send_exported_map(user, file_name, map_text)
