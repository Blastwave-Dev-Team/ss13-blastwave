// MODULE ID: OVERMAP
// Overmap ships. The base type is purely positional and animation-related;
// the simulated subtype is bound to a real `/obj/docking_port/mobile` and
// tracks the shuttle's Z so the ship icon stays in sync when the shuttle is
// moved by ANY system (helm, in-shuttle console, admin VV, etc).

/// Anything on the overmap that's capable of self-propelled motion.
/obj/structure/overmap/ship
	name = "vessel"
	desc = "A spacefaring vessel."
	icon = 'modular_nova/modules/overmap/icons/overmap.dmi'
	icon_state = "ship"
	base_icon_state = "ship"

	/// Current flight-assisted speed envelope in tiles/second.
	/// Refreshed from available full-output thrust and ship mass.
	var/max_speed = 0
	/// Full-output thrust currently available for the assisted envelope/braking.
	/// Unlike est_thrust, this is independent of commanded throttle and spool.
	var/available_thrust = 0
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
	has_heading = desired_throttle > OVERMAP_THRUST_EPSILON
	if(has_heading && is_still())
		activate_physics()

/// All-stop: zero throttle, clear heading, and begin braking.
/// Braking rate is proportional to thrust/mass — light ships with good
/// engines stop fast, heavy ships take longer.
/obj/structure/overmap/ship/proc/all_stop()
	desired_throttle = 0
	has_heading = FALSE
	station_keeping = FALSE

/obj/structure/overmap/ship/simulated/all_stop()
	..()
	target_mol_s = 0
	delivered_mol_s = 0

/// Helm full-stop command. Meaningful velocity still brakes physically, while
/// drift at or below one percent of the current envelope settles immediately.
/obj/structure/overmap/ship/proc/can_full_stop()
	var/reference_speed = max_speed > 0 ? max_speed : OVERMAP_MAX_SPEED
	return get_speed() / reference_speed <= 0.01

/obj/structure/overmap/ship/proc/full_stop()
	all_stop()
	if(can_full_stop())
		deactivate_physics()
		update_icon_state()
	else
		activate_physics()

/// Live thrust for velocity convergence. Simulated ships use burn `est_thrust`
/// while thrusting; otherwise rated thrust remains the legacy fallback.
/// Braking and the assisted envelope use get_available_thrust() instead.
/obj/structure/overmap/ship/proc/get_effective_thrust()
	if(istype(src, /obj/structure/overmap/ship/simulated))
		var/obj/structure/overmap/ship/simulated/sim = src
		if(sim.est_thrust > OVERMAP_THRUST_EPSILON)
			return sim.est_thrust
		if(!sim.shuttle)
			return OVERMAP_THRUST_EPSILON
		var/rated = 0
		for(var/obj/machinery/power/shuttle_engine/overmap/engine in sim.shuttle.engine_list)
			if(engine.enabled && engine.thruster_active)
				rated += engine.get_rated_thrust()
		return max(rated, OVERMAP_THRUST_EPSILON)
	return 20

/// Effective mass for accel/brake. Simulated ships use turf-count mass.
/obj/structure/overmap/ship/proc/get_effective_mass()
	if(istype(src, /obj/structure/overmap/ship/simulated))
		var/obj/structure/overmap/ship/simulated/sim = src
		return max(sim.mass, 1)
	return 1

/// Full-output thrust presently available for the flight envelope and braking.
/// Simulated ships override this with an engine/power/ISP-aware sum.
/obj/structure/overmap/ship/proc/get_available_thrust()
	return get_effective_thrust()

/// Acceleration available at full output in tiles/s².
/obj/structure/overmap/ship/proc/get_available_acceleration()
	return (available_thrust / get_effective_mass()) * OVERMAP_THRUST_ACCEL_SCALE

/// Refresh the assisted target-speed envelope from stopping distance.
/obj/structure/overmap/ship/proc/refresh_flight_envelope()
	available_thrust = max(get_available_thrust(), 0)
	var/available_acceleration = get_available_acceleration()
	if(available_acceleration <= 0)
		max_speed = 0
		return
	max_speed = min(
		sqrt(2 * available_acceleration * OVERMAP_ASSIST_BRAKING_DISTANCE),
		OVERMAP_MAX_SPEED,
	)

/// Apply braking deceleration toward zero velocity. Called each physics_tick
/// when has_heading is FALSE and ship is not yet still.
/// Uses the same full-output authority that defines the assisted speed envelope,
/// guaranteeing a stop within OVERMAP_ASSIST_BRAKING_DISTANCE while available.
/obj/structure/overmap/ship/proc/apply_braking(dt)
	var/brake_rate = get_available_acceleration() * dt
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
/obj/structure/overmap/ship/physics_tick(dt, refresh_envelope = TRUE)
	if(!has_heading && is_still() && !has_gravity_influence())
		deactivate_physics()
		update_icon_state()
		return

	if(refresh_envelope)
		refresh_flight_envelope()

	if(has_heading)
		var/target_vx = cos(desired_angle) * desired_throttle * max_speed
		var/target_vy = sin(desired_angle) * desired_throttle * max_speed
		var/thrust_accel = (get_effective_thrust() / get_effective_mass()) * OVERMAP_THRUST_ACCEL_SCALE
		var/step = thrust_accel * dt
		var/dvx = target_vx - vel_x
		var/dvy = target_vy - vel_y
		var/delta = sqrt(dvx * dvx + dvy * dvy)
		if(delta <= step || delta <= OVERMAP_VELOCITY_EPSILON)
			vel_x = target_vx
			vel_y = target_vy
		else
			vel_x += dvx * (step / delta)
			vel_y += dvy * (step / delta)
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
		var/gravity_accel = body.gravity_mass / dist_sq
		// Convert pixel-space accel to tiles/second velocity change
		vel_x += (dx / dist) * gravity_accel * dt / ICON_SIZE_ALL
		vel_y += (dy / dist) * gravity_accel * dt / ICON_SIZE_ALL

	// Station-keeping autopilot
	if(station_keeping)
		apply_station_keeping(dt)

	var/speed = get_speed()
	// The assisted envelope is a target, not an instantaneous velocity clamp.
	// Keep only the hard integration ceiling so engine loss decelerates physically.
	if(speed > OVERMAP_MAX_SPEED)
		var/scale = OVERMAP_MAX_SPEED / speed
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

/obj/structure/overmap/ship/update_overlays()
	. = ..()
	var/obj/structure/overmap/ship/simulated/sim = istype(src, /obj/structure/overmap/ship/simulated) ? src : null
	if(!sim?.cached_hull_icon || integrity >= initial(integrity) / 4)
		return
	var/mutable_appearance/damage_tint = mutable_appearance(sim.cached_hull_icon)
	damage_tint.color = integrity <= 0 ? "#701b1b" : "#a64b4b"
	damage_tint.alpha = integrity <= 0 ? 150 : 90
	. += damage_tint

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
	/// Commanded propellant mass flow (mol/s) from throttle × engine demand.
	var/target_mol_s = 0
	/// Spool-limited delivered mass flow (mol/s); thrust tracks this, not raw throttle.
	var/delivered_mol_s = 0
	/// Pending nav-camera docking target (written by helm `dock()`, read by nav console on open).
	var/obj/structure/overmap/nav_dock_target
	/// Z-levels the nav camera should display for the pending target.
	var/list/nav_dock_zs
	/// Stationary dock IDs relevant to the pending target (for jump-to-location in the nav UI).
	var/list/nav_dock_ids
	/// Overmap level id this ship was bound under (MAIN / DES_TWO). Used for
	/// stealth affiliation while the hull sits on a reserved transit Z.
	var/home_level_id
	/// Uncontrolled site LZ pins: site REF → landing zone REF. Cleared on undock.
	var/list/assigned_landing_zones
	/// TRUE while the high-authority recovery brake is decelerating the ship.
	var/emergency_braking = FALSE
	/// Rated acceleration captured when the emergency brake engages.
	var/emergency_brake_acceleration = 0
	/// Disabled ships automatically land once emergency braking reaches zero.
	var/emergency_auto_land = FALSE
	/// Prevent repeated recovery attempts after a landing fault.
	var/emergency_recovery_attempted = FALSE

/obj/structure/overmap/ship/simulated/Initialize(mapload, _id, obj/docking_port/mobile/_shuttle)
	. = ..()
	LAZYADD(SSovermap.simulated_ships, src)
	if(_shuttle)
		shuttle = _shuttle
	if(!shuttle && id)
		shuttle = SSshuttle.getShuttle(id, TRUE)
	if(shuttle)
		name = shuttle.name
	if(istype(loc, /obj/structure/overmap))
		docked = loc
	if(isnull(home_level_id) && istype(docked, /obj/structure/overmap/level))
		var/obj/structure/overmap/level/home_level = docked
		home_level_id = home_level.id
	addtimer(CALLBACK(src, PROC_REF(scan)), 1 SECONDS)

/// Idempotently apply the post-undock state machine: mass + engines + fuel
/// recomputed, icon refreshed, hull silhouette generated.
/obj/structure/overmap/ship/simulated/proc/prepare_for_flight()
	calculate_mass()
	refresh_engines()
	refresh_flight_envelope()
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
	assigned_landing_zones = null
	return ..()

/// Write the pending docking target so the nav console can read it lazily.
/// Called by `dock()` when no automatic stationary port is found.
/obj/structure/overmap/ship/simulated/proc/set_nav_target(obj/structure/overmap/target, list/zs, list/dock_ids)
	nav_dock_target = target
	nav_dock_zs = zs?.Copy()
	nav_dock_ids = dock_ids?.Copy()

/// Full-throttle propellant demand across enabled feed-capable engines (mol/s).
/obj/structure/overmap/ship/simulated/proc/get_propellant_demand_mol_s()
	if(!shuttle)
		return 0
	var/total = 0
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.enabled || !engine.thruster_active)
			continue
		var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
		if(!injector?.has_feed_propellant())
			continue
		total += overmap_engine_propellant_mol_s(engine.thrust, engine.get_power_fraction())
	return total

/// Highest L2 feed pressure among injectors currently feeding engines (kPa).
/obj/structure/overmap/ship/simulated/proc/get_feed_rail_pressure()
	if(!shuttle)
		return 0
	var/best = 0
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.enabled || !engine.thruster_active)
			continue
		var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
		if(!injector?.has_feed_propellant())
			continue
		best = max(best, injector.return_feed_pressure())
	return best

/// Full-throttle capability independent of command/spool state.
/// update_engine() refreshes panel, injector, and hall-only availability;
/// get_current_thrust() folds in current power fraction and injector ISP.
/obj/structure/overmap/ship/simulated/get_available_thrust()
	if(!shuttle)
		return 0
	var/total = 0
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.update_engine())
			continue
		total += engine.get_current_thrust()
	return total

/// Slews delivered_mol_s toward throttle×demand; L2 pressure sets spool-up rate.
/obj/structure/overmap/ship/simulated/proc/update_propellant_spool(dt)
	if(dt <= 0)
		return
	var/demand = get_propellant_demand_mol_s()
	target_mol_s = desired_throttle * demand
	if(target_mol_s <= OVERMAP_MOL_S_EPSILON && delivered_mol_s <= OVERMAP_MOL_S_EPSILON)
		target_mol_s = 0
		delivered_mol_s = 0
		return
	var/rail_p = get_feed_rail_pressure()
	var/rail_frac = OVERMAP_SPOOL_FULL_RAIL_PRESSURE > 0 \
		? clamp(rail_p / OVERMAP_SPOOL_FULL_RAIL_PRESSURE, 0, 1) \
		: 0
	// At full rail, spool-up can jump to any demand in one tick; empty rail crawls.
	var/max_up = max(OVERMAP_SPOOL_MIN_ACCEL, demand * rail_frac / max(dt, 0.01))
	if(rail_frac >= 1)
		max_up = max(max_up, demand / max(dt, 0.01))
	var/delta = target_mol_s - delivered_mol_s
	if(delta > 0)
		delivered_mol_s += min(delta, max_up * dt)
	else
		delivered_mol_s += max(delta, -OVERMAP_SPOOL_DECEL * dt)
	delivered_mol_s = max(delivered_mol_s, 0)

/obj/structure/overmap/ship/simulated/receive_damage(amount)
	var/previous_integrity = integrity
	. = ..()
	if(integrity <= 0 && emergency_braking)
		emergency_auto_land = TRUE
	if(previous_integrity > 0 && integrity <= 0 && state == OVERMAP_SHIP_FLYING && !emergency_braking)
		engage_emergency_brake(TRUE)

/// Engage the independent recovery brake. Damage is applied once, while the
/// captured 3x rated authority remains active until the ship stops.
/obj/structure/overmap/ship/simulated/proc/engage_emergency_brake(automatic = FALSE)
	if(state != OVERMAP_SHIP_FLYING || emergency_braking || is_still())
		return FALSE
	emergency_braking = TRUE
	emergency_auto_land = automatic || integrity <= 0
	emergency_recovery_attempted = FALSE
	all_stop()
	if(!mass)
		calculate_mass()
	var/rated_thrust = 0
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle?.engine_list)
		if(QDELETED(engine))
			continue
		rated_thrust += max(engine.thrust, engine.get_rated_thrust())
	emergency_brake_acceleration = max(
		(rated_thrust / max(get_effective_mass(), 1)) * OVERMAP_THRUST_ACCEL_SCALE * OVERMAP_EMERGENCY_BRAKE_MULTIPLIER,
		OVERMAP_VELOCITY_EPSILON * 10,
	)
	var/speed_fraction = clamp(get_speed() / OVERMAP_MAX_SPEED, 0, 1)
	var/hull_damage = round(lerp(OVERMAP_EMERGENCY_BRAKE_HULL_DAMAGE_MIN, OVERMAP_EMERGENCY_BRAKE_HULL_DAMAGE_MAX, speed_fraction))
	if(hull_damage > 0)
		receive_damage(hull_damage)
	if(integrity <= 0)
		emergency_auto_land = TRUE
	var/engine_damage = round(lerp(OVERMAP_EMERGENCY_BRAKE_ENGINE_DAMAGE_MIN, OVERMAP_EMERGENCY_BRAKE_ENGINE_DAMAGE_MAX, speed_fraction))
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle?.engine_list)
		if(QDELETED(engine) || !engine.enabled)
			continue
		engine.take_damage(engine_damage, BRUTE)
		engine.update_engine()
		engine.update_appearance()
	refresh_engines()
	refresh_flight_envelope()
	activate_physics()
	announce_to_helms(automatic ? "CRITICAL HULL FAILURE. Emergency braking engaged; preparing automatic open-space recovery." : "Emergency brake engaged. Hull and propulsion stress detected.")
	return TRUE

/obj/structure/overmap/ship/simulated/apply_braking(dt)
	if(!emergency_braking)
		return ..()
	var/brake_rate = emergency_brake_acceleration * dt
	var/speed = get_speed()
	if(speed <= brake_rate)
		vel_x = 0
		vel_y = 0
		return
	var/scale = (speed - brake_rate) / speed
	vel_x *= scale
	vel_y *= scale

/// Override physics_tick: if docked, do nothing. If out of fuel, decay.
/// While thrusting, aggregate live burn thrust into `est_thrust` for accel.
/obj/structure/overmap/ship/simulated/physics_tick(dt)
	if(docked || state != OVERMAP_SHIP_FLYING)
		all_stop()
		delivered_mol_s = 0
		target_mol_s = 0
		deactivate_physics()
		return
	calculate_avg_fuel()
	// Sample full-output capability before this tick's burn adds power load.
	refresh_flight_envelope()
	if(avg_fuel_amnt < 1)
		desired_throttle = max(desired_throttle - 0.1 * dt, 0)
	update_propellant_spool(dt)
	if(desired_throttle > OVERMAP_THRUST_EPSILON)
		refresh_engines()
		var/thrust_sum = 0
		var/moles_tick = delivered_mol_s * dt
		var/list/injector_thrust = process_engine_fuel_burns(moles_tick, dt)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in injector_thrust)
			thrust_sum += injector_thrust[engine]
		var/hall_pct = desired_throttle * 100
		for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
			if(!engine.enabled || !engine.thruster_active)
				continue
			var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
			if(injector?.has_feed_propellant())
				continue
			thrust_sum += engine.burn_engine(hall_pct, skip_engine_update = TRUE, dt = dt)
			engine.burning = FALSE
		est_thrust = thrust_sum
	else
		est_thrust = 0
	..(dt, FALSE)
	if(emergency_braking && can_full_stop())
		full_stop()
	if(emergency_braking && is_still())
		emergency_braking = FALSE
		emergency_brake_acceleration = 0
		if(emergency_auto_land && !emergency_recovery_attempted)
			emergency_recovery_attempted = TRUE
			recover_disabled_ship()

/// Batch L2 feed burns for injector-fed engines. `moles_requested` is total moles this tick.
/obj/structure/overmap/ship/simulated/proc/process_engine_fuel_burns(moles_requested, dt = 1)
	if(!shuttle || moles_requested <= OVERMAP_MOL_S_EPSILON)
		return list()
	var/list/by_injector = list()
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.enabled || !engine.thruster_active)
			continue
		var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
		if(!injector?.has_feed_propellant())
			continue
		LAZYADD(by_injector[injector], engine)
	if(!length(by_injector))
		return list()
	// Split total moles across injectors proportional to their engines' mol/s demand.
	var/list/injector_demand = list()
	var/total_demand = 0
	for(var/obj/machinery/overmap/fuel_injector/injector as anything in by_injector)
		var/d = 0
		for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in by_injector[injector])
			d += overmap_engine_propellant_mol_s(engine.thrust, engine.get_power_fraction())
		injector_demand[injector] = d
		total_demand += d
	if(total_demand <= 0)
		return list()
	processing_fuel_batch = TRUE
	var/list/all_thrust = list()
	for(var/obj/machinery/overmap/fuel_injector/injector as anything in by_injector)
		var/share = moles_requested * (injector_demand[injector] / total_demand)
		var/list/thrust_results = injector.process_tick_burn(by_injector[injector], share, dt)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in thrust_results)
			all_thrust[engine] = thrust_results[engine]
			engine.burning = FALSE
	processing_fuel_batch = FALSE
	return all_thrust

/// Resync the ship icon's overmap position with whatever Z the bound shuttle
/// currently occupies. Called from M3's `shuttle_move` BLASTWAVE EDIT after every
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
	var/obj/structure/overmap/docked_object = SSovermap.get_overmap_object_by_z(shuttle.z)
	if(docked_object == loc)
		return TRUE
	if(!docked_object && !docked)
		return TRUE
	// Docked at a dynamic whose content Z still holds this shuttle — stay put.
	if(docked && istype(docked, /obj/structure/overmap/dynamic))
		var/obj/structure/overmap/dynamic/enc = docked
		if(shuttle.z in enc.linked_levels)
			return TRUE
	if(docked && !docked_object)
		var/turf/free_tile = SSovermap.get_unused_overmap_square()
		if(free_tile)
			forceMove(free_tile)
		docked = null
		state = OVERMAP_SHIP_FLYING
		update_screen(TRUE)
		sync_helm_gps_beacons()
		return FALSE
	if(!docked && docked_object)
		overmap_reset_visual_offset()
		forceMove(docked_object)
		docked = docked_object
		state = OVERMAP_SHIP_IDLE
		all_stop()
		update_screen(TRUE)
		sync_helm_gps_beacons()
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
			calc += engine.get_rated_thrust()
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
/// With no `n_dir`, applies braking (no propellant draw).
/obj/structure/overmap/ship/simulated/proc/burn_engines(n_dir = null, percentage = 100)
	if(state != OVERMAP_SHIP_FLYING)
		return
	if(!n_dir)
		all_stop()
		return
	refresh_engines()
	if(!mass)
		calculate_mass()
	calculate_avg_fuel()
	// Apply commanded thrust before consuming so ship_wants_thrust() gates pass.
	burn_direction(n_dir, clamp(percentage / 100, 0, 1))
	if(percentage <= 0 || desired_throttle <= OVERMAP_THRUST_EPSILON)
		est_thrust = 0
		delivered_mol_s = 0
		target_mol_s = 0
		return
	// One-shot burns (tests / legacy): skip spool lag — deliver the commanded mol/s immediately.
	var/demand = get_propellant_demand_mol_s()
	target_mol_s = desired_throttle * demand
	delivered_mol_s = target_mol_s
	var/thrust_used = 0
	var/list/by_injector = list()
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.enabled)
			continue
		var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
		if(injector?.has_feed_propellant())
			LAZYADD(by_injector[injector], engine)
			continue
		thrust_used += engine.burn_engine(percentage)
	if(length(by_injector))
		var/list/thrust_map = process_engine_fuel_burns(delivered_mol_s, 1)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in thrust_map)
			thrust_used += thrust_map[engine]
	est_thrust = thrust_used

/// Detach the ship from its current docked overmap object and start flight.
/obj/structure/overmap/ship/simulated/proc/undock()
	if(!shuttle)
		return "Shuttle not found!"
	if(integrity <= 0)
		return "Hull control systems are disabled! Repair the vessel before launch."
	if(state != OVERMAP_SHIP_IDLE)
		return "Ship is not docked!"
	if(!docked)
		check_loc()
		return "Ship not docked!"
	all_stop()
	prepare_for_flight()
	if(avg_fuel_amnt <= 0)
		return "Engines have no fuel!"
	var/launch_block = check_launch_clearance()
	if(launch_block)
		return launch_block
	// Pre-flight: the shuttle subsystem refuses transit if canMove() fails
	// (e.g. a custom shuttle with no welded engines), so surface that now
	// rather than silently aborting mid-ignition.
	if(!shuttle.canMove())
		return "Engines not responding! Ensure engines are installed and welded to the hull."
	shuttle.destination = null
	shuttle.mode = SHUTTLE_IGNITING
	shuttle.setTimer(shuttle.ignitionTime)
	addtimer(CALLBACK(src, PROC_REF(complete_undock)), shuttle.ignitionTime + (1 SECONDS))
	state = OVERMAP_SHIP_UNDOCKING
	sync_helm_gps_beacons()
	return "Beginning undocking procedures..."

/// How many 2-second rechecks complete_undock() will wait for SSshuttle to
/// allocate a transit zone before declaring the launch failed.
#define UNDOCK_TRANSIT_RETRIES 10

/// Called when the shuttle's ignition timer elapses. Verifies the physical
/// shuttle actually reached hyperspace before advancing the overmap icon:
/// the SSshuttle state machine can silently abort (transit allocation failure,
/// lockdown, canMove() flipping FALSE), and a blind timer would leave the icon
/// "flying" while the hull is still parked on the station Z.
/obj/structure/overmap/ship/simulated/proc/complete_undock(retries = UNDOCK_TRANSIT_RETRIES)
	if(state != OVERMAP_SHIP_UNDOCKING)
		return
	if(!shuttle)
		state = OVERMAP_SHIP_IDLE
		update_screen(TRUE)
		return
	if(!is_reserved_level(shuttle.z) && shuttle.mode != SHUTTLE_CALL)
		if(shuttle.mode == SHUTTLE_IGNITING && retries > 0)
			// Transit zone not allocated yet - SSshuttle retries every 2 seconds.
			addtimer(CALLBACK(src, PROC_REF(complete_undock), retries - 1), 2 SECONDS)
			return
		// enterTransit() aborted or transit allocation gave up. Stay docked.
		state = OVERMAP_SHIP_IDLE
		update_screen(TRUE)
		sync_helm_gps_beacons()
		announce_to_helms("Launch aborted: engines failed to reach hyperspace. Check engine installation and try again.")
		return
	var/obj/structure/overmap/prev_docked = docked
	if(docked)
		forceMove(get_turf(docked))
		docked = null
	state = OVERMAP_SHIP_FLYING
	update_screen(TRUE)
	sync_helm_gps_beacons()
	if(istype(prev_docked, /obj/structure/overmap/level/site))
		LAZYREMOVE(assigned_landing_zones, REF(prev_docked))
	if(istype(prev_docked, /obj/structure/overmap/dynamic))
		var/obj/structure/overmap/dynamic/encounter = prev_docked
		encounter.unload_level()
	if(istype(prev_docked, /obj/structure/overmap/level/site/open_space))
		var/obj/structure/overmap/level/site/open_space/open_site = prev_docked
		open_site.try_cleanup()

#undef UNDOCK_TRANSIT_RETRIES

/// Say a message from every helm console currently bound to this ship, for
/// async failures where there is no synchronous return value to relay.
/obj/structure/overmap/ship/simulated/proc/announce_to_helms(message)
	for(var/obj/machinery/computer/helm/helm as anything in SSovermap.helms)
		if(helm.current_ship == src && !helm.viewer)
			helm.say(message)

/// Refresh landed-only GPS beacons on every helm bound to this ship.
/obj/structure/overmap/ship/simulated/proc/sync_helm_gps_beacons()
	for(var/obj/machinery/computer/helm/helm as anything in SSovermap.helms)
		if(helm.current_ship == src)
			helm.sync_gps_beacon()

/// Helm "Act" entry point. `lz_ref` optionally names a specific landing zone
/// landmark to dock at instead of the automatic stationary-port search.
/obj/structure/overmap/ship/simulated/proc/overmap_object_act(obj/structure/overmap/target, mob/user, lz_ref)
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
		var/dock_result = dock(encounter, lz_ref)
		if(state != OVERMAP_SHIP_DOCKING)
			var/still_inbound = shuttle && shuttle.destination && (
				shuttle.mode == SHUTTLE_CALL || shuttle.mode == SHUTTLE_IGNITING || shuttle.mode == SHUTTLE_PREARRIVAL
			)
			if(!still_inbound)
				encounter.unload_level()
		return dock_result
	if(istype(target, /obj/structure/overmap/level))
		return dock(target, lz_ref)
	return "Cannot interact with this object yet."

/// Landing zones on `target`'s Z-levels that this ship's shuttle fits in its
/// current orientation and that are unoccupied. Returns a list of landmarks.
/// Uncontrolled sites (`site.controlled == FALSE`) pin one random free LZ per
/// ship so the helm and astrogation camera only expose a single choice.
/obj/structure/overmap/ship/simulated/proc/get_landing_zones_for(obj/structure/overmap/target)
	. = list()
	if(!shuttle)
		return
	var/list/target_zs = resolve_nav_target_zs(target)
	if(!length(target_zs))
		return
	var/list/bounds = shuttle.return_coords()
	var/ship_w = abs(bounds[3] - bounds[1]) + 1
	var/ship_h = abs(bounds[4] - bounds[2]) + 1
	var/list/candidates = list()
	var/ship_affiliation = SSovermap.get_affiliation(src)
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in SSovermap.landing_zones)
		if(!(zone.z in target_zs))
			continue
		if(ship_w > zone.zone_width || ship_h > zone.zone_height)
			continue
		if(zone.get_occupant(shuttle))
			continue
		// Null/empty dock_affiliation = open pad (seeded/mapped defaults).
		if(zone.dock_affiliation && zone.dock_affiliation != ship_affiliation)
			continue
		candidates += zone

	if(!length(candidates))
		return

	if(!istype(target, /obj/structure/overmap/level/site))
		return candidates
	var/obj/structure/overmap/level/site/site = target
	if(site.controlled)
		return candidates

	var/site_ref = REF(site)
	var/pinned_ref = LAZYACCESS(assigned_landing_zones, site_ref)
	if(pinned_ref)
		var/obj/effect/landmark/overmap_landing_zone/pinned = locate(pinned_ref)
		if(pinned && (pinned in candidates))
			return list(pinned)
		LAZYREMOVE(assigned_landing_zones, site_ref)

	var/obj/effect/landmark/overmap_landing_zone/picked = pick(candidates)
	LAZYSET(assigned_landing_zones, site_ref, REF(picked))
	return list(picked)

/// Build a one-shot stationary docking port centered in `zone`, preserving the
/// shuttle's current orientation. Returns the port, or null if the shuttle no
/// longer fits / the zone is occupied. The port self-deletes after the shuttle
/// next departs it (`delete_after`).
/obj/structure/overmap/ship/simulated/proc/create_landing_zone_port(obj/effect/landmark/overmap_landing_zone/zone)
	var/list/bounds = shuttle.return_coords()
	var/bbox_x1 = min(bounds[1], bounds[3])
	var/bbox_y1 = min(bounds[2], bounds[4])
	var/ship_w = max(bounds[1], bounds[3]) - bbox_x1 + 1
	var/ship_h = max(bounds[2], bounds[4]) - bbox_y1 + 1
	if(ship_w > zone.zone_width || ship_h > zone.zone_height)
		return null
	if(zone.get_occupant(shuttle))
		return null
	// Offset of the mobile port tile inside its own bbox. With the stationary
	// port sharing the shuttle's dir and dimensions, landing reproduces the
	// same bbox relative to the port tile, so this places the hull centered.
	var/port_off_x = shuttle.x - bbox_x1
	var/port_off_y = shuttle.y - bbox_y1
	var/dest_x = zone.x + round((zone.zone_width - ship_w) / 2) + port_off_x
	var/dest_y = zone.y + round((zone.zone_height - ship_h) / 2) + port_off_y
	var/turf/dest = locate(dest_x, dest_y, zone.z)
	if(!dest)
		return null
	var/obj/docking_port/stationary/port = new()
	port.unregister()
	port.delete_after = TRUE
	port.name = zone.zone_name
	port.shuttle_id = "[shuttle.shuttle_id]_lz"
	port.width = shuttle.width
	port.height = shuttle.height
	port.dwidth = shuttle.dwidth
	port.dheight = shuttle.dheight
	port.register(TRUE)
	port.setDir(shuttle.dir)
	port.forceMove(dest)
	if(!shuttle.check_dock(port, TRUE) || !SSovermap.dock_footprint_is_clear(port))
		qdel(port)
		return null
	return port

/// Voluntarily land at the shared open-space site for the current overmap
/// tile. A new blank site is created only when no level already owns it.
/obj/structure/overmap/ship/simulated/proc/land_in_open_space(lz_ref)
	if(state != OVERMAP_SHIP_FLYING)
		return "Ship is not in flight."
	if(!is_still())
		return "Ship must be stopped before landing in open space."
	var/turf/overmap_tile = get_turf(src)
	var/obj/structure/overmap/level/landing_site = SSovermap.get_or_create_open_space_site(overmap_tile)
	if(!landing_site)
		return "Unable to stabilize an open-space landing site at these coordinates."
	var/result = dock(landing_site, lz_ref)
	if(state != OVERMAP_SHIP_DOCKING && istype(landing_site, /obj/structure/overmap/level/site/open_space))
		var/obj/structure/overmap/level/site/open_space/open_site = landing_site
		open_site.try_cleanup()
	return result

/// Force a disabled, stopped hull onto a validated landing zone without
/// requiring functional shuttle engines.
/obj/structure/overmap/ship/simulated/proc/recover_disabled_ship()
	if(state != OVERMAP_SHIP_FLYING || !is_still() || !shuttle)
		return FALSE
	var/obj/structure/overmap/level/landing_site = SSovermap.get_or_create_open_space_site(get_turf(src))
	if(!landing_site)
		announce_to_helms("EMERGENCY RECOVERY FAILED. No stable open-space site is available at this coordinate.")
		return FALSE
	var/list/zones = get_landing_zones_for(landing_site)
	if(!length(zones))
		announce_to_helms("EMERGENCY RECOVERY FAILED. No clear landing zone can contain this hull.")
		if(istype(landing_site, /obj/structure/overmap/level/site/open_space))
			var/obj/structure/overmap/level/site/open_space/open_site = landing_site
			open_site.try_cleanup()
		return FALSE
	var/obj/docking_port/stationary/recovery_port = create_landing_zone_port(pick(zones))
	if(!recovery_port)
		announce_to_helms("EMERGENCY RECOVERY FAILED. Landing-zone geometry changed before touchdown.")
		return FALSE
	docked = landing_site
	state = OVERMAP_SHIP_DOCKING
	var/docking_result = shuttle.initiate_docking(recovery_port, force = TRUE)
	if(docking_result != DOCKING_SUCCESS)
		docked = null
		state = OVERMAP_SHIP_FLYING
		qdel(recovery_port)
		announce_to_helms("EMERGENCY RECOVERY FAILED. Physical docking transfer was rejected.")
		return FALSE
	if(state == OVERMAP_SHIP_DOCKING)
		complete_dock()
	emergency_auto_land = FALSE
	announce_to_helms("Emergency recovery complete. Hull secured in open space.")
	return TRUE

/// Stationary dock lookup by shuttle_id without SSshuttle.getDock()'s
/// "couldn't find dock" warning. dock() probes several speculative IDs per
/// attempt and misses are the expected case, not an error.
/obj/structure/overmap/ship/simulated/proc/find_dock_quiet(id)
	for(var/obj/docking_port/stationary/port in SSshuttle.stationary_docking_ports)
		if(port.shuttle_id == id)
			return port
	return null

/// Try to resolve a stationary docking port for `target` and request the
/// shuttle to fly to it. If `lz_ref` is given, dock at that landing zone
/// instead of searching pre-mapped ports.
/obj/structure/overmap/ship/simulated/proc/dock(obj/structure/overmap/target, lz_ref)
	if(state == OVERMAP_SHIP_DOCKING)
		return "Docking already in progress."
	if(state != OVERMAP_SHIP_FLYING)
		return "Ship is not in flight."
	if(!is_still())
		return "Ship must be stopped to dock."
	if(!shuttle)
		return "Shuttle not found."
	if(!SSovermap.can_view_installation(src, target))
		return "Unable to establish docking link with target."
	if(!shuttle.canMove())
		return "Engines not responding! Ensure engines are installed and welded to the hull."

	var/obj/docking_port/stationary/picked

	if(lz_ref)
		var/obj/effect/landmark/overmap_landing_zone/zone = locate(lz_ref) in SSovermap.landing_zones
		if(!zone || !(zone in get_landing_zones_for(target)))
			return "Landing zone unavailable - it may be occupied or out of range."
		picked = create_landing_zone_port(zone)
		if(!picked)
			return "Unable to designate a landing site in [zone.zone_name]."
	else
		var/list/target_zs = resolve_nav_target_zs(target)

		// Landing-console designated pad takes priority over pre-mapped docks.
		// The pad has to actually be on the target body: a pad designated on
		// another planet must not let you "dock" here.
		var/obj/docking_port/stationary/designated = find_dock_quiet("[shuttle.shuttle_id]_custom")
		if(designated && (designated.z in target_zs) && shuttle.check_dock(designated, TRUE) && SSovermap.dock_footprint_is_clear(designated))
			picked = designated

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

		if(!picked)
			for(var/dock_id in candidates)
				var/obj/docking_port/stationary/found = find_dock_quiet(dock_id)
				if(!found)
					continue
				if(!shuttle.check_dock(found, TRUE))
					continue
				if(!SSovermap.dock_footprint_is_clear(found))
					continue
				picked = found
				break

		// Named sites (and other LZ-backed bodies) auto-assign a free LZ when
		// no premapped / designated pad is available.
		if(!picked)
			var/list/zones = get_landing_zones_for(target)
			if(length(zones))
				picked = create_landing_zone_port(pick(zones))

		if(!picked)
			set_nav_target(target, target_zs, candidates)
			if(length(get_landing_zones_for(target)))
				return "No automatic dock found - select a landing zone or use the astrogation landing console to designate a landing pad on [target.name]."
			return "No automatic dock found - use the astrogation landing console to designate a landing pad on [target.name]."

	docked = target
	state = OVERMAP_SHIP_DOCKING
	if(!shuttle.check_dock(picked, TRUE))
		docked = null
		state = OVERMAP_SHIP_FLYING
		update_screen(TRUE)
		return "Docking lock rejected — no confirmed approach corridor at [target.name]. Re-run survey or select a landing zone."
	if(!SSovermap.dock_footprint_is_clear(picked))
		docked = null
		state = OVERMAP_SHIP_FLYING
		update_screen(TRUE)
		return "Docking lock rejected — landing corridor at [target.name] is obstructed. Select a clear landing zone."
	shuttle.request(picked)
	// SHUTTLE_CALL / PREARRIVAL with matching destination is a successful commit.
	var/shuttle_committed = (shuttle.destination == picked) && (
		shuttle.mode == SHUTTLE_IGNITING || shuttle.mode == SHUTTLE_CALL || shuttle.mode == SHUTTLE_PREARRIVAL
	)
	if(!shuttle_committed)
		docked = null
		state = OVERMAP_SHIP_FLYING
		update_screen(TRUE)
		return "Docking lock rejected — engines could not commit to the surveyed corridor at [target.name]."
	var/transit_time
	if(shuttle.mode == SHUTTLE_CALL || shuttle.mode == SHUTTLE_PREARRIVAL)
		transit_time = shuttle.timeLeft(1) + (3 SECONDS)
	else
		transit_time = shuttle.ignitionTime + (shuttle.callTime * shuttle.engine_coeff) + (3 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(complete_dock)), transit_time)
	return "Commencing docking at [target.name]..."

/// Derive the real Z-levels for a docking target so the nav camera can open there.
/obj/structure/overmap/ship/simulated/proc/resolve_nav_target_zs(obj/structure/overmap/target)
	if(istype(target, /obj/structure/overmap/level))
		var/obj/structure/overmap/level/level_target = target
		return level_target.linked_levels?.Copy()
	if(istype(target, /obj/structure/overmap/dynamic))
		var/obj/structure/overmap/dynamic/encounter = target
		return encounter.linked_levels?.Copy() || list()
	return list()

/// Snap icon onto docked overmap object and return to idle.
/obj/structure/overmap/ship/simulated/proc/complete_dock()
	if(state != OVERMAP_SHIP_DOCKING)
		return
	if(istype(docked, /obj/structure/overmap/dynamic))
		var/obj/structure/overmap/dynamic/encounter = docked
		if(length(encounter.linked_levels) && !(shuttle.z in encounter.linked_levels))
			encounter.unload_level()
			docked = null
			state = OVERMAP_SHIP_FLYING
			announce_to_helms("SURVEY MISMATCH. Vessel landed outside the charted encounter footprint — hold position and re-attempt docking.")
			update_screen(TRUE)
			return
	if(docked)
		overmap_reset_visual_offset()
		forceMove(docked)
	state = OVERMAP_SHIP_IDLE
	all_stop()
	scanned_objects = null
	set_nav_target(null, null, null)
	update_screen(TRUE)
	sync_helm_gps_beacons()

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

/// Frigate: purpose-built overmap ship. Supports both helm console and
/// direct piloting.
/obj/structure/overmap/ship/simulated/frigate
	control_flags = SHIP_CONTROL_CONSOLE | SHIP_CONTROL_DIRECT

/// Capital / military: supports both console and direct piloting.
/obj/structure/overmap/ship/simulated/capital
	control_flags = SHIP_CONTROL_CONSOLE | SHIP_CONTROL_DIRECT

#undef SHIP_SIZE_THRESHOLD
#undef SHIP_DOCKED_REPAIR_TIME
