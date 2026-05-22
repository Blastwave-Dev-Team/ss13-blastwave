// MODULE ID: OVERMAP
// Overmap ships. The base type is purely positional and animation-related;
// the simulated subtype is bound to a real `/obj/docking_port/mobile` and
// tracks the shuttle's Z so the ship icon stays in sync when the shuttle is
// moved by ANY system (helm, in-shuttle console, admin VV, etc).
//
// Movement procs (tick_move/accelerate/adjust_speed/etc) are added in M5;
// the dock/undock/overmap_object_act flow is added in M6. M3 only needs the
// position-tracking surface so SSovermap can iterate live shuttle ports at
// roundstart and bind one icon per shuttle.

#define SHIP_MOVE_RESOLUTION 0.00001
#define MOVING(speed) (abs(speed) >= min_speed)
#define OVERMAP_MAGNITUDE(a, b) (sqrt((a) * (a) + (b) * (b)))

/// Anything on the overmap that's capable of self-propelled motion.
/obj/structure/overmap/ship
	name = "overmap vessel"
	desc = "A spacefaring vessel."
	icon = 'modular_nova/modules/overmap/icons/overmap.dmi'
	icon_state = "ship"
	base_icon_state = "ship"

	// Movement state. Wiring lands in M5.
	var/movement_callback_id
	var/static/max_speed = 1/(1 SECONDS)
	var/static/min_speed = 1/(2 MINUTES)
	var/list/speed = list(0, 0)

/obj/structure/overmap/ship/Destroy()
	LAZYREMOVE(SSovermap.simulated_ships, src)
	if(movement_callback_id)
		deltimer(movement_callback_id)
		movement_callback_id = null
	return ..()

/// Stop helper used in M5 by tick_move and dock transitions.
/obj/structure/overmap/ship/proc/is_still()
	return !MOVING(speed[1]) && !MOVING(speed[2])

/// Heading bitfield from current speed components.
/obj/structure/overmap/ship/proc/get_heading()
	var/direction = 0
	if(MOVING(speed[1]))
		if(speed[1] > 0)
			direction |= EAST
		else
			direction |= WEST
	if(MOVING(speed[2]))
		if(speed[2] > 0)
			direction |= NORTH
		else
			direction |= SOUTH
	return direction

/// Estimated time-of-arrival to the next tile, in deciseconds. 0 if stopped.
/obj/structure/overmap/ship/proc/get_eta()
	if(!movement_callback_id)
		return 0
	return timeleft(movement_callback_id)

/// Magnitude-derived speed in tiles-per-minute. 0 if effectively stopped.
/obj/structure/overmap/ship/proc/get_speed()
	if(is_still())
		return 0
	return 60 SECONDS / round(1 / OVERMAP_MAGNITUDE(speed[1], speed[2]), SHIP_MOVE_RESOLUTION)

/// Add to the ship's speed vector. Recomputes the next-tick timer cadence.
/// `n_x` / `n_y` are absolute deltas (positive E/N, negative W/S).
/obj/structure/overmap/ship/proc/adjust_speed(n_x, n_y)
	var/offset = 1
	if(movement_callback_id)
		var/magnitude = OVERMAP_MAGNITUDE(speed[1], speed[2])
		if(magnitude > SHIP_MOVE_RESOLUTION)
			var/previous_time = round(1 / magnitude, SHIP_MOVE_RESOLUTION)
			var/remaining = timeleft(movement_callback_id)
			if(!isnull(remaining) && previous_time)
				offset = remaining / previous_time
		deltimer(movement_callback_id)
		movement_callback_id = null

	speed[1] += n_x
	speed[2] += n_y

	var/new_mag = OVERMAP_MAGNITUDE(speed[1], speed[2])
	if(new_mag > max_speed)
		var/scale = max_speed / new_mag
		speed[1] *= scale
		speed[2] *= scale

	update_icon_state()

	if(is_still() || QDELETED(src))
		return

	var/timer = max(round(1 / OVERMAP_MAGNITUDE(speed[1], speed[2]) * offset, SHIP_MOVE_RESOLUTION), 1 / max_speed)
	movement_callback_id = addtimer(CALLBACK(src, PROC_REF(tick_move)), timer, TIMER_STOPPABLE)

/// Single-tile step in the current heading, then reschedule. Edge turfs
/// halt via `Bump()`. M6's docking flow zeroes speed via `simulated/tick_move`
/// when the ship has docked.
/obj/structure/overmap/ship/proc/tick_move()
	var/static/last_fire_time = 0
	var/delta = world.time - last_fire_time
	last_fire_time = world.time
	var/mag = OVERMAP_MAGNITUDE(speed[1], speed[2])
	log_game("OVERMAP TICK_MOVE: delta=[delta]ds speed=([speed[1]],[speed[2]]) mag=[mag]")
	if(is_still() || QDELETED(src))
		if(movement_callback_id)
			deltimer(movement_callback_id)
			movement_callback_id = null
		return
	var/turf/newloc = locate(x + sign(speed[1]), y + sign(speed[2]), z)
	if(newloc)
		Move(newloc)
	if(is_still() || QDELETED(src))
		if(movement_callback_id)
			deltimer(movement_callback_id)
			movement_callback_id = null
		return
	if(movement_callback_id)
		deltimer(movement_callback_id)
	var/timer = 1 / round(OVERMAP_MAGNITUDE(speed[1], speed[2]), SHIP_MOVE_RESOLUTION)
	log_game("OVERMAP TICK_MOVE: scheduling next in [timer]ds")
	movement_callback_id = addtimer(CALLBACK(src, PROC_REF(tick_move)), timer, TIMER_STOPPABLE)
	update_screen()

/// Add `acceleration` to the ship's speed in `direction`. Diagonals are
/// halved so going NE isn't twice as efficient as going N.
/obj/structure/overmap/ship/proc/accelerate(direction, acceleration)
	if(!direction || !acceleration)
		return
	if(!(direction in GLOB.cardinals))
		acceleration *= 0.5
	if(direction & EAST)
		adjust_speed(acceleration, 0)
	if(direction & WEST)
		adjust_speed(-acceleration, 0)
	if(direction & NORTH)
		adjust_speed(0, acceleration)
	if(direction & SOUTH)
		adjust_speed(0, -acceleration)

/// Damp speed toward zero by up to `acceleration` per axis. If currently
/// moving on both axes, the brake is split between them so the diagonal
/// case isn't twice as effective as cardinal.
/obj/structure/overmap/ship/proc/decelerate(acceleration)
	if(!acceleration)
		return
	if(speed[1] && speed[2])
		adjust_speed(-sign(speed[1]) * min(acceleration / 2, abs(speed[1])), -sign(speed[2]) * min(acceleration / 2, abs(speed[2])))
	else if(speed[1])
		adjust_speed(-sign(speed[1]) * min(acceleration, abs(speed[1])), 0)
	else if(speed[2])
		adjust_speed(0, -sign(speed[2]) * min(acceleration, abs(speed[2])))

/// Edge tiles bump-stop. Wraparound is post-prototype polish.
/obj/structure/overmap/ship/Bump(atom/A)
	. = ..()
	if(istype(A, /turf/open/overmap/edge))
		decelerate(max_speed)

/obj/structure/overmap/ship/update_icon_state()
	if(!is_still())
		icon_state = "[base_icon_state]_moving"
		dir = get_heading()
	else
		icon_state = base_icon_state
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

	/// IDLE / FLYING / DOCKING / UNDOCKING. M5 transitions IDLE <-> FLYING
	/// via undock/stop; M6 transitions through DOCKING.
	var/state = OVERMAP_SHIP_IDLE
	/// The overmap object the ship is currently parked at, if any.
	var/obj/structure/overmap/docked
	/// The bound mobile docking port this icon represents.
	var/obj/docking_port/mobile/shuttle
	/// Estimated thrust from the shuttle's engine_list. Recomputed in M5
	/// burn_engines hook.
	var/est_thrust
	/// Approximate mass derived from `shuttle.shuttle_areas` turf count.
	var/mass
	/// Average percent fullness across the shuttle's enabled engines.
	var/avg_fuel_amnt = 100

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

/// Idempotently apply the post-undock state machine: mass + engines + fuel
/// recomputed, icon refreshed. Safe to call before `linkup()` has connected
/// engines (mass is derived from `shuttle_areas` turf count, not engine_list)
/// and again after engines are connected so the cached `est_thrust` /
/// `avg_fuel_amnt` reflect reality. Used both from `complete_undock()` and
/// from the spawn-in-transit path so the helm is fly-ready immediately.
/obj/structure/overmap/ship/simulated/proc/prepare_for_flight()
	calculate_mass()
	refresh_engines()
	calculate_avg_fuel()
	update_screen()

/obj/structure/overmap/ship/simulated/Destroy()
	if(shuttle?.current_ship == src)
		shuttle.current_ship = null
	shuttle = null
	docked = null
	return ..()

/// Resync the ship icon's overmap position with whatever Z the bound shuttle
/// currently occupies. Called from M3's `shuttle_move` NOVA EDIT after every
/// `initiate_docking`, so any non-overmap shuttle move (in-shuttle console,
/// admin recall, etc) keeps the icon honest.
/obj/structure/overmap/ship/simulated/proc/check_loc()
	if(!shuttle)
		return
	var/obj/structure/overmap/level/docked_object = SSovermap.get_overmap_object_by_z(shuttle.z)
	if(docked_object == loc)
		return TRUE
	if(!docked_object && !docked)
		return TRUE
	if(state == OVERMAP_SHIP_DOCKING || state == OVERMAP_SHIP_UNDOCKING)
		return
	if(docked && !docked_object)
		// Shuttle left the overmap-mapped space (e.g. CentCom). Float to a
		// random non-edge tile and flag as flying so the helm can react.
		var/turf/free_tile = SSovermap.get_unused_overmap_square()
		if(free_tile)
			forceMove(free_tile)
		docked = null
		state = OVERMAP_SHIP_FLYING
		update_screen()
		return FALSE
	if(!docked && docked_object)
		// Shuttle moved onto a known POI Z (mining via in-shuttle console,
		// CentCom recall back to station, etc). Snap the icon onto it.
		forceMove(docked_object)
		docked = docked_object
		state = OVERMAP_SHIP_IDLE
		decelerate(max_speed)
		update_screen()
		return FALSE

/// Approximate ship mass from the bound shuttle's area turf count. Mass
/// drives the divisor in `burn_engines` so larger shuttles need beefier
/// engines to accelerate at the same rate.
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
/// Cached on `est_thrust` for the helm UI's "estimated burn" display.
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

/// Average percent fullness across enabled engines. Surfaced to the helm
/// pre-undock check.
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

/// Burn engines in `n_dir`; each contributes its `burn_engine(percentage)`
/// thrust output. The summed thrust is then divided by mass to drive
/// acceleration in tiles-per-tick. With no `n_dir`, decelerate.
/obj/structure/overmap/ship/simulated/proc/burn_engines(n_dir = null, percentage = 100)
	if(state != OVERMAP_SHIP_FLYING)
		return
	refresh_engines()
	if(!mass)
		calculate_mass()
	calculate_avg_fuel()
	var/thrust_used = 0
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in shuttle.engine_list)
		if(!engine.enabled)
			continue
		thrust_used += engine.burn_engine(percentage)
	est_thrust = thrust_used
	thrust_used = thrust_used / max(mass * 100, 1)
	log_game("OVERMAP BURN: raw_thrust=[est_thrust] mass=[mass] accel=[thrust_used] engines=[length(shuttle.engine_list)] dir=[n_dir]")
	if(n_dir)
		accelerate(n_dir, thrust_used)
	else
		decelerate(thrust_used)

/// Detach the ship from its current docked overmap object and start the
/// flight state. The shuttle itself is requested to launch with no target,
/// so it parks in transit until the player lines up a real dock via M6.
/obj/structure/overmap/ship/simulated/proc/undock()
	if(!is_still())
		decelerate(max_speed)
	if(!shuttle)
		return "Shuttle not found!"
	if(!docked)
		check_loc()
		return "Ship not docked!"
	prepare_for_flight()
	if(avg_fuel_amnt <= 0)
		return "Engines have no fuel!"
	shuttle.destination = null
	shuttle.mode = SHUTTLE_IGNITING
	shuttle.setTimer(shuttle.ignitionTime)
	addtimer(CALLBACK(src, PROC_REF(complete_undock)), shuttle.ignitionTime + (1 SECONDS))
	state = OVERMAP_SHIP_UNDOCKING
	return "Beginning undocking procedures..."

/// Called when the shuttle's ignition timer elapses. Move the icon off the
/// docked overmap object onto the underlying turf so the ship can fly.
/obj/structure/overmap/ship/simulated/proc/complete_undock()
	if(state != OVERMAP_SHIP_UNDOCKING)
		return
	if(docked)
		forceMove(get_turf(docked))
		docked = null
	state = OVERMAP_SHIP_FLYING
	update_screen()

/// Helm "Act" entry point. Validates adjacency and target type, then routes
/// to the appropriate handler. Levels dock; events / dynamic encounters
/// (deferred past prototype) get their own dispatch.
/obj/structure/overmap/ship/simulated/proc/overmap_object_act(obj/structure/overmap/target, mob/user)
	if(!target)
		return "No target."
	if(!(target in close_overmap_objects))
		return "Target not in range. Move closer first."
	if(istype(target, /obj/structure/overmap/level))
		return dock(target)
	return "Cannot interact with this object yet."

/// Try to resolve a stationary docking port for `target` and request the
/// shuttle to fly to it. Falls back through several naming conventions so
/// the prototype works with shipped TG mining shuttle docks
/// (`mining_home`, `mining_away`) without requiring map edits.
/obj/structure/overmap/ship/simulated/proc/dock(obj/structure/overmap/level/target)
	if(!is_still())
		return "Ship must be stopped to dock."
	if(state != OVERMAP_SHIP_FLYING)
		return "Ship is not in flight."
	if(!shuttle)
		return "Shuttle not found."

	// Notify any nav consoles bound to this shuttle so the player can also
	// use the nav UI to designate a custom landing spot on the target body.
	for(var/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/nav as anything in SSovermap.navs)
		if(nav.linked_port == shuttle)
			nav.set_target_level(target)

	// Candidate dock IDs in priority order: WS-canonical first, then TG
	// mining-shuttle patterns for prototype playability with stock maps.
	var/list/candidates = list(
		"[shuttle.shuttle_id]_[target.id]",
		"[OVERMAP_DOCK_PREFIX]_[target.id]",
	)
	if(istype(target, /obj/structure/overmap/level/main))
		candidates += "[shuttle.shuttle_id]_home"
	if(istype(target, /obj/structure/overmap/level/mining))
		candidates += "[shuttle.shuttle_id]_away"

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
		// No auto-resolvable dock. The nav console is now pre-filtered to the
		// target body, so the player can place a custom pad there.
		return "No automatic dock found - use the navigation computer to designate a landing pad on [target.name]."

	docked = target
	state = OVERMAP_SHIP_DOCKING
	shuttle.request(picked)
	addtimer(CALLBACK(src, PROC_REF(complete_dock)), shuttle.ignitionTime + (1 SECONDS))
	return "Commencing docking at [target.name]..."

/// Called once the shuttle's ignition + transit timers have fired. Snap the
/// icon onto the docked overmap object and return to idle.
/obj/structure/overmap/ship/simulated/proc/complete_dock()
	if(state != OVERMAP_SHIP_DOCKING)
		return
	if(docked)
		forceMove(docked)
	state = OVERMAP_SHIP_IDLE
	decelerate(max_speed)
	update_screen()

/// Override - if we're docked, freeze speed; if we're out of fuel, decay
/// speed to a halt instead of maintaining velocity forever.
/obj/structure/overmap/ship/simulated/tick_move()
	if(docked)
		decelerate(max_speed)
		if(movement_callback_id)
			deltimer(movement_callback_id)
			movement_callback_id = null
		return
	calculate_avg_fuel()
	if(avg_fuel_amnt < 1)
		decelerate(max_speed / 100)
	. = ..()

#undef MOVING
#undef SHIP_MOVE_RESOLUTION
#undef OVERMAP_MAGNITUDE
#undef SHIP_SIZE_THRESHOLD
#undef SHIP_DOCKED_REPAIR_TIME
