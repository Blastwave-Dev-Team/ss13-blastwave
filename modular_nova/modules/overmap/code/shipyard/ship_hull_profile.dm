// MODULE ID: OVERMAP
// What a hull looks like on paper, read from its map file without loading it.
//
// The broker lists hulls nobody has built yet and the registrar shows hulls that
// are sitting on disk, so neither has live turfs to walk. Both read the same
// parse instead: a glyph grid for the schematic and the fittings the broker
// lists. A map file under
// data/player_ships is one immutable revision, and a stock map does not change
// during a round, so a profile is built once per path and kept.

// Schematic glyphs, the TGUI contract for `cells`.
#define HULL_GLYPH_FLOOR "."
#define HULL_GLYPH_WALL "#"
#define HULL_GLYPH_WINDOW "W"
#define HULL_GLYPH_AIRLOCK "A"
#define HULL_GLYPH_ENGINE "E"
#define HULL_GLYPH_INJECTOR "I"

/// map path -> /datum/hull_profile
GLOBAL_LIST_EMPTY(shipyard_hull_profiles)

/datum/hull_profile
	var/map_path
	var/width = 0
	var/height = 0
	var/tiles = 0
	/// Row-major, top row first, one glyph or null per footprint tile.
	var/list/cells = list()
	var/engines = 0
	/// Name of the first engine found, for the listing.
	var/engine_type = ""
	var/injectors = 0
	var/apcs = 0
	var/smes = 0
	var/airlocks = 0

/// The profile for a map file, parsed on first ask. Null when the file does not parse.
/proc/shipyard_hull_profile(map_path)
	if(!map_path)
		return null
	var/datum/hull_profile/profile = GLOB.shipyard_hull_profiles["[map_path]"]
	if(profile)
		return profile
	if(!fexists(map_path))
		return null
	var/datum/parsed_map/parsed = new(file(map_path))
	var/datum/ship_teardown/rebuilt = shipyard_teardown_from_parsed(parsed)
	if(rebuilt.refusal)
		qdel(rebuilt)
		return null
	profile = new()
	profile.map_path = "[map_path]"
	profile.read_cells(rebuilt)
	qdel(rebuilt)
	GLOB.shipyard_hull_profiles["[map_path]"] = profile
	return profile

/// Stock maps pad the hull out with space, so the footprint is cropped to what the
/// fabricator would actually build: every tile that is not space.
/datum/hull_profile/proc/read_cells(datum/ship_teardown/rebuilt)
	var/list/hull_cells = list()
	var/min_x = INFINITY
	var/min_y = INFINITY
	var/max_x = -INFINITY
	var/max_y = -INFINITY
	for(var/cell_key in rebuilt.cells)
		var/list/cell = rebuilt.cells[cell_key]
		if(ispath(cell["turf_path"], /turf/open/space))
			continue
		var/list/coords = splittext(cell_key, ",")
		var/cell_x = text2num(coords[1])
		var/cell_y = text2num(coords[2])
		min_x = min(min_x, cell_x)
		min_y = min(min_y, cell_y)
		max_x = max(max_x, cell_x)
		max_y = max(max_y, cell_y)
		hull_cells[cell_key] = cell
	if(!length(hull_cells))
		return
	width = max_x - min_x + 1
	height = max_y - min_y + 1
	for(var/rel_y in height to 1 step -1)
		for(var/rel_x in 1 to width)
			var/list/cell = hull_cells["[rel_x + min_x - 1],[rel_y + min_y - 1]"]
			if(!cell)
				cells += list(null)
				continue
			tiles++
			cells += read_glyph(cell)

/// Tally what stands on one tile, and return the glyph that best says what it is.
/datum/hull_profile/proc/read_glyph(list/cell)
	var/glyph = ispath(cell["turf_path"], /turf/closed) ? HULL_GLYPH_WALL : HULL_GLYPH_FLOOR
	for(var/list/member as anything in cell["objects"])
		var/member_path = member["path"]
		if(ispath(member_path, /obj/machinery/power/shuttle_engine))
			engines++
			if(!engine_type)
				var/obj/machinery/power/shuttle_engine/engine_path = member_path
				engine_type = initial(engine_path.name)
			glyph = HULL_GLYPH_ENGINE
		else if(ispath(member_path, /obj/machinery/overmap/fuel_injector))
			injectors++
			glyph = HULL_GLYPH_INJECTOR
		else if(ispath(member_path, /obj/machinery/door/airlock))
			airlocks++
			if(glyph != HULL_GLYPH_ENGINE && glyph != HULL_GLYPH_INJECTOR)
				glyph = HULL_GLYPH_AIRLOCK
		else if(ispath(member_path, /obj/machinery/power/apc))
			apcs++
		else if(ispath(member_path, /obj/machinery/power/smes))
			smes++
		else if(ispath(member_path, /obj/structure/window) || ispath(member_path, /obj/effect/spawner/structure/window))
			if(glyph == HULL_GLYPH_FLOOR)
				glyph = HULL_GLYPH_WINDOW
	return glyph

/// The schematic and fittings, in the shape the broker and registrar send.
/datum/hull_profile/proc/listing_data()
	return list(
		"width" = width,
		"height" = height,
		"tiles" = tiles,
		"cells" = cells,
		"engines" = list("count" = engines, "type" = engine_type),
		"injectors" = injectors,
		"apcs" = apcs,
		"smes" = smes,
		"airlocks" = airlocks,
	)

/// Just the footprint, for a garage slot's silhouette.
/datum/hull_profile/proc/silhouette_data()
	var/list/filled = list()
	for(var/glyph in cells)
		filled += glyph ? TRUE : FALSE
	return list("width" = width, "height" = height, "cells" = filled)

#undef HULL_GLYPH_FLOOR
#undef HULL_GLYPH_WALL
#undef HULL_GLYPH_WINDOW
#undef HULL_GLYPH_AIRLOCK
#undef HULL_GLYPH_ENGINE
#undef HULL_GLYPH_INJECTOR
