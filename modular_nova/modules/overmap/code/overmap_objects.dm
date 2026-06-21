// MODULE ID: OVERMAP
// Turfs, area, and base structure types living on the dedicated overmap Z.
// Concrete level subtypes (main, mining variants), ship subtypes, and event
// subtypes live in neighboring files.

/* OVERMAP TURFS */

/turf/open/overmap
	icon = 'modular_nova/modules/overmap/icons/overmap_turf.dmi'
	icon_state = "overmap"
	initial_gas_mix = AIRLESS_ATMOS
	baseturfs = /turf/open/overmap

/turf/open/overmap/edge
	opacity = TRUE
	density = TRUE
	baseturfs = /turf/open/overmap/edge

/// Decorative coordinate overlays at the grid's edge, ported from WS.
/turf/open/overmap/Initialize(mapload)
	. = ..()
	name = "[x]-[y]"
	if(!SSovermap)
		return
	var/list/numbers = list()
	if(x == 1 || x == SSovermap.size)
		numbers += list("[round(y/10)]","[round(y%10)]")
		if(y == 1 || y == SSovermap.size)
			numbers += "-"
	if(y == 1 || y == SSovermap.size)
		numbers += list("[round(x/10)]","[round(x%10)]")

	for(var/i in 1 to numbers.len)
		var/image/I = image('modular_nova/modules/overmap/icons/overmap_numbers.dmi', numbers[i])
		I.pixel_x = 5*i - 2
		I.pixel_y = world.icon_size/2 - 3
		if(y == 1)
			I.pixel_y = 3
			I.pixel_x = 5*i + 4
		if(y == SSovermap.size)
			I.pixel_y = world.icon_size - 9
			I.pixel_x = 5*i + 4
		if(x == 1)
			I.pixel_x = 5*i - 2
		if(x == SSovermap.size)
			I.pixel_x = 5*i + 2
		overlays += I

/* OVERMAP AREA */

/area/overmap
	name = "Overmap"
	icon_state = "yellow"
	requires_power = FALSE
	static_lighting = FALSE
	base_lighting_alpha = 255
	area_flags = NOTELEPORT
	flags_1 = NONE

/* OVERMAP STRUCTURES */

/// # Overmap objects
///
/// Everything visible on the overmap: stations, ships, and (post-prototype)
/// ruins, events, and dynamic encounters. Adjacency tracking uses
/// `on_overmap_crossed` / `on_overmap_uncrossed`; the same-tile list
/// close_overmap_objects is what helms surface in their radar and what
/// enables docking via act_overmap.
/obj/structure/overmap
	name = "overmap object"
	desc = "An unknown celestial object."
	icon = 'modular_nova/modules/overmap/icons/overmap.dmi'
	icon_state = "object"
	anchored = TRUE
	density = FALSE
	animate_movement = NO_STEPS
	/// Identifier - used to resolve docks and look the object up.
	var/id
	/// Whether this object should render a viewscreen-style camera surface.
	/// Levels and ships set this; events and decorations don't.
	var/render_map = FALSE
	/// Range of the view shown to helms / viewscreens of this object.
	var/sensor_range = 4
	/// Integrity percent. Use `receive_damage()` to mutate.
	var/integrity = 100
	/// Armor reduces integrity damage taken.
	var/overmap_armor = 1
	/// Other overmap objects sharing the same turf.
	var/list/close_overmap_objects
	/// Velocity X component in tiles/second (positive = east).
	var/vel_x = 0
	/// Velocity Y component in tiles/second (positive = north).
	var/vel_y = 0
	/// Earliest world.time we may rebuild cam_screen without `force`.
	var/next_screen_update = 0
	/// Admin diag: stay on SSfastprocess while stationary (no icon motion).
	var/diag_hold_physics = FALSE
	/// Fractional-tile position (tile units). Reconciled via Move(); rendered with pixel_x/y + animate.
	var/offset_x = 0
	var/offset_y = 0
	/// Offset at the start of the current physics tick (for animate interpolation).
	var/motion_last_offset_x = 0
	var/motion_last_offset_y = 0

	// Camera-surface plumbing. Initialized only if `render_map` is TRUE.
	// Modern Nova replaced WS' manual plane_master + background plumbing with
	// the `map_view/camera`-style subtype below: it carries its own
	// `cam_background` plane that `fill_rect`s the BYOND map widget so the
	// client knows how much screen real-estate to allocate. Without that
	// background the widget renders at minimum size (~2-3px); see CameraConsole
	// for the canonical reference of the same pattern.
	var/map_name
	var/atom/movable/screen/map_view/overmap/cam_screen

/obj/structure/overmap/Initialize(mapload, _id)
	. = ..()
	LAZYADD(SSovermap.overmap_objects, src)
	if(_id)
		id = _id
	if(!id)
		id = "overmap_object_[length(SSovermap.overmap_objects) + 1]"
	if(render_map)
		map_name = "overmap_[id]_map"
		cam_screen = new
		cam_screen.generate_view(map_name)
		update_screen(TRUE)

/obj/structure/overmap/Destroy()
	LAZYREMOVE(SSovermap.overmap_objects, src)
	STOP_PROCESSING(SSfastprocess, src)
	QDEL_NULL(cam_screen)
	return ..()

/obj/structure/overmap/process(seconds_per_tick)
	physics_tick(seconds_per_tick)

/obj/structure/overmap/Move(atom/newloc, direction, glide_size_override, update_dir)
	if(!newloc || newloc == loc)
		return FALSE
	if(!direction)
		direction = get_dir(src, newloc)
	if(!newloc.Enter(src))
		Bump(newloc)
		return FALSE
	var/atom/oldloc = loc
	loc = newloc
	oldloc.Exited(src, direction)
	newloc.Entered(src, oldloc)
	Moved(oldloc, direction)
	return TRUE

/obj/structure/overmap/Moved(atom/old_loc, direction, forced, list/old_locs, momentum_change)
	. = ..()
	if(old_loc && loc != old_loc)
		for(var/obj/structure/overmap/peer in old_loc)
			if(peer == src)
				continue
			peer.on_overmap_uncrossed(src, loc)
		for(var/obj/structure/overmap/peer in loc)
			if(peer == src)
				continue
			peer.on_overmap_crossed(src, old_loc)

/// Absolute pixel X on the overmap grid (tile anchor + fractional offset).
/obj/structure/overmap/proc/get_overmap_abs_px()
	return (x - 1) * ICON_SIZE_ALL + round(offset_x * ICON_SIZE_ALL)

/// Absolute pixel Y on the overmap grid (tile anchor + fractional offset).
/obj/structure/overmap/proc/get_overmap_abs_py()
	return (y - 1) * ICON_SIZE_ALL + round(offset_y * ICON_SIZE_ALL)

/// Zero fractional offset and snap visuals to the tile anchor (post-teleport / stop).
/obj/structure/overmap/proc/overmap_reset_visual_offset()
	offset_x = 0
	offset_y = 0
	step_x = 0
	step_y = 0
	motion_last_offset_x = 0
	motion_last_offset_y = 0
	pixel_x = 0
	pixel_y = 0
	animate(src, pixel_x = 0, pixel_y = 0, time = 0, flags = ANIMATION_END_NOW)

/// Reconcile fractional offsets with tile coordinates via Move(), spacepod-style.
/obj/structure/overmap/proc/reconcile_overmap_offsets()
	while((offset_x > 0 && vel_x > 0) || (offset_y > 0 && vel_y > 0) || (offset_x < 0 && vel_x < 0) || (offset_y < 0 && vel_y < 0))
		var/failed_x = FALSE
		var/failed_y = FALSE
		if(offset_x > 0 && vel_x > 0)
			if(!Move(get_step(src, EAST)))
				offset_x = 0
				failed_x = TRUE
				on_axis_blocked(EAST)
			else
				offset_x -= 1
				motion_last_offset_x -= 1
		else if(offset_x < 0 && vel_x < 0)
			if(!Move(get_step(src, WEST)))
				offset_x = 0
				failed_x = TRUE
				on_axis_blocked(WEST)
			else
				offset_x += 1
				motion_last_offset_x += 1
		else
			failed_x = TRUE
		if(offset_y > 0 && vel_y > 0)
			if(!Move(get_step(src, NORTH)))
				offset_y = 0
				failed_y = TRUE
				on_axis_blocked(NORTH)
			else
				offset_y -= 1
				motion_last_offset_y -= 1
		else if(offset_y < 0 && vel_y < 0)
			if(!Move(get_step(src, SOUTH)))
				offset_y = 0
				failed_y = TRUE
				on_axis_blocked(SOUTH)
			else
				offset_y += 1
				motion_last_offset_y += 1
		else
			failed_y = TRUE
		if(failed_x && failed_y)
			break
	if(abs(vel_x) < OVERMAP_VELOCITY_EPSILON)
		if(offset_x > 0.5)
			if(Move(get_step(src, EAST)))
				offset_x -= 1
				motion_last_offset_x -= 1
			else
				offset_x = 0
		if(offset_x < -0.5)
			if(Move(get_step(src, WEST)))
				offset_x += 1
				motion_last_offset_x += 1
			else
				offset_x = 0
	if(abs(vel_y) < OVERMAP_VELOCITY_EPSILON)
		if(offset_y > 0.5)
			if(Move(get_step(src, NORTH)))
				offset_y -= 1
				motion_last_offset_y -= 1
			else
				offset_y = 0
		if(offset_y < -0.5)
			if(Move(get_step(src, SOUTH)))
				offset_y += 1
				motion_last_offset_y += 1
			else
				offset_y = 0

/// Client-side glide for fractional motion; does not touch step_x/step_y.
/obj/structure/overmap/proc/apply_overmap_visual(dt)
	var/anim_time = max(dt * 10, 1)
	pixel_x = motion_last_offset_x * ICON_SIZE_ALL
	pixel_y = motion_last_offset_y * ICON_SIZE_ALL
	animate(src, transform = transform, pixel_x = offset_x * ICON_SIZE_ALL, pixel_y = offset_y * ICON_SIZE_ALL, time = anim_time, flags = ANIMATION_END_NOW)

/// Called when Move() fails along an axis during offset reconciliation.
/obj/structure/overmap/proc/on_axis_blocked(direction)
	return

/obj/structure/overmap/set_glide_size(target)
	return

/obj/structure/overmap/newtonian_move(inertia_angle, instant, start_delay, drift_force, controlled_cap, force_loop)
	return FALSE

/obj/structure/overmap/proc/cam_has_viewers()
	return cam_screen && length(cam_screen.viewers_to_huds)

/obj/structure/overmap/proc/update_screen(force = FALSE)
	if(!render_map || !cam_screen)
		return
	if(!force && !cam_has_viewers())
		return
	if(!force && world.time < next_screen_update)
		return
	next_screen_update = world.time + OVERMAP_SCREEN_UPDATE_INTERVAL
	var/list/visible_turfs = list()
	for(var/turf/T in view(sensor_range, src))
		visible_turfs += T
	if(!length(visible_turfs))
		// Off-grid (e.g. ship in CentCom-tier nullspace). Show static so the
		// widget still has visible dimensions instead of collapsing to ~0px.
		cam_screen.show_camera_static()
		return TRUE
	var/list/bbox = get_bbox_of_atoms(visible_turfs)
	var/size_x = bbox[3] - bbox[1] + 1
	var/size_y = bbox[4] - bbox[2] + 1
	cam_screen.show_camera(visible_turfs, size_x, size_y)
	return TRUE

/// Overmap map_view subtype, mirroring `/atom/movable/screen/map_view/camera`.
///
/// `cam_background` sits BELOW the turf vis_contents on the animated
/// `scanline2` state. Anywhere the visible turfs don't reach within the bbox
/// (opacity blockers, edge clipping, off-grid float) the CRT static shows
/// through - that's the WS-style "edge static" sensor fuzz, free of charge.
///
/// The sensor_range coupling is implicit: `update_screen()` sources its bbox
/// from `view(sensor_range, ...)`, so a smaller sensor produces a tighter
/// "clear" zone with proportionally more static visible at the edges.
///
/// Stale plane-group guard: if a previous helm open's `hide_from` cleanup
/// was bypassed (e.g. user briefly disconnected so `user.client` was null
/// when `ui_close` ran, skipping `cam_screen.hide_from(user)`), the popup
/// plane group can survive on the user's hud. The next open's parent
/// `attach_to()` would then fire a `Hey brother, our key ... is already in
/// use` runtime. We sniff for that case at the top of `display_to_client`
/// and reuse the existing group instead.
/atom/movable/screen/map_view/overmap
	var/atom/movable/screen/background/cam_background

/atom/movable/screen/map_view/overmap/Destroy()
	QDEL_NULL(cam_background)
	return ..()

/atom/movable/screen/map_view/overmap/generate_view(map_key)
	. = ..()
	cam_background = new
	cam_background.del_on_map_removal = FALSE
	cam_background.assigned_map = assigned_map

/atom/movable/screen/map_view/overmap/display_to_client(client/show_to)
	var/datum/hud/current_hud = show_to?.mob?.hud_used
	var/key = PLANE_GROUP_POPUP_WINDOW(src)
	if(current_hud?.master_groups[key])
		var/datum/plane_master_group/popup/existing = current_hud.master_groups[key]
		viewers_to_huds[WEAKREF(show_to)] = WEAKREF(current_hud)
		show_to.register_map_obj(cam_background)
		show_to.register_map_obj(src)
		return existing
	show_to.register_map_obj(cam_background)
	var/datum/plane_master_group/popup/pop_planes = ..()
	// Neutralize the lighting rendering plate on this popup so the
	// overmap renders fullbright. The area's base_lighting_alpha only
	// applies to the main hud's planes; popup plane groups don't
	// inherit it. Setting alpha=0 on the BLEND_MULTIPLY lighting plate
	// makes it transparent = no darkening.
	var/atom/movable/screen/plane_master/lighting_pm = pop_planes?.get_plane(RENDER_PLANE_LIGHTING)
	if(lighting_pm)
		lighting_pm.alpha = 0
	return pop_planes

/atom/movable/screen/map_view/overmap/hide_from(mob/hide_from)
	. = ..()

/// Render the live view: turfs in vis_contents, transparent background
/// just defines the popup widget bounds (turfs paint on FLOOR_PLANE which
/// is below GAME_PLANE — an opaque background would cover them).
/atom/movable/screen/map_view/overmap/proc/show_camera(list/visible_turfs, size_x, size_y)
	vis_contents = visible_turfs
	cam_background.icon_state = "clear"
	cam_background.fill_rect(1, 1, size_x, size_y)

/// Sized fallback rect of static when there's nothing visible (off-grid
/// ship). cam_background's `scanline2` state shows through wherever
/// vis_contents doesn't paint, giving us a visible widget instead of a
/// collapsed 0px popup.
/atom/movable/screen/map_view/overmap/proc/show_camera_static()
	vis_contents.Cut()
	cam_background.icon_state = "scanline2"
	cam_background.fill_rect(1, 1, 9, 9)

/// Adjacency tracking. Two overmap objects on the same tile know about each
/// other so the helm radar and dock-via-Act flow can find their neighbors.
/// Uses custom procs because `/atom/movable/Crossed` is not overridable.
/obj/structure/overmap/proc/on_overmap_crossed(obj/structure/overmap/other, atom/oldloc)
	if(!istype(loc, /turf) || !istype(other))
		return
	if(other == src)
		return
	LAZYADD(other.close_overmap_objects, src)
	LAZYADD(close_overmap_objects, other)

/obj/structure/overmap/proc/on_overmap_uncrossed(obj/structure/overmap/other, atom/newloc)
	if(!istype(loc, /turf) || !istype(other))
		return
	if(other == src)
		return
	LAZYREMOVE(other.close_overmap_objects, src)
	LAZYREMOVE(close_overmap_objects, other)

/obj/structure/overmap/proc/receive_damage(amount)
	integrity = max(integrity - (amount / overmap_armor), 0)

/// Integrates velocity into pixel displacement. Ticked by SSfastprocess via `process()`.
/obj/structure/overmap/proc/physics_tick(dt)
	var/atom/start_loc = loc
	if(abs(vel_x) < OVERMAP_VELOCITY_EPSILON && abs(vel_y) < OVERMAP_VELOCITY_EPSILON)
		if(!diag_hold_physics)
			deactivate_physics()
		return
	var/dx_tiles = vel_x * dt
	var/dy_tiles = vel_y * dt
	var/max_tile_delta = OVERMAP_INTERPOLATE_LIMIT / ICON_SIZE_ALL
	dx_tiles = clamp(dx_tiles, -max_tile_delta, max_tile_delta)
	dy_tiles = clamp(dy_tiles, -max_tile_delta, max_tile_delta)
	motion_last_offset_x = offset_x
	motion_last_offset_y = offset_y
	offset_x += dx_tiles
	offset_y += dy_tiles
	reconcile_overmap_offsets()
	if(loc != start_loc && cam_has_viewers())
		update_screen()

/// Begin SSfastprocess physics ticks for this entity.
/obj/structure/overmap/proc/activate_physics()
	if(render_map && cam_screen && cam_has_viewers())
		cam_screen.show_camera_static()
	START_PROCESSING(SSfastprocess, src)

/// Stop physics ticks and zero velocity.
/obj/structure/overmap/proc/deactivate_physics()
	diag_hold_physics = FALSE
	overmap_reset_visual_offset()
	vel_x = 0
	vel_y = 0
	if(render_map && cam_screen && cam_has_viewers())
		update_screen(TRUE)
	STOP_PROCESSING(SSfastprocess, src)

/* STAR — now defined in overmap_celestial.dm as /obj/structure/overmap/celestial/star */

// LEVELS (Z-linked, dockable). Concrete subtypes live in this same file.

/// Z-level linked overmap objects. Stations and mining sites are level
/// objects; ships dock at them via SSshuttle. The base type carries the
/// shared linkage machinery so M2's concrete subtypes (main, mining/lavaland,
/// mining/ice) can stay declarative.
/obj/structure/overmap/level
	/// Z-values this overmap tile maps to. Multi-Z mining maps populate
	/// this with all `ZTRAIT_MINING` levels so a single icon represents the
	/// entire body (Snowglobe, Icebox, etc).
	var/list/linked_levels
	/// If the shuttle nav console can change the docking location.
	var/custom_docking = TRUE
	render_map = TRUE

/obj/structure/overmap/level/Initialize(mapload, _id, list/_zs)
	if(_zs)
		LAZYADD(linked_levels, _zs)
	else if(!linked_levels)
		WARNING("Overmap level [src.type] initialized with no linked Z, deleting.")
		return INITIALIZE_HINT_QDEL
	. = ..()

// MAIN STATION POI

/// The station-bound overmap object. Created once per round, named after the
/// station, and tracked on `SSovermap.main` so name changes can be mirrored.
/obj/structure/overmap/level/main
	name = "Space Station 13"
	desc = "The local Nanotrasen-operated frontier station."
	icon_state = "station"
	id = MAIN_OVERMAP_OBJECT_ID
	sensor_range = 6

/obj/structure/overmap/level/main/Initialize(mapload, _id, list/_zs)
	if(SSovermap.main)
		WARNING("Multiple overmap /level/main spawned; deleting the duplicate.")
		return INITIALIZE_HINT_QDEL
	. = ..()
	SSovermap.main = src
	if(GLOB.station_name)
		name = GLOB.station_name

// MINING POI

/// Base mining body. Lavaland and Icebox subclasses only override flavor.
/// Multi-Z mining (Snowglobe) is collapsed via `linked_levels` so the
/// overmap shows one icon for the whole body.
/obj/structure/overmap/level/mining
	id = AWAY_OVERMAP_OBJECT_ID_MINING
	icon_state = "globe"
	sensor_range = 5

/obj/structure/overmap/level/mining/lavaland
	name = "Lavaland"
	desc = "A lava-covered planet known for its plentiful natural resources among dangerous fauna."
	color = COLOR_ORANGE

/obj/structure/overmap/level/mining/ice
	name = "Icemoon"
	desc = "A frozen planet, well known for its deep chasms and rivers of plasma."
	color = COLOR_BLUE_LIGHT

// ORBITAL STRUCTURE POIs

/// Medium orbital structure (mini-station). Intended to be subclassed per
/// installation. Its loaded map uses /area/overmap_structure/installation.
/obj/structure/overmap/level/installation
	name = "Orbital Installation"
	desc = "A mid-sized orbital facility."
	icon_state = "station"
	sensor_range = 5

/// Small orbital structure. Its loaded map uses /area/overmap_structure/depot.
/obj/structure/overmap/level/depot
	name = "Orbital Depot"
	desc = "A small orbital supply structure."
	icon_state = "object"
	sensor_range = 4
