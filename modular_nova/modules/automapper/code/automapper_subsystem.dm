/**
 * The AUTOMAPPER
 *
 * This is a subsystem designed to make modular mapping far easier.
 *
 * It does two things: Loads maps from an automapper config and loads area spawn datums for simpler items.
 *
 * The benefits? We no longer need to have _nova maps and can have a more unique feeling map experience as each time, it can be different.
 *
 * Please note, this uses some black magic to interject the templates mid world load to prevent mass runtimes down the line.
 *
 * Station/mining/centcom stamps use trait Z + world-absolute coordinates.
 * Ruin-relative stamps (`load_templates_for_ruin`) use the ruin DMM origin and
 * optional `shuttle` ids so overmap/home hulls can spawn without mapped
 * `roundstart_template` docks.
 */

SUBSYSTEM_DEF(automapper)
	name = "Automapper"
	ss_flags = SS_NO_FIRE

	/// The path to our TOML file
	var/config_file = "_maps/nova/automapper/automapper_config.toml"
	/// Our loaded TOML file
	var/loaded_config
	/// Our preloaded map templates
	var/list/preloaded_map_templates = list()
	/// Ruin shuttle loads queued until SSshuttle is ready. seedRuins runs
	/// during SSmapping.Initialize, before the transit reservation Z exists,
	/// so action_load there CRASHes and leaves hangars empty.
	var/list/pending_ruin_shuttles = list()

/datum/controller/subsystem/automapper/Initialize()
	loaded_config = rustg_read_toml_file(config_file)
	return SS_INIT_SUCCESS

/**
 * This will preload our templates into a cache ready to be loaded later.
 *
 * IMPORTANT: This requires Z levels to exist in order to function, so make sure it is preloaded AFTER that.
 */
/datum/controller/subsystem/automapper/proc/preload_templates_from_toml(map_names)
	if(!islist(map_names))
		map_names = list(map_names)
	for(var/template in loaded_config["templates"])
		var/selected_template = loaded_config["templates"][template]
		var/required_map = selected_template["required_map"]

		// !builtin is a magic code for built in maps, ie CentCom levels.
		// We'll pretend it's loaded with the station z-level, because they by definition they are loaded before the station z-levels.
		var/requires_builtin = (required_map == AUTOMAPPER_MAP_BUILTIN) && ((SSmapping.current_map.map_file in map_names) || SSmapping.current_map.map_file == map_names)

		if(!requires_builtin && !(required_map in map_names))
			continue
		// Shuttle-on-ruin entries are applied after the ruin loads, not here.
		if(selected_template["shuttle"])
			continue

		var/list/coordinates = selected_template["coordinates"]
		if(LAZYLEN(coordinates) != 3)
			CRASH("Invalid coordinates for automap template [template]!")

		var/desired_z = SSmapping.levels_by_trait(selected_template["trait_name"])[coordinates[3]]

		var/turf/load_turf = locate(coordinates[1], coordinates[2], desired_z)

		if(!LAZYLEN(selected_template["map_files"]))
			CRASH("Could not find any valid map files for automap template [template]!")

		var/map_file = selected_template["directory"] + pick(selected_template["map_files"])

		if(!fexists(map_file))
			CRASH("[template] could not find map file [map_file]!")

		var/datum/map_template/automap_template/map = new(map_file, template, required_map, load_turf)
		if(selected_template["priority"])
			map.load_priority = selected_template["priority"]
		preloaded_map_templates += map

/**
 * Assuming we have preloaded our templates, this will load them from the cache.
 */
/datum/controller/subsystem/automapper/proc/load_templates_from_cache(map_names)
	if(!islist(map_names))
		map_names = list(map_names)
	sortTim(preloaded_map_templates, GLOBAL_PROC_REF(cmp_automap_template_priority))
	for(var/datum/map_template/automap_template/iterating_template as anything in preloaded_map_templates)
		if(iterating_template.affects_builtin_map && ((SSmapping.current_map.map_file in map_names) || SSmapping.current_map.map_file == map_names))
			// CentCom already started loading objects, place them in the netherzone
			for(var/turf/old_turf as anything in iterating_template.get_affected_turfs(iterating_template.load_turf, FALSE))
				init_contents(old_turf)
		else if(!(iterating_template.required_map in map_names))
			continue
		if(iterating_template.load(iterating_template.load_turf, FALSE))
			add_startup_message("Loaded [iterating_template.name] at [iterating_template.load_turf.x], [iterating_template.load_turf.y], [iterating_template.load_turf.z]!")
			log_world("AUTOMAPPER: Successfully loaded map template [iterating_template.name] at [iterating_template.load_turf.x], [iterating_template.load_turf.y], [iterating_template.load_turf.z]!")

/**
 * CentCom atoms aren't initialized but already exist, so must be properly initialized and then qdel'd.
 * Arguments:
 * * parent - parent turf
 */
/datum/controller/subsystem/automapper/proc/init_contents(atom/parent)
	var/static/list/mapload_args = list(TRUE)
	// Don't even initialize things in this list. Very specific edge cases.
	var/static/list/type_blacklist = typecacheof(list(
		/obj/docking_port/stationary,
		/obj/structure/bookcase,
		/obj/structure/closet,
		/obj/item/storage,
		/obj/item/reagent_containers,
	))

	var/previous_initialized_value = SSatoms.initialized
	SSatoms.initialized = INITIALIZATION_INNEW_MAPLOAD

	// Force everything to init as if INITIALIZE_IMMEDIATE was called on them.
	for(var/atom/atom_to_init as anything in parent.get_all_contents_ignoring(type_blacklist) - parent)
		if(atom_to_init.flags_1 & INITIALIZED_1)
			continue
		SSatoms.InitAtom(atom_to_init, FALSE, mapload_args)

	SSatoms.initialized = previous_initialized_value

	// NOW we can finally delete everything.
	for(var/atom/atom_to_del as anything in parent.get_all_contents() - parent)
		qdel(atom_to_del, TRUE)

/**
 * Get whether a given turf of the map template is a /turf/template_noop.
 *
 * You'd think there would be a better API way of doing this, but there is not.
 *
 * Arguments:
 * * map - The map_template we are looking at.
 * * x - The zero-based x coordinate RELATIVE to the map_template.
 * * y - The zero-based y coordinate RELATIVE to the map_template.
 */
/datum/controller/subsystem/automapper/proc/has_turf_noop(datum/map_template/map, x, y)
	// Row of the map grid.
	var/datum/grid_set/map_row = map.cached_map.gridSets[x + 1]
	// Note that Y is upside-down in the map data.
	// Which model, as in that key name in the map file, like pAK.
	var/modelID = map_row.gridLines[map.height - y]
	// Get the actual model text, ie the text of what's in this cell
	var/model = map.cached_map.grid_models[modelID]

	// If this doesn't work right, the map is horribly malformed and shoul fail,
	// Or you've map-edited template_noop which I'm fine with failing as well.
	return findtextEx(model, "/turf/template_noop,\n")

/**
 * This returns a list of turfs that have been preloaded and preselected using our templates.
 *
 * Not really useful outside of load groups.
 */
/datum/controller/subsystem/automapper/proc/get_turf_blacklists(map_names)
	if(!islist(map_names))
		map_names = list(map_names)

	var/list/blacklisted_turfs = list()
	for(var/datum/map_template/automap_template/iterating_template as anything in preloaded_map_templates)
		if(!(iterating_template.required_map in map_names))
			continue

		// Base of the coordinate system to introspect the templates.
		var/base_x = iterating_template.load_turf.x
		var/base_y = iterating_template.load_turf.y

		for(var/turf/blacklisted_turf as anything in iterating_template.get_affected_turfs(iterating_template.load_turf, FALSE))
			// Allow non-rectangular templates. Have to manually check the grid set since parsed_maps are not helpful for this.

			if(has_turf_noop(iterating_template, blacklisted_turf.x - base_x, blacklisted_turf.y - base_y))
				continue

			blacklisted_turfs[blacklisted_turf] = TRUE
	return blacklisted_turfs

/// Bottom-left turf of a DMM placed at `load_turf`. `centered` matches `map_template.load`.
/datum/map_template/proc/load_origin_turf(turf/load_turf, centered = FALSE)
	if(!load_turf)
		return null
	if(centered)
		return locate(load_turf.x - round(width / 2), load_turf.y - round(height / 2), load_turf.z)
	return load_turf

/// Stamp automapper templates whose `required_map` is this ruin's `suffix`.
/// Coordinates are 1-based SDMM coords on that DMM. `shuttle` entries call
/// `SSshuttle.action_load` instead of overlaying a frigate DMM.
/datum/controller/subsystem/automapper/proc/load_templates_for_ruin(datum/map_template/ruin/ruin, turf/origin)
	if(!ruin || !origin || !loaded_config)
		return
	var/map_name = ruin.suffix
	if(!map_name)
		return
	for(var/template in loaded_config["templates"])
		var/list/selected_template = loaded_config["templates"][template]
		if(selected_template["required_map"] != map_name)
			continue
		var/list/coordinates = selected_template["coordinates"]
		if(length(coordinates) < 2)
			stack_trace("Invalid coordinates for ruin automap template [template]!")
			continue
		var/turf/dest = locate(origin.x + coordinates[1] - 1, origin.y + coordinates[2] - 1, origin.z)
		if(!dest)
			stack_trace("Ruin automap template [template] dest turf out of bounds for [map_name]!")
			continue
		var/shuttle_id = selected_template["shuttle"]
		if(shuttle_id)
			load_ruin_shuttle(template, selected_template, dest)
			continue
		if(!length(selected_template["map_files"]))
			stack_trace("Ruin automap template [template] has neither shuttle nor map_files!")
			continue
		var/map_file = selected_template["directory"] + pick(selected_template["map_files"])
		if(!fexists(map_file))
			stack_trace("[template] could not find map file [map_file]!")
			continue
		var/datum/map_template/automap_template/stamp = new(map_file, template, map_name, dest)
		if(stamp.load(dest, FALSE))
			log_world("AUTOMAPPER: Loaded ruin template [template] at [AREACOORD(dest)] for [map_name]!")

/// Load a shuttle template onto a mapped port at `dest`, or a throwaway port.
/datum/controller/subsystem/automapper/proc/load_ruin_shuttle(template_name, list/selected_template, turf/dest)
	var/shuttle_id = selected_template["shuttle"]
	var/datum/map_template/shuttle/ship = SSmapping.shuttle_templates[shuttle_id]
	if(!ship)
		stack_trace("Ruin automap template [template_name] unknown shuttle id [shuttle_id]!")
		return
	var/obj/docking_port/stationary/port = locate() in dest
	if(!port)
		port = new()
		port.unregister()
		port.delete_after = TRUE
		if(selected_template["dir"])
			port.setDir(selected_template["dir"])
		if(selected_template["width"])
			port.width = selected_template["width"]
		if(selected_template["height"])
			port.height = selected_template["height"]
		if(!isnull(selected_template["dwidth"]))
			port.dwidth = selected_template["dwidth"]
		if(!isnull(selected_template["dheight"]))
			port.dheight = selected_template["dheight"]
		if(selected_template["shuttle_id"])
			port.shuttle_id = selected_template["shuttle_id"]
		port.name = template_name
		port.register(TRUE)
		port.forceMove(dest)
	if(!SSshuttle.initialized)
		pending_ruin_shuttles += list(list(
			"ship" = ship,
			"port" = port,
			"shuttle_id" = shuttle_id,
			"template_name" = template_name,
		))
		log_world("AUTOMAPPER: Queued shuttle [shuttle_id] at [AREACOORD(dest)] ([template_name]) until SSshuttle init!")
		return
	SSshuttle.action_load(ship, port)
	log_world("AUTOMAPPER: Loaded shuttle [shuttle_id] at [AREACOORD(dest)] ([template_name])!")

/// Run queued ruin shuttle loads. Called from SSshuttle.Initialize after
/// setup_shuttles, once the transit reservation Z exists.
/datum/controller/subsystem/automapper/proc/flush_pending_ruin_shuttles()
	for(var/list/entry as anything in pending_ruin_shuttles)
		var/datum/map_template/shuttle/ship = entry["ship"]
		var/obj/docking_port/stationary/port = entry["port"]
		var/shuttle_id = entry["shuttle_id"]
		var/template_name = entry["template_name"]
		if(QDELETED(port) || !ship)
			stack_trace("Ruin automap template [template_name] dropped queued shuttle [shuttle_id] (port or template missing)!")
			continue
		SSshuttle.action_load(ship, port)
		log_world("AUTOMAPPER: Loaded queued shuttle [shuttle_id] at [AREACOORD(port)] ([template_name])!")
	pending_ruin_shuttles.Cut()
