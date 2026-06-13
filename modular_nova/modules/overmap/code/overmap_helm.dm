// MODULE ID: OVERMAP
// Helm console - sits next to a shuttle's engines, registers the bound
// `/ship/simulated`'s map widget, and surfaces the overmap UI. Two flavors:
// the interactive helm (grants pilot control) and a viewscreen subtype
// (read-only window that just shows the overmap).
//
// M4 lights up the data path: opens, registers the map, ships data to the
// HelmConsole.tsx UI, but action handling for change_heading/stop/undock
// are implemented in M5 and act_overmap (docking) in M6.

/obj/machinery/computer/helm
	name = "helm control console"
	desc = "Used to view or control the ship via the overmap."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	circuit = /obj/item/circuitboard/computer/shuttle/helm
	light_color = LIGHT_COLOR_FLARE
	/// The overmap object this helm is currently bound to (typically the ship the helm sits on).
	var/obj/structure/overmap/current_ship
	/// Tracking for terminal-on/off ambience and use_energy.
	var/list/concurrent_users = list()
	/// If TRUE, omit pilot controls. Used by the viewscreen subtype.
	var/viewer = FALSE
	/// Optional override - set via VV or area_spawn to bind this helm to a specific overmap object.
	var/override_id

/obj/machinery/computer/helm/Initialize(mapload)
	. = ..()
	LAZYADD(SSovermap.helms, src)
	// Round-start helms are bound by SSovermap.bind_existing_consoles(). Anything spawning
	// after the subsystem is up - shuttle templates included, since they Initialize with
	// mapload=TRUE - needs to bind itself here.
	if(SSovermap.initialized)
		set_ship()

/obj/machinery/computer/helm/Destroy()
	LAZYREMOVE(SSovermap.helms, src)
	current_ship = null
	return ..()

/// Rebind this helm to its target overmap object. Resolution priority:
///   1. `override_id` if set (admin / area_spawn flow)
///   2. The shuttle this helm is sitting on (`get_containing_shuttle`)
///   3. The main station POI if we're on a station Z
/obj/machinery/computer/helm/proc/set_ship(_id)
	if(_id)
		override_id = _id
	if(override_id)
		current_ship = SSovermap.get_overmap_object_by_id(override_id)
		return
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(src)
	if(port?.current_ship)
		current_ship = port.current_ship
		return
	if(is_station_level(z))
		current_ship = SSovermap.main
		return
	current_ship = null

/obj/machinery/computer/helm/ui_interact(mob/user, datum/tgui/ui)
	if(!current_ship)
		set_ship()
	ui = SStgui.try_update_ui(user, src, ui)
	if(ui)
		return
	var/user_ref = REF(user)
	var/is_living = isliving(user)
	if(is_living)
		concurrent_users += user_ref
	if(length(concurrent_users) == 1 && is_living)
		playsound(src, 'sound/machines/terminal/terminal_on.ogg', 25, FALSE)
		use_energy(active_power_usage)
	// Refresh so vis_contents is populated and cam_background is sized
	// before the popup widget binds. Mirrors the CameraConsole pattern.
	current_ship?.update_screen()
	ui = new(user, src, "HelmConsole", name)
	ui.open()
	// Window must exist before `display_to` so cam_screen + cam_background
	// register against the correct UI map slot.
	if(current_ship?.cam_screen)
		current_ship.cam_screen.display_to(user, ui.window)

/obj/machinery/computer/helm/ui_close(mob/user)
	concurrent_users -= REF(user)
	if(current_ship?.cam_screen && user.client)
		current_ship.cam_screen.hide_from(user)
	if(!length(concurrent_users) && isliving(user))
		playsound(src, 'sound/machines/terminal/terminal_off.ogg', 25, FALSE)

/obj/machinery/computer/helm/ui_static_data(mob/user)
	. = list()
	.["isViewer"] = viewer
	.["mapRef"] = current_ship?.cam_screen?.assigned_map

/obj/machinery/computer/helm/ui_data(mob/user)
	. = list()
	if(!current_ship)
		.["canFly"] = FALSE
		return
	.["canFly"] = istype(current_ship, /obj/structure/overmap/ship/simulated)
	.["shipInfo"] = list(
		"name" = current_ship.name,
		"class" = istype(current_ship, /obj/structure/overmap/ship) ? "Ship" : istype(current_ship, /obj/structure/overmap/level) ? "Body" : "Station",
		"integrity" = current_ship.integrity,
		"sensor_range" = current_ship.sensor_range,
		"ref" = REF(current_ship),
	)
	.["otherInfo"] = list()
	var/list/seen_refs = list()
	for(var/obj/structure/overmap/other in current_ship.close_overmap_objects)
		var/ref = REF(other)
		seen_refs += ref
		.["otherInfo"] += list(list(
			"name" = other.name,
			"integrity" = other.integrity,
			"ref" = ref,
			"bearing" = get_bearing_to(current_ship, other),
			"distance" = get_dist(current_ship, other),
			"adjacent" = TRUE,
			"type" = get_contact_type(other),
		))
	if(istype(current_ship, /obj/structure/overmap/ship/simulated))
		var/obj/structure/overmap/ship/simulated/scan_ship = current_ship
		for(var/scan_ref in scan_ship.scanned_objects)
			if(scan_ref in seen_refs)
				continue
			var/obj/structure/overmap/scanned = locate(scan_ref)
			if(!scanned || QDELETED(scanned))
				continue
			.["otherInfo"] += list(list(
				"name" = scanned.name,
				"integrity" = scanned.integrity,
				"ref" = scan_ref,
				"bearing" = get_bearing_to(current_ship, scanned),
				"distance" = get_dist(current_ship, scanned),
				"adjacent" = FALSE,
				"type" = get_contact_type(scanned),
			))
	var/atom/positional = istype(current_ship.loc, /obj/structure/overmap) ? current_ship.loc : current_ship
	.["x"] = positional.x
	.["y"] = positional.y

	if(!istype(current_ship, /obj/structure/overmap/ship/simulated))
		return

	var/obj/structure/overmap/ship/simulated/ship = current_ship
	.["state"] = ship.state
	.["docked"] = !!ship.docked
	.["stopped"] = ship.is_still()
	.["consoleControl"] = !!(ship.control_flags & SHIP_CONTROL_CONSOLE)
	.["scanReady"] = COOLDOWN_FINISHED(ship, scan_cooldown)
	.["shipInfo"]["mass"] = ship.mass
	.["shipInfo"]["est_thrust"] = ship.est_thrust

	var/speed = ship.get_speed()
	var/heading_deg = ship.get_heading_degrees()
	.["speed"] = speed
	.["maxSpeed"] = ship.max_speed
	.["heading"] = heading_deg
	.["actual_angle"] = ship.is_still() ? 0 : -(TORADIANS(arctan(ship.vel_x, ship.vel_y)))
	.["actual_speed"] = ship.max_speed > 0 ? speed / ship.max_speed : 0
	.["desired_angle"] = -(TORADIANS(ship.desired_angle))
	.["desired_throttle"] = ship.desired_throttle
	.["station_keeping"] = ship.station_keeping

	.["engineInfo"] = list()
	if(ship.shuttle)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine in ship.shuttle.engine_list)
			var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
			var/list/engine_entry = list(
				"name" = engine.name,
				"fuel" = engine.return_fuel(),
				"maxFuel" = engine.return_fuel_cap(),
				"enabled" = engine.enabled,
				"ref" = REF(engine),
				"fuelSource" = injector ? "injector" : (engine.fuel_core ? "core" : "none"),
			)
			if(injector)
				engine_entry["pressure"] = round(injector.return_chamber_pressure(), 0.1)
				engine_entry["temperature"] = round(injector.return_chamber_temperature(), 0.1)
			.["engineInfo"] += list(engine_entry)

/obj/machinery/computer/helm/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	if(viewer)
		return
	switch(action)
		if("reload_ship")
			set_ship()
			return TRUE
	if(!istype(current_ship, /obj/structure/overmap/ship/simulated))
		return FALSE
	var/obj/structure/overmap/ship/simulated/ship = current_ship
	if(!(ship.control_flags & SHIP_CONTROL_CONSOLE))
		to_chat(usr, span_warning("This vessel does not support console-based control."))
		return FALSE
	switch(action)
		if("toggle_engine")
			var/obj/machinery/power/shuttle_engine/overmap/engine = locate(params["engine"]) in (ship.shuttle?.engine_list || list())
			if(!engine)
				return
			engine.enabled = !engine.enabled
			engine.update_engine()
			engine.update_icon_state()
			ship.refresh_engines()
			return TRUE
		if("reload_engines")
			ship.refresh_engines()
			return TRUE
		if("set_desired")
			var/angle = text2num(params["angle"])
			var/throttle = text2num(params["throttle"])
			if(isnull(angle) || isnull(throttle))
				return
			ship.set_desired(TODEGREES(-angle), throttle)
			return TRUE
		if("all_stop")
			ship.all_stop()
			return TRUE
		if("toggle_lock")
			ship.station_keeping = !ship.station_keeping
			return TRUE
		if("change_heading")
			var/dir = text2num(params["dir"])
			if(!dir)
				return
			ship.burn_engines(dir)
			return TRUE
		if("stop")
			ship.all_stop()
			return TRUE
		if("undock")
			ship.calculate_avg_fuel()
			if(ship.avg_fuel_amnt < 25 && tgui_alert(usr, "Ship only has [round(ship.avg_fuel_amnt)]% fuel remaining. Are you sure you want to undock?", name, list("Yes", "No")) != "Yes")
				return TRUE
			say(ship.undock())
			return TRUE
		if("dock")
			var/obj/structure/overmap/target = locate(params["target"]) in current_ship.close_overmap_objects
			if(!target)
				return TRUE
			say(ship.overmap_object_act(target, usr))
			return TRUE
		if("act_overmap")
			var/obj/structure/overmap/target = locate(params["ship_to_act"]) in current_ship.close_overmap_objects
			if(!target)
				return TRUE
			say(ship.overmap_object_act(target, usr))
			return TRUE
		if("scan")
			var/count = ship.scan()
			if(count)
				say("Scan complete: [count] contact\s detected.")
			else
				say("Scan on cooldown or no contacts in range.")
			return TRUE
	return FALSE

/// Read-only viewscreen variant - no controls, just renders the overmap of
/// whatever ship the parent helm console is bound to. Used in cockpits where
/// you want passengers to see the map without being able to fly.
/obj/machinery/computer/helm/viewscreen
	name = "ship viewscreen"
	icon = 'icons/obj/machines/wallmounts.dmi'
	icon_state = "telescreen"
	layer = SIGN_LAYER
	density = FALSE
	viewer = TRUE
	circuit = /obj/item/circuitboard/computer/shuttle/helm/viewscreen

/// Returns the bearing in degrees (0=north, clockwise) from `origin` to `target`.
/proc/get_bearing_to(atom/origin, atom/target)
	var/dx = target.x - origin.x
	var/dy = target.y - origin.y
	if(!dx && !dy)
		return 0
	var/angle = arctan(dx, dy)
	if(angle < 0)
		angle += 360
	return round(angle)

/// Returns a string type classification for an overmap contact.
/proc/get_contact_type(obj/structure/overmap/O)
	if(istype(O, /obj/structure/overmap/dynamic))
		return "dynamic"
	if(istype(O, /obj/structure/overmap/event))
		return "event"
	if(istype(O, /obj/structure/overmap/ship))
		return "ship"
	if(istype(O, /obj/structure/overmap/level))
		return "level"
	return "unknown"
