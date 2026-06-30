// MODULE ID: OVERMAP
// Overmap ships. The base type is purely positional and animation-related;
// the simulated subtype is bound to a real `/obj/docking_port/mobile` and
// tracks the shuttle's Z so the ship icon stays in sync when the shuttle is
// moved by ANY system (helm, in-shuttle console, admin VV, etc).

/// Anything on the overmap that's capable of self-propelled motion.
/obj/structure/overmap/ship
	name = "overmap vessel"
	desc = "A spacefaring vessel."
	icon = 'modular_nova/modules/overmap/icons/overmap.dmi'
	icon_state = "ship"
	base_icon_state = "ship"

	/// Max speed in tiles/second.
	var/max_speed = OVERMAP_MAX_SPEED
	/// Desired heading angle in degrees (0=east, 90=north, math convention).
	var/desired_angle = 0
	/// Desired throttle 0..1 (fraction of max_speed).
	var/desired_throttle = 0
	/// Whether a heading has been set (FALSE = drifting/stopped).
	var/has_heading = FALSE
	/// Station-keeping mode active.
	var/station_keeping = FALSE
	/// Ship control flags (SHIP_CONTROL_CONSOLE, SHIP_CONTROL_DIRECT).
	var/control_flags = SHIP_CONTROL_CONSOLE

/obj/structure/overmap/ship/Destroy()
	LAZYREMOVE(SSovermap.simulated_ships, src)
	STOP_PROCESSING(SSfastprocess, src)
	return ..()

/// Whether the ship is effectively stationary.
/obj/structure/overmap/ship/proc/is_still()
	return abs(vel_x) < OVERMAP_VELOCITY_EPSILON && abs(vel_y) < OVERMAP_VELOCITY_EPSILON

/// Whether any gravity well is currently influencing this ship.
/obj/structure/overmap/ship/proc/has_gravity_influence()
	var/ship_px = get_overmap_abs_px()
	var/ship_py = get_overmap_abs_py()
	for(var/obj/structure/overmap/celestial/body as anything in SSovermap.gravity_wells)
		var/dx = body.px - ship_px
		var/dy = body.py - ship_py
		if(dx * dx + dy * dy <= body.soi_sq)
			return TRUE
	return FALSE

/// Current speed magnitude in tiles/second.
/obj/structure/overmap/ship/proc/get_speed()
	return sqrt(vel_x * vel_x + vel_y * vel_y)

/// Heading in degrees (0-359, 0=north clockwise) from velocity vector.
/obj/structure/overmap/ship/proc/get_heading_degrees()
	if(is_still())
		return 0
	var/angle_rad = arctan(vel_x, vel_y)
	var/degrees = angle_rad
	if(degrees < 0)
		degrees += 360
	return round(degrees)

/// Heading bitfield from current velocity components (for icon direction).
/obj/structure/overmap/ship/proc/get_heading()
	var/direction = 0
	if(abs(vel_x) >= OVERMAP_VELOCITY_EPSILON)
		if(vel_x > 0)
			direction |= EAST
		else
			direction |= WEST
	if(abs(vel_y) >= OVERMAP_VELOCITY_EPSILON)
		if(vel_y > 0)
			direction |= NORTH
		else
			direction |= SOUTH
	return direction

/// Set the desired heading and throttle. Called from helm UI act("set_desired").
/// angle is in degrees (math convention: 0=east, 90=north).
/obj/structure/overmap/ship/proc/set_desired(angle, throttle)
	desired_angle = angle
	desired_throttle = clamp(throttle, 0, 1)
	has_heading = desired_throttle > 0.01
	if(has_heading && is_still())
		activate_physics()

/// All-stop: zero throttle, clear heading, and begin braking.
/// Braking rate is proportional to thrust/mass — light ships with good
/// engines stop fast, heavy ships take longer.
/obj/structure/overmap/ship/proc/all_stop()
	desired_throttle = 0
	has_heading = FALSE
	station_keeping = FALSE

/// Apply braking deceleration toward zero velocity. Called each physics_tick
/// when has_heading is FALSE and ship is not yet still.
/// Deceleration is derived purely from thrust/mass — no static constant.
/obj/structure/overmap/ship/proc/apply_braking(dt)
	var/effective_thrust = 20
	var/effective_mass = 1
	if(istype(src, /obj/structure/overmap/ship/simulated))
		var/obj/structure/overmap/ship/simulated/sim = src
		effective_thrust = max(sim.est_thrust, 10)
		effective_mass = max(sim.mass, 1)
	var/brake_rate = (effective_thrust / effective_mass) * dt
	var/speed = get_speed()
	if(speed <= brake_rate)
		vel_x = 0
		vel_y = 0
	else
		var/scale = (speed - brake_rate) / speed
		vel_x *= scale
		vel_y *= scale

/// Apply thrust in a given 8-direction. Converts direction to angle, sets
/// desired heading and throttle. Used by legacy console directional buttons
/// and relaymove from pilot link.
/obj/structure/overmap/ship/proc/burn_direction(direction, thrust_fraction = 1)
	if(!direction)
		return
	var/angle = dir_to_physics_angle(direction)
	desired_angle = angle
	desired_throttle = clamp(thrust_fraction, 0, 1)
	has_heading = TRUE
	if(is_still())
		activate_physics()

/// Physics integration. Applies thrust toward desired velocity, integrates
/// position. Called by SSfastprocess via `process()` each tick.
/obj/structure/overmap/ship/physics_tick(dt)
	if(!has_heading && is_still() && !has_gravity_influence())
		deactivate_physics()
		update_icon_state()
		return

	if(has_heading)
		var/target_vx = cos(desired_angle) * desired_throttle * max_speed
		var/target_vy = sin(desired_angle) * desired_throttle * max_speed
		var/maneuver = OVERMAP_MANEUVERABILITY * dt
		vel_x += (target_vx - vel_x) * min(maneuver, 1)
		vel_y += (target_vy - vel_y) * min(maneuver, 1)
	else
		apply_braking(dt)

	// Gravity pass: apply gravitational acceleration from nearby bodies
	var/ship_px = get_overmap_abs_px()
	var/ship_py = get_overmap_abs_py()
	for(var/obj/structure/overmap/celestial/body as anything in SSovermap.gravity_wells)
		var/dx = body.px - ship_px
		var/dy = body.py - ship_py
		var/dist_sq = dx * dx + dy * dy
		if(dist_sq > body.soi_sq || dist_sq < 1)
			continue
		var/dist = sqrt(dist_sq)
		var/accel = body.gravity_mass / dist_sq
		// Convert pixel-space accel to tiles/second velocity change
		vel_x += (dx / dist) * accel * dt / ICON_SIZE_ALL
		vel_y += (dy / dist) * accel * dt / ICON_SIZE_ALL

	// Station-keeping autopilot
	if(station_keeping)
		apply_station_keeping(dt)

	var/speed = get_speed()
	if(speed > max_speed)
		var/scale = max_speed / speed
		vel_x *= scale
		vel_y *= scale

	if(is_still() && !has_heading)
		deactivate_physics()
		update_icon_state()
		return

	..()
	update_icon_state()
	apply_overmap_visual(dt)

/// Handle blocked movement by zeroing velocity on the blocked axis.
/obj/structure/overmap/ship/on_axis_blocked(direction)
	switch(direction)
		if(EAST, WEST)
			vel_x = 0
		if(NORTH, SOUTH)
			vel_y = 0
	if(is_still())
		has_heading = FALSE

/// Convert a BYOND 8-dir to physics angle in degrees (math convention: 0=east, 90=north).
/obj/structure/overmap/ship/proc/dir_to_physics_angle(dir)
	switch(dir)
		if(EAST)
			return 0
		if(NORTH)
			return 90
		if(WEST)
			return 180
		if(SOUTH)
			return 270
		if(NORTHEAST)
			return 45
		if(NORTHWEST)
			return 135
		if(SOUTHWEST)
			return 225
		if(SOUTHEAST)
			return 315
	return 0

/obj/structure/overmap/ship/update_icon_state()
	// If we have a dynamic hull icon, use it directly (skip icon_state logic)
	var/obj/structure/overmap/ship/simulated/sim = istype(src, /obj/structure/overmap/ship/simulated) ? src : null
	if(sim?.cached_hull_icon)
		if(icon != sim.cached_hull_icon)
			icon = sim.cached_hull_icon
			icon_state = ""
		if(!is_still())
			var/face_angle = has_heading ? desired_angle : arctan(vel_x, vel_y)
			var/rotation = 270 - face_angle
			var/matrix/M = matrix()
			M.Turn(rotation)
			transform = M
		else
			transform = matrix()
		return ..()

	if(!is_still())
		icon_state = "[base_icon_state]_moving"
		var/face_angle = has_heading ? desired_angle : arctan(vel_x, vel_y)
		var/rotation = 270 - face_angle
		var/matrix/M = matrix()
		M.Turn(rotation)
		transform = M
	else
		icon_state = base_icon_state
		transform = matrix()
	if(integrity < initial(integrity) / 4)
		icon_state = "[icon_state]_damaged"
	return ..()

// SIMULATED SHIP - bound to a real shuttle docking port.

#define SHIP_SIZE_THRESHOLD 300
#define SHIP_DOCKED_REPAIR_TIME (2 SECONDS)

/// A ship icon that corresponds to a real `/obj/docking_port/mobile`. Tracks
/// the shuttle's Z; when the shuttle teleports between Zs (by any means),
/// `check_loc()` resnaps the icon to the matching overmap level.
/obj/structure/overmap/ship/simulated
	render_map = TRUE

	/// IDLE / FLYING / DOCKING / UNDOCKING.
	var/state = OVERMAP_SHIP_IDLE
	/// The overmap object the ship is currently parked at, if any.
	var/obj/structure/overmap/docked
	/// The bound mobile docking port this icon represents.
	var/obj/docking_port/mobile/shuttle
	/// Estimated thrust from the shuttle's engine_list.
	var/est_thrust
	/// Approximate mass derived from `shuttle.shuttle_areas` turf count.
	var/mass
	/// Average percent fullness across the shuttle's enabled engines.
	var/avg_fuel_amnt = 100
	/// Objects detected by active radar scan. Assoc list: weakref -> timer_id.
	var/list/scanned_objects
	/// Cooldown on active radar sweeps.
	COOLDOWN_DECLARE(scan_cooldown)
	/// TRUE while batched injector fuel burns are being processed this tick.
	var/processing_fuel_batch = FALSE
	/// Pending nav-camera docking target (written by helm `dock()`, read by nav console on open).
	var/obj/structure/overmap/nav_dock_target
	/// Z-levels the nav camera should display for the pending target.
	var/list/nav_dock_zs
	/// Stationary dock IDs relevant to the pending target (for jump-to-location in the nav UI).
	var/list/nav_dock_ids

/obj/structure/overmap/ship/simulated/Initialize(mapload, _id, obj/docking_port/mobile/_shuttle)
	. = ..()
	LAZYADD(SSovermap.simulated_ships, src)
	if(_shuttle)
		shuttle = _shuttle
	if(!shuttle && id)
		shuttle = SSshuttle.getShuttle(id)
	if(shuttle)
		name = shuttle.name
	if(istype(loc, /obj/structure/overmap))
		docked = loc
	addtimer(CALLBACK(src, PROC_REF(scan)), 1 SECONDS)

/// Idempotently apply the post-undock state machine: mass + engines + fuel
/// recomputed, icon refreshed, hull silhouette generated.
/obj/structure/overmap/ship/simulated/proc/prepare_for_flight()
	calculate_mass()
	refresh_engines()
	calculate_avg_fuel()
	// Hull icon generation is async (sleeps while Rust DLL processes).
	// Spawn it so it doesn't block the undock flow.
	INVOKE_ASYNC(src, PROC_REF(generate_hull_icon))
	update_screen(TRUE)

/obj/structure/overmap/ship/simulated/Destroy()
	if(shuttle?.current_ship == src)
		shuttle.current_ship = null
	shuttle = null
	docked = null
	nav_dock_target = null
	nav_dock_zs = null
	nav_dock_ids = null
	return ..()

/// Write the pending docking target so the nav console can read it lazily.
/// Called by `dock()` when no automatic stationary port is found.
/obj/structure/overmap/ship/simulated/proc/set_nav_target(obj/structure/overmap/target, list/zs, list/dock_ids)
	nav_dock_target = target
	nav_dock_zs = zs?.Copy()
	nav_dock_ids = dock_ids?.Copy()

/// Override physics_tick: if docked, do nothing. If out of fuel, decay.
/obj/structure/overmap/ship/simulated/physics_tick(dt)
	if(docked || state != OVERMAP_SHIP_FLYING)
		all_stop()
		deactivate_physics()
		return
	calculate_avg_fuel()
	if(avg_fuel_amnt < 1)
		desired_throttle = max(desired_throttle - 0.1 * dt, 0)
	if(desired_throttle > 0.01)
		refresh_engines()
		var/burn_pct = desired_throttle * 100 * dt * 10
		process_engine_fuel_burns(burn_pct)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
			if(!engine.enabled || !engine.thruster_active)
				continue
			var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
			if(injector?.has_propellant())
				continue
			engine.burn_engine(burn_pct, skip_engine_update = TRUE)
			engine.burning = FALSE
	..()

/// Batch chamber burns for injector-fed engines grouped by fuel injector.
/obj/structure/overmap/ship/simulated/proc/process_engine_fuel_burns(burn_pct)
	if(!shuttle)
		return list()
	var/list/by_injector = list()
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.enabled || !engine.thruster_active)
			continue
		var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
		if(!injector?.has_propellant())
			continue
		LAZYADD(by_injector[injector], engine)
	if(!length(by_injector))
		return list()
	processing_fuel_batch = TRUE
	var/list/all_thrust = list()
	for(var/obj/machinery/overmap/fuel_injector/injector as anything in by_injector)
		var/list/thrust_results = injector.process_tick_burn(by_injector[injector], burn_pct)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in thrust_results)
			all_thrust[engine] = thrust_results[engine]
			engine.burning = FALSE
	processing_fuel_batch = FALSE
	return all_thrust

/// Resync the ship icon's overmap position with whatever Z the bound shuttle
/// currently occupies. Called from M3's `shuttle_move` NOVA EDIT after every
/// `initiate_docking`, so any non-overmap shuttle move (in-shuttle console,
/// admin recall, etc) keeps the icon honest.
/obj/structure/overmap/ship/simulated/proc/check_loc()
	if(!shuttle)
		return
	// If we're mid-transition, don't interfere with the state machine.
	if(state == OVERMAP_SHIP_DOCKING || state == OVERMAP_SHIP_UNDOCKING)
		// If docking and the shuttle has actually arrived (mode is IDLE), finalize.
		if(state == OVERMAP_SHIP_DOCKING && shuttle.mode == SHUTTLE_IDLE)
			complete_dock()
		return
	var/obj/structure/overmap/level/docked_object = SSovermap.get_overmap_object_by_z(shuttle.z)
	if(docked_object == loc)
		return TRUE
	if(!docked_object && !docked)
		return TRUE
	// If currently docked at a dynamic encounter whose reservation holds this Z, stay put.
	if(docked && istype(docked, /obj/structure/overmap/dynamic))
		var/obj/structure/overmap/dynamic/enc = docked
		if(enc.reserve)
			var/turf/bl = enc.reserve.bottom_left_turfs[1]
			if(bl && bl.z == shuttle.z)
				return TRUE
	if(docked && !docked_object)
		var/turf/free_tile = SSovermap.get_unused_overmap_square()
		if(free_tile)
			forceMove(free_tile)
		docked = null
		state = OVERMAP_SHIP_FLYING
		update_screen(TRUE)
		return FALSE
	if(!docked && docked_object)
		overmap_reset_visual_offset()
		forceMove(docked_object)
		docked = docked_object
		state = OVERMAP_SHIP_IDLE
		all_stop()
		update_screen(TRUE)
		return FALSE

/// Approximate ship mass from the bound shuttle's area turf count.
/obj/structure/overmap/ship/simulated/proc/calculate_mass()
	if(!shuttle)
		mass = 0
		return
	var/total = 0
	for(var/area/shuttle_area as anything in shuttle.shuttle_areas)
		total += length(get_area_turfs(shuttle_area))
	mass = total
	update_icon_state()

/// Sum thrust from currently enabled, fueled engines on the bound shuttle.
/obj/structure/overmap/ship/simulated/proc/refresh_engines()
	if(!shuttle)
		est_thrust = 0
		return
	var/calc = 0
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		engine.update_engine()
		if(engine.enabled && engine.thruster_active)
			calc += engine.thrust
	est_thrust = calc

/// Average percent fullness across enabled engines.
/obj/structure/overmap/ship/simulated/proc/calculate_avg_fuel()
	if(!shuttle)
		avg_fuel_amnt = 0
		return
	var/sum = 0
	var/count = 0
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.enabled)
			continue
		var/cap = engine.return_fuel_cap()
		if(!cap)
			continue
		sum += engine.return_fuel() / cap
		count++
	avg_fuel_amnt = count ? round(sum / count * 100) : 0

/// Burn engines in `n_dir`. Converts thrust into a desired heading/throttle.
/// With no `n_dir`, applies braking.
/obj/structure/overmap/ship/simulated/proc/burn_engines(n_dir = null, percentage = 100)
	if(state != OVERMAP_SHIP_FLYING)
		return
	refresh_engines()
	if(!mass)
		calculate_mass()
	calculate_avg_fuel()
	var/thrust_used = 0
	var/list/by_injector = list()
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.enabled)
			continue
		var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
		if(injector?.has_propellant())
			LAZYADD(by_injector[injector], engine)
			continue
		thrust_used += engine.burn_engine(percentage)
	if(length(by_injector))
		processing_fuel_batch = TRUE
		for(var/obj/machinery/overmap/fuel_injector/injector as anything in by_injector)
			var/list/thrust_results = injector.process_tick_burn(by_injector[injector], percentage)
			for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in thrust_results)
				thrust_used += thrust_results[engine]
		processing_fuel_batch = FALSE
	est_thrust = thrust_used
	if(n_dir)
		burn_direction(n_dir, clamp(percentage / 100, 0, 1))
	else
		all_stop()

/// Detach the ship from its current docked overmap object and start flight.
/obj/structure/overmap/ship/simulated/proc/undock()
	if(!shuttle)
		return "Shuttle not found!"
	if(state != OVERMAP_SHIP_IDLE)
		return "Ship is not docked!"
	if(!docked)
		check_loc()
		return "Ship not docked!"
	all_stop()
	prepare_for_flight()
	if(avg_fuel_amnt <= 0)
		return "Engines have no fuel!"
	shuttle.destination = null
	shuttle.mode = SHUTTLE_IGNITING
	shuttle.setTimer(shuttle.ignitionTime)
	addtimer(CALLBACK(src, PROC_REF(complete_undock)), shuttle.ignitionTime + (1 SECONDS))
	state = OVERMAP_SHIP_UNDOCKING
	return "Beginning undocking procedures..."

/// Called when the shuttle's ignition timer elapses.
/obj/structure/overmap/ship/simulated/proc/complete_undock()
	if(state != OVERMAP_SHIP_UNDOCKING)
		return
	var/obj/structure/overmap/prev_docked = docked
	if(docked)
		forceMove(get_turf(docked))
		docked = null
	state = OVERMAP_SHIP_FLYING
	update_screen(TRUE)
	if(istype(prev_docked, /obj/structure/overmap/dynamic))
		var/obj/structure/overmap/dynamic/encounter = prev_docked
		encounter.unload_level()

/// Helm "Act" entry point.
/obj/structure/overmap/ship/simulated/proc/overmap_object_act(obj/structure/overmap/target, mob/user)
	if(!target)
		return "No target."
	if(state != OVERMAP_SHIP_FLYING)
		return "Ship must be in flight to interact."
	if(!is_still())
		return "Ship must be stopped to interact."
	if(!(target in close_overmap_objects))
		return "Target not in range. Move closer first."
	if(istype(target, /obj/structure/overmap/dynamic))
		var/obj/structure/overmap/dynamic/encounter = target
		var/error = encounter.load_level(shuttle)
		if(error)
			return error
		return dock(encounter)
	if(istype(target, /obj/structure/overmap/level))
		return dock(target)
	return "Cannot interact with this object yet."

/// Try to resolve a stationary docking port for `target` and request the
/// shuttle to fly to it.
/obj/structure/overmap/ship/simulated/proc/dock(obj/structure/overmap/target)
	if(state != OVERMAP_SHIP_FLYING)
		return "Ship is not in flight."
	if(!is_still())
		return "Ship must be stopped to dock."
	if(!shuttle)
		return "Shuttle not found."
	if(!SSovermap.can_view_installation(src, target))
		return "Unable to establish docking link with target."

	var/list/candidates = list(
		"[shuttle.shuttle_id]_[target.id]",
		"[OVERMAP_DOCK_PREFIX]_[target.id]",
	)
	if(istype(target, /obj/structure/overmap/level/main))
		candidates += "[shuttle.shuttle_id]_home"
	if(istype(target, /obj/structure/overmap/level/mining))
		candidates += "[shuttle.shuttle_id]_away"
	if(istype(target, /obj/structure/overmap/dynamic))
		candidates += "[OVERMAP_FERRY_PREFIX]_[target.id]"

	var/obj/docking_port/stationary/picked
	for(var/dock_id in candidates)
		var/obj/docking_port/stationary/found = SSshuttle.getDock(dock_id)
		if(!found)
			continue
		if(!shuttle.check_dock(found, TRUE))
			continue
		picked = found
		break

	if(!picked)
		var/list/target_zs = resolve_nav_target_zs(target)
		set_nav_target(target, target_zs, candidates)
		return "No automatic dock found - use the navigation computer to designate a landing pad on [target.name]."

	docked = target
	state = OVERMAP_SHIP_DOCKING
	shuttle.request(picked)
	var/transit_time = shuttle.ignitionTime + (shuttle.callTime * shuttle.engine_coeff) + (3 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(complete_dock)), transit_time)
	return "Commencing docking at [target.name]..."

/// Derive the real Z-levels for a docking target so the nav camera can open there.
/obj/structure/overmap/ship/simulated/proc/resolve_nav_target_zs(obj/structure/overmap/target)
	if(istype(target, /obj/structure/overmap/level))
		var/obj/structure/overmap/level/level_target = target
		return level_target.linked_levels?.Copy()
	if(istype(target, /obj/structure/overmap/dynamic))
		var/obj/structure/overmap/dynamic/encounter = target
		if(encounter.reserve)
			var/turf/bl = encounter.reserve.bottom_left_turfs?[1]
			if(bl)
				return list(bl.z)
		if(encounter.reserve_dock)
			return list(encounter.reserve_dock.z)
	return list()

/// Snap icon onto docked overmap object and return to idle.
/obj/structure/overmap/ship/simulated/proc/complete_dock()
	if(state != OVERMAP_SHIP_DOCKING)
		return
	if(docked)
		overmap_reset_visual_offset()
		forceMove(docked)
	state = OVERMAP_SHIP_IDLE
	all_stop()
	scanned_objects = null
	set_nav_target(null, null, null)
	update_screen(TRUE)

/// Active radar sweep. Finds all overmap objects within sensor_range using
/// pixel-distance (accounts for sub-tile positions from pixel movement).
/obj/structure/overmap/ship/simulated/proc/scan()
	if(!COOLDOWN_FINISHED(src, scan_cooldown))
		return 0
	COOLDOWN_START(src, scan_cooldown, OVERMAP_SCAN_COOLDOWN)
	var/scan_px = sensor_range * ICON_SIZE_ALL
	var/scan_sq = scan_px * scan_px
	var/my_px = get_overmap_abs_px()
	var/my_py = get_overmap_abs_py()
	var/count = 0
	for(var/obj/structure/overmap/other as anything in SSovermap.overmap_objects)
		if(other == src || QDELETED(other))
			continue
		if(other.z != z)
			continue
		var/dx = other.get_overmap_abs_px() - my_px
		var/dy = other.get_overmap_abs_py() - my_py
		if(dx * dx + dy * dy > scan_sq)
			continue
		if(!SSovermap.can_view_installation(src, other))
			continue
		var/ref = REF(other)
		if(LAZYACCESS(scanned_objects, ref))
			deltimer(scanned_objects[ref])
		var/timer_id = addtimer(CALLBACK(src, PROC_REF(expire_scan), ref), OVERMAP_SCAN_DECAY, TIMER_STOPPABLE)
		LAZYSET(scanned_objects, ref, timer_id)
		count++
	return count

/// Remove a scanned contact when its decay timer elapses.
/obj/structure/overmap/ship/simulated/proc/expire_scan(ref)
	LAZYREMOVE(scanned_objects, ref)

// --- Ship class subtypes with preset control_flags ---

/// Fighter: direct piloting only (NIF or neurohelm). No helm console.
/obj/structure/overmap/ship/simulated/fighter
	control_flags = SHIP_CONTROL_DIRECT
	max_speed = OVERMAP_MAX_SPEED * 1.5

/// Frigate: purpose-built overmap ship. Supports both helm console and
/// direct piloting.
/obj/structure/overmap/ship/simulated/frigate
	control_flags = SHIP_CONTROL_CONSOLE | SHIP_CONTROL_DIRECT

/// Capital / military: supports both console and direct piloting.
/obj/structure/overmap/ship/simulated/capital
	control_flags = SHIP_CONTROL_CONSOLE | SHIP_CONTROL_DIRECT

#undef SHIP_SIZE_THRESHOLD
#undef SHIP_DOCKED_REPAIR_TIME
