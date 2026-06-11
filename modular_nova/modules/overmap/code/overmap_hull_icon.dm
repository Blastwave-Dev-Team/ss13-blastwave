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
/// Cached minimap icon (higher-res, north-up) used by the systems console.
/obj/structure/overmap/ship/simulated/var/icon/cached_minimap_icon
/// Persisted hull layout bounds, set when the layout JSON is built. The systems
/// console uses these to inverse-map a clicked minimap region back to world
/// turf coordinates (the minimap is north-up, so the only transform is a Y-flip).
/obj/structure/overmap/ship/simulated/var/hull_min_x
/obj/structure/overmap/ship/simulated/var/hull_min_y
/obj/structure/overmap/ship/simulated/var/hull_grid_w
/obj/structure/overmap/ship/simulated/var/hull_grid_h

/// Returns the platform-specific native renderer library name, or null if the
/// library file isn't present next to the .dmb.
/obj/structure/overmap/ship/simulated/proc/get_hull_renderer_lib()
	var/lib_name = (world.system_type == MS_WINDOWS) ? "overmap_render.dll" : "libovermap_render.so"
	if(!fexists(lib_name))
		return null
	return lib_name

/// Build the JSON layout payload for the native hull renderer from the bound
/// shuttle's actual map turfs. Classifies turfs as "edge" (walls + exposed
/// floors) or "interior" (fully enclosed floors), and persists the layout
/// bounds (hull_min_x/min_y/grid_w/grid_h) on src so a clicked minimap region
/// can later be inverse-mapped to turfs. Returns the JSON string, or null if
/// the ship has no bound shuttle / areas. Shared by the token and minimap paths.
/obj/structure/overmap/ship/simulated/proc/build_hull_layout_json()
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

	// Persist bounds for the systems console's inverse-mapping.
	hull_min_x = min_x
	hull_min_y = min_y
	hull_grid_w = grid_w
	hull_grid_h = grid_h

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

	return json_encode(payload)

/// Generate a hull silhouette icon from the bound shuttle's actual map layout,
/// sends the layout to the native Rust renderer, and caches the result. Safe to
/// call multiple times — returns immediately if cached.
/obj/structure/overmap/ship/simulated/proc/generate_hull_icon()
	if(cached_hull_icon)
		return cached_hull_icon

	var/json = build_hull_layout_json()
	if(!json)
		return null

	var/lib_name = get_hull_renderer_lib()
	if(!lib_name)
		log_game("OVERMAP: Hull icon DLL not found — using default icon")
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

/// Generate the higher-resolution, north-up minimap icon used by the systems
/// console. Unlike the overmap token, this is not rotated 180° and is rendered
/// at up to MINIMAP_MAX_PX on its longer side. The native call returns a JSON
/// blob with the rendered PNG path plus coordinate metadata (grid_w/grid_h/
/// img_w/img_h/px_per_tile); the layout bounds needed for inverse-mapping are
/// persisted by build_hull_layout_json(). Cached for the round. Returns the
/// icon, or null on failure.
/obj/structure/overmap/ship/simulated/proc/generate_hull_minimap_icon()
	if(cached_minimap_icon)
		return cached_minimap_icon

	var/json = build_hull_layout_json()
	if(!json)
		return null

	var/lib_name = get_hull_renderer_lib()
	if(!lib_name)
		log_game("OVERMAP: Minimap DLL not found — no minimap available")
		return null

	var/result = call_ext(lib_name, "byond,await:generate_hull_minimap")(json)
	if(!result)
		log_game("OVERMAP: Minimap generation failed — Rust DLL returned null")
		return null

	var/list/meta = json_decode(result)
	if(!islist(meta) || !meta["path"])
		log_game("OVERMAP: Minimap generation failed — malformed metadata: [result]")
		return null

	var/png_path = meta["path"]
	if(!fexists(png_path))
		log_game("OVERMAP: Minimap generation failed — output file not found: [png_path]")
		return null

	var/icon/minimap = new(file(png_path))
	fdel(png_path)

	if(!minimap)
		log_game("OVERMAP: Minimap generation failed — could not create icon from result")
		return null

	cached_minimap_icon = minimap
	return cached_minimap_icon

/// Generate (if needed) the systems-console minimap, register it as a runtime
/// browser asset, optionally send it to a client, and return the display data a
/// TGUI console needs: the asset URL plus the persisted layout bounds used to
/// inverse-map a normalized click box back to world turfs. Returns null if no
/// minimap could be produced (e.g. the renderer DLL is missing).
///
/// Inverse mapping (north-up minimap, single Y-flip) for a normalized click
/// `(nx, ny)` with a top-left origin:
///   world_x = min_x + floor(nx * grid_w)
///   world_y = min_y + (grid_h - 1 - floor(ny * grid_h))
/obj/structure/overmap/ship/simulated/proc/get_minimap_ui_data(client/target)
	var/icon/minimap = generate_hull_minimap_icon()
	if(!minimap)
		return null

	var/asset_name = "overmap_minimap_[REF(src)].png"
	SSassets.transport.register_asset(asset_name, minimap)
	if(target)
		SSassets.transport.send_assets(target, asset_name)

	return list(
		"url" = SSassets.transport.get_asset_url(asset_name),
		"min_x" = hull_min_x,
		"min_y" = hull_min_y,
		"grid_w" = hull_grid_w,
		"grid_h" = hull_grid_h,
	)
