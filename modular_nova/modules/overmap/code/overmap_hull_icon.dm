// MODULE ID: OVERMAP
// Hull icon generation — iterates shuttle turfs, classifies edges vs interior,
// serializes layout as JSON, calls the native Rust DLL asynchronously, and
// receives back a rendered 32x32 PNG icon for use on the overmap.

// =============================================================================
// Init: configure the Rust renderer with RSC location and preferences
// =============================================================================

/// Called once at SSovermap init. Sends the RSC path (or URL) and game root
/// to the native DLL so it knows where to find icon data on a production
/// server where loose .dmi files may not exist.
/datum/controller/subsystem/overmap/proc/init_hull_renderer()
	var/lib_name
	if(world.system_type == MS_WINDOWS)
		lib_name = "overmap_render.dll"
	else
		lib_name = "libovermap_render.so"

	if(!fexists(lib_name))
		return

	var/list/init_payload = list()
	init_payload["game_root"] = "."
	// Use the existing external_rsc_urls config if available (CDN RSC),
	// otherwise fall back to the local .rsc file next to the .dmb.
	var/list/rsc_urls = CONFIG_GET(keyed_list/external_rsc_urls)
	if(length(rsc_urls))
		init_payload["rsc_path"] = rsc_urls[1]
	else
		init_payload["rsc_path"] = "tgstation.rsc"
	init_payload["prefer_rsc"] = (!fexists("icons/turf/walls.dmi"))

	var/result = call_ext(lib_name, "byond:init_render")(json_encode(init_payload))
	if(result == "OK")
		log_game("OVERMAP: Hull renderer initialized successfully")
	else
		log_game("OVERMAP: Hull renderer init returned: [result || "null"]")

/// Cached hull icon. Once generated, reused for the remainder of the round.
/obj/structure/overmap/ship/simulated/var/icon/cached_hull_icon

/// Generate a hull silhouette icon from the bound shuttle's actual map layout.
/// Classifies turfs as "edge" (walls + exposed floors) or "interior" (fully
/// enclosed floors), sends the layout to the native Rust renderer, and caches
/// the result. Safe to call multiple times — returns immediately if cached.
/obj/structure/overmap/ship/simulated/proc/generate_hull_icon()
	if(cached_hull_icon)
		return cached_hull_icon
	if(!shuttle)
		return null
	if(!length(shuttle.shuttle_areas))
		return null

	var/list/turfs_data = list()
	var/min_x = INFINITY
	var/min_y = INFINITY
	var/max_x = -INFINITY
	var/max_y = -INFINITY

	// Collect all shuttle area refs for fast membership checks
	var/list/shuttle_area_set = list()
	for(var/area/A as anything in shuttle.shuttle_areas)
		shuttle_area_set[A] = TRUE

	// First pass: find bounds
	for(var/area/shuttle_area as anything in shuttle.shuttle_areas)
		for(var/turf/T in shuttle_area)
			min_x = min(min_x, T.x)
			min_y = min(min_y, T.y)
			max_x = max(max_x, T.x)
			max_y = max(max_y, T.y)

	if(min_x == INFINITY)
		return null

	var/grid_w = max_x - min_x + 1
	var/grid_h = max_y - min_y + 1

	// Second pass: classify and collect turf data
	for(var/area/shuttle_area as anything in shuttle.shuttle_areas)
		for(var/turf/T in shuttle_area)
			var/rel_x = T.x - min_x
			var/rel_y = T.y - min_y
			var/is_edge = FALSE

			if(istype(T, /turf/closed))
				is_edge = TRUE
			else
				// Open turf: check if any cardinal neighbor is NOT in a shuttle area
				var/turf/north_t = get_step(T, NORTH)
				var/turf/south_t = get_step(T, SOUTH)
				var/turf/east_t = get_step(T, EAST)
				var/turf/west_t = get_step(T, WEST)

				if(!north_t || !shuttle_area_set[north_t.loc])
					is_edge = TRUE
				else if(!south_t || !shuttle_area_set[south_t.loc])
					is_edge = TRUE
				else if(!east_t || !shuttle_area_set[east_t.loc])
					is_edge = TRUE
				else if(!west_t || !shuttle_area_set[west_t.loc])
					is_edge = TRUE

			turfs_data += list(list(
				"icon" = "[T.icon]",
				"state" = T.icon_state,
				"dir" = T.dir,
				"x" = rel_x,
				"y" = rel_y,
				"edge" = is_edge,
			))

	// Build the JSON payload
	var/list/payload = list()
	payload["width"] = grid_w
	payload["height"] = grid_h
	payload["game_root"] = "."
	payload["rsc_path"] = "tgstation.rsc"
	payload["fill_color"] = list(26, 30, 46, 255)
	payload["turfs"] = turfs_data

	var/json = json_encode(payload)

	// Call the native Rust DLL asynchronously
	var/lib_name
	if(world.system_type == MS_WINDOWS)
		lib_name = "overmap_render.dll"
	else
		lib_name = "libovermap_render.so"

	if(!fexists(lib_name))
		log_game("OVERMAP: Hull icon DLL not found ([lib_name]) — using default icon")
		return null

	var/result = call_ext(lib_name, "byond,await:generate_hull")(json)

	if(!result)
		log_game("OVERMAP: Hull icon generation failed — Rust DLL returned null")
		return null

	// Result is an absolute file path to the rendered PNG
	if(!fexists(result))
		log_game("OVERMAP: Hull icon generation failed — output file not found: [result]")
		return null

	var/icon/hull = new(file(result))
	fdel(result)

	if(!hull)
		log_game("OVERMAP: Hull icon generation failed — could not create icon from result")
		return null

	cached_hull_icon = hull
	// Apply immediately
	icon = cached_hull_icon
	icon_state = ""
	return cached_hull_icon
