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
	name = "astrogation helm"
	desc = "Used to view or control the ship via the astrogation display. Handles throttle, heading, autopilot, and NavBall."
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
	/// User preference: emit GPS while landed. Forced off in transit regardless.
	var/gps_beacon_pref = TRUE

/obj/machinery/computer/helm/Initialize(mapload)
	. = ..()
	LAZYADD(SSovermap.helms, src)
	if(!viewer)
		AddComponent(/datum/component/gps, "SHIP", FALSE)
	// Round-start helms are bound by SSovermap.bind_existing_consoles(). Anything spawning
	// after the subsystem is up - shuttle templates included, since they Initialize with
	// mapload=TRUE - needs to bind itself here.
	if(SSovermap.initialized)
		set_ship()

/obj/machinery/computer/helm/Destroy()
	LAZYREMOVE(SSovermap.helms, src)
	current_ship = null
	return ..()

/obj/machinery/computer/helm/examine(mob/user)
	. = ..()
	if(viewer)
		return
	var/obj/structure/overmap/ship/simulated/ship = current_ship
	if(!istype(ship) || ship.state != OVERMAP_SHIP_IDLE || !ship.shuttle)
		return
	var/launch_block = ship.check_launch_clearance()
	if(launch_block)
		. += span_warning("Launch hold: bay exit obstructed. Clear a path to space or open the bay doors.")
	else
		. += span_notice("Launch path is clear.")

/// Rebind this helm to its target overmap object. Resolution priority:
///   1. `override_id` if set (admin / area_spawn flow)
///   2. The shuttle this helm is sitting on (`get_containing_shuttle`)
///   3. The main station POI if we're on a station Z
/obj/machinery/computer/helm/proc/set_ship(_id)
	if(_id)
		override_id = _id
	if(override_id)
		current_ship = SSovermap.get_overmap_object_by_id(override_id)
		sync_gps_beacon()
		return
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(src)
	if(port?.current_ship)
		current_ship = port.current_ship
		sync_gps_beacon()
		return
	if(is_station_level(z))
		current_ship = SSovermap.main
		sync_gps_beacon()
		return
	current_ship = null
	sync_gps_beacon()

/// Landed-only GPS beacon: tracking follows gps_beacon_pref while IDLE+docked.
/obj/machinery/computer/helm/proc/sync_gps_beacon()
	if(viewer)
		return
	var/datum/component/gps/gps = GetComponent(/datum/component/gps)
	if(!gps)
		return
	var/obj/structure/overmap/ship/simulated/ship = current_ship
	var/landed = istype(ship) && ship.state == OVERMAP_SHIP_IDLE && !!ship.docked
	gps.gpstag = istype(ship) ? ship.name : name
	gps.tracking = landed && gps_beacon_pref

/// Active GPS broadcasts grouped by the overmap object that owns their
/// physical location. Broadcasts deliberately bypass radar visibility:
/// transmitting a coordinate fix reveals that overmap location.
/obj/machinery/computer/helm/proc/get_overmap_gps_contacts()
	var/list/grouped = list()
	for(var/datum/component/gps/gps as anything in GLOB.GPS_list)
		if(!gps.tracking || gps.emped)
			continue
		var/atom/gps_parent = gps.parent
		if(!gps_parent || QDELETED(gps_parent))
			continue
		var/obj/structure/overmap/resolved = SSovermap.resolve_overmap_object_from_atom(gps_parent)
		if(!resolved || QDELETED(resolved))
			continue
		var/ref = REF(resolved)
		var/list/contact = grouped[ref]
		if(!contact)
			var/atom/position = istype(resolved.loc, /obj/structure/overmap) ? resolved.loc : resolved
			var/obj/structure/overmap/position_object = istype(position, /obj/structure/overmap) ? position : null
			contact = list(
				"name" = resolved.name,
				"ref" = ref,
				"tags" = list(),
				"bearing" = get_bearing_to(current_ship, position),
				"distance" = get_dist(current_ship, position),
				"x" = position.x,
				"y" = position.y,
				"offsetX" = position_object?.offset_x || 0,
				"offsetY" = position_object?.offset_y || 0,
				"local" = resolved == current_ship,
			)
			grouped[ref] = contact
		var/list/tags = contact["tags"]
		if(!(gps.gpstag in tags))
			tags += gps.gpstag
	var/list/contacts = list()
	for(var/ref in grouped)
		contacts += list(grouped[ref])
	return contacts

/obj/machinery/computer/helm/ui_interact(mob/user, datum/tgui/ui)
	if(!current_ship)
		set_ship()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		var/user_ref = REF(user)
		var/is_living = isliving(user)
		if(is_living)
			concurrent_users += user_ref
		if(length(concurrent_users) == 1 && is_living)
			playsound(src, 'sound/machines/terminal/terminal_on.ogg', 25, FALSE)
			use_energy(active_power_usage)
		// Refresh so vis_contents is populated and cam_background is sized
		// before the popup widget binds. Mirrors the CameraConsole pattern.
		current_ship?.update_screen(TRUE)
		ui = new(user, src, "HelmConsole", name)
		ui.open()
		// Window must exist before `display_to` so cam_screen + cam_background
		// register against the correct UI map slot.
		if(current_ship?.cam_screen)
			current_ship.cam_screen.display_to(user, ui.window)
	. = ..()

/obj/machinery/computer/helm/ui_close(mob/user)
	concurrent_users -= REF(user)
	if(current_ship?.cam_screen && user.client)
		current_ship.cam_screen.hide_from(user)
	if(!length(concurrent_users) && isliving(user))
		playsound(src, 'sound/machines/terminal/terminal_off.ogg', 25, FALSE)
	. = ..()

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
	var/obj/structure/overmap/ship/simulated/lz_ship = istype(current_ship, /obj/structure/overmap/ship/simulated) ? current_ship : null
	for(var/obj/structure/overmap/other in current_ship.close_overmap_objects)
		if(!SSovermap.can_view_installation(current_ship, other))
			continue
		var/ref = REF(other)
		if(ref in seen_refs)
			continue
		seen_refs |= ref
		var/list/contact_entry = list(
			"name" = other.name,
			"integrity" = other.integrity,
			"ref" = ref,
			"bearing" = get_bearing_to(current_ship, other),
			"distance" = get_dist(current_ship, other),
			"adjacent" = TRUE,
			"type" = get_contact_type(other),
		)
		// Adjacent POIs advertise their landing zones so the pilot can pick one to dock at.
		if(lz_ship && istype(other, /obj/structure/overmap/level))
			var/list/zone_entries = list()
			for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in lz_ship.get_landing_zones_for(other))
				zone_entries += list(list(
					"name" = zone.zone_name,
					"ref" = REF(zone),
					"width" = zone.zone_width,
					"height" = zone.zone_height,
				))
			if(length(zone_entries))
				contact_entry["landingZones"] = zone_entries
		.["otherInfo"] += list(contact_entry)
	if(istype(current_ship, /obj/structure/overmap/ship/simulated))
		var/obj/structure/overmap/ship/simulated/scan_ship = current_ship
		for(var/scan_ref in scan_ship.scanned_objects)
			if(scan_ref in seen_refs)
				continue
			var/obj/structure/overmap/scanned = locate(scan_ref)
			if(!scanned || QDELETED(scanned))
				continue
			if(!SSovermap.can_view_installation(current_ship, scanned))
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
	var/obj/structure/overmap/positional_object = istype(positional, /obj/structure/overmap) ? positional : null
	.["x"] = positional.x
	.["y"] = positional.y
	.["offsetX"] = positional_object?.offset_x || 0
	.["offsetY"] = positional_object?.offset_y || 0
	.["gpsContacts"] = get_overmap_gps_contacts()
	if(current_ship.camera_size_x && current_ship.camera_size_y)
		.["mapView"] = list(
			"minX" = current_ship.camera_min_x,
			"minY" = current_ship.camera_min_y,
			"sizeX" = current_ship.camera_size_x,
			"sizeY" = current_ship.camera_size_y,
		)

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
	.["shipInfo"]["disabled"] = ship.integrity <= 0
	.["emergencyBraking"] = ship.emergency_braking
	var/datum/component/gps/gps = GetComponent(/datum/component/gps)
	.["gpsBeacon"] = !!gps?.tracking
	.["gpsBeaconPref"] = gps_beacon_pref
	.["gpsBeaconLanded"] = ship.state == OVERMAP_SHIP_IDLE && !!ship.docked
	var/list/open_space_data = list(
		"x" = positional.x,
		"y" = positional.y,
		"available" = ship.state == OVERMAP_SHIP_FLYING && ship.is_still() && !ship.docked,
		"landingZones" = list(),
	)
	var/turf/current_overmap_tile = get_turf(ship)
	var/obj/structure/overmap/level/site/open_space/existing_open_site = locate(/obj/structure/overmap/level/site/open_space) in current_overmap_tile
	if(existing_open_site)
		open_space_data["siteRef"] = REF(existing_open_site)
		for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in ship.get_landing_zones_for(existing_open_site))
			open_space_data["landingZones"] += list(list(
				"name" = zone.zone_name,
				"ref" = REF(zone),
				"width" = zone.zone_width,
				"height" = zone.zone_height,
			))
	.["openSpace"] = open_space_data

	var/speed = ship.get_speed()
	var/heading_deg = ship.is_still() ? round((90 - ship.desired_angle + 360) % 360) : ship.get_heading_degrees()
	.["speed"] = speed
	.["maxSpeed"] = ship.max_speed
	.["heading"] = heading_deg
	.["actual_angle"] = ship.is_still() ? 0 : -(TORADIANS(arctan(ship.vel_x, ship.vel_y)))
	// Engine loss can leave velocity temporarily above the reduced assisted
	// envelope; keep the existing NavBall's normalized input bounded.
	var/speed_reference = ship.max_speed > 0 ? ship.max_speed : OVERMAP_MAX_SPEED
	.["actual_speed"] = ship.is_still() ? 0 : clamp(speed / speed_reference, 0, 1)
	.["desired_angle"] = -(TORADIANS(ship.desired_angle))
	.["desired_throttle"] = ship.desired_throttle
	.["station_keeping"] = ship.station_keeping
	.["target_mol_s"] = round(ship.target_mol_s, 0.001)
	.["delivered_mol_s"] = round(ship.delivered_mol_s, 0.001)
	.["spool_pct"] = ship.target_mol_s > OVERMAP_MOL_S_EPSILON \
		? round(clamp(ship.delivered_mol_s / ship.target_mol_s, 0, 1), 0.001) \
		: 0

	.["engineInfo"] = list()
	if(ship.shuttle)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine in ship.shuttle.engine_list)
			var/obj/machinery/overmap/fuel_injector/injector = engine.get_linked_injector()
			var/list/engine_entry = list(
				"name" = engine.name,
				"fuel" = engine.return_fuel(),
				"maxFuel" = engine.return_fuel_cap(),
				"enabled" = engine.enabled,
				"broken" = !!(engine.machine_stat & BROKEN),
				"ref" = REF(engine),
				"fuelSource" = injector ? "injector" : (istype(engine, /obj/machinery/power/shuttle_engine/overmap/standard) ? "hall-only" : "none"),
			)
			if(injector)
				engine_entry["pressure"] = round(injector.return_chamber_pressure(), 0.1)
				engine_entry["temperature"] = round(injector.return_chamber_temperature(), 0.1)
				engine_entry["feedPressure"] = round(injector.return_feed_pressure(), 0.1)
				engine_entry["linkType"] = engine.link_via_pipe ? "piped" : "adjacent"
				engine_entry["shareCount"] = fuel_injector_count_active_share_engines(injector)
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
			ship.full_stop()
			return TRUE
		if("emergency_brake")
			if(!ship.engage_emergency_brake())
				say("Emergency brake unavailable while stopped, docked, or already active.")
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
			ship.full_stop()
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
			if(!SSovermap.can_view_installation(current_ship, target))
				say("Unable to establish link with target.")
				return TRUE
			say(ship.overmap_object_act(target, usr, params["lz"]))
			return TRUE
		if("land_open_space")
			say(ship.land_in_open_space(params["lz"]))
			return TRUE
		if("act_overmap")
			var/obj/structure/overmap/target = locate(params["ship_to_act"]) in current_ship.close_overmap_objects
			if(!target)
				return TRUE
			if(!SSovermap.can_view_installation(current_ship, target))
				say("Unable to establish link with target.")
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
		if("toggle_gps")
			if(ship.state != OVERMAP_SHIP_IDLE || !ship.docked)
				say("No valid coordinate fix. Surface GPS broadcast unavailable while in transit.")
				return TRUE
			gps_beacon_pref = !gps_beacon_pref
			sync_gps_beacon()
			say(gps_beacon_pref ? "Surface GPS beacon active." : "Surface GPS beacon silenced.")
			return TRUE
	return FALSE

/// Read-only viewscreen variant - no controls, just renders the overmap of
/// whatever ship the parent helm console is bound to. Used in cockpits where
/// you want passengers to see the map without being able to fly.
/obj/machinery/computer/helm/viewscreen
	name = "astrogation viewscreen"
	icon = 'icons/obj/wallmounts.dmi'
	icon_state = "telescreen"
	// wallmounts.dmi has no keyboard/screen overlay states; the base computer
	// overlays ("tech_key" keyboard, emissive icon_screen) runtime without these.
	icon_keyboard = null
	icon_screen = null
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
