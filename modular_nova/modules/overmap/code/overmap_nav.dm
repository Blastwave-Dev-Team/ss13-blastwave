// MODULE ID: OVERMAP
// Nav console - shuttle docker subtype that reads its Z-lock from the
// bound ship's pending docking state. The helm writes that state via
// `ship.set_nav_target()` when no automatic dock is found; the nav
// picks it up lazily when the player opens the console.

/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav
	name = "overmap navigation computer"
	desc = "Designates a landing pad on whatever overmap body the bound shuttle is currently next to."
	circuit = /obj/item/circuitboard/computer/shuttle/overmap_nav
	whitelist_turfs = list(
		/turf/open/space,
		/turf/open/floor/plating,
		/turf/open/lava,
		/turf/open/openspace,
		/turf/open/misc,
	)
	locked_traits = list(ZTRAIT_RESERVED, ZTRAIT_CENTCOM)
	/// The mobile docking port this nav is bound to. Set by `link_shuttle()`.
	var/obj/docking_port/mobile/linked_port
	/// Cached landing zones valid for the current target. Rebuilt on sync.
	var/list/obj/effect/landmark/overmap_landing_zone/target_zones

/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/Initialize(mapload)
	. = ..()
	LAZYADD(SSovermap.navs, src)
	actions += new /datum/action/innate/camera_jump/landing_zone(src)
	if(SSovermap.initialized)
		link_shuttle()

/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/Destroy()
	LAZYREMOVE(SSovermap.navs, src)
	linked_port = null
	target_zones = null
	return ..()

/// Bind this nav to the shuttle that contains it.
/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/proc/link_shuttle()
	linked_port = SSshuttle.get_containing_shuttle(src)
	if(!linked_port)
		return
	shuttleId = linked_port.shuttle_id

/// Before opening the camera eye, pull the current nav-docking state from
/// the bound ship and apply it to `z_lock` / `jump_to_ports`. This replaces
/// the old push-based `set_target_level()` cross-machine call.
/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/attack_hand(mob/user, list/modifiers)
	if(!linked_port)
		link_shuttle()
	var/obj/structure/overmap/ship/simulated/ship = linked_port?.current_ship
	if(ship)
		sync_from_ship(ship)
	return ..()

/// Read the ship's pending docking state and configure this console's
/// z_lock, jump_to_ports, and landing zone cache accordingly.
/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/proc/sync_from_ship(obj/structure/overmap/ship/simulated/ship)
	if(!length(ship.nav_dock_zs))
		z_lock = list()
		target_zones = null
		return
	z_lock = ship.nav_dock_zs.Copy()
	for(var/port_id in jump_to_ports.Copy())
		remove_jumpable_port(port_id)
	for(var/dock_id in ship.nav_dock_ids)
		add_jumpable_port(dock_id)
	discover_landing_zones()

/// Find landing zones on the target Zs that the bound shuttle can fit within.
/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/proc/discover_landing_zones()
	target_zones = list()
	if(!shuttle_port && shuttleId)
		shuttle_port = SSshuttle.getShuttle(shuttleId)
	if(!shuttle_port)
		return
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in SSovermap.landing_zones)
		if(!(zone.z in z_lock))
			continue
		if(!zone.can_fit_shuttle(shuttle_port.width, shuttle_port.height))
			continue
		target_zones += zone

/// Override checkLandingSpot to additionally validate that the shuttle bbox
/// is entirely within a landing zone (if zones exist on the target Z).
/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/checkLandingSpot()
	. = ..()
	if(. != SHUTTLE_DOCKER_LANDING_CLEAR)
		return
	if(!length(target_zones))
		return
	var/mob/eye/camera/remote/shuttle_docker/the_eye = eyeobj
	var/turf/eyeturf = get_turf(the_eye)
	if(!eyeturf)
		return SHUTTLE_DOCKER_BLOCKED
	var/list/bounds = shuttle_port.return_coords(eyeturf.x - x_offset, eyeturf.y - y_offset, the_eye.dir)
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in target_zones)
		if(zone.contains_bbox(bounds[1], bounds[2], bounds[3], bounds[4], eyeturf.z))
			return SHUTTLE_DOCKER_LANDING_CLEAR
	return SHUTTLE_DOCKER_BLOCKED

// --- Landing Zone Jump Action ---

/datum/action/innate/camera_jump/landing_zone
	name = "Jump to Landing Zone"
	button_icon_state = "camera_jump"

/datum/action/innate/camera_jump/landing_zone/Activate()
	if(QDELETED(owner) || !isliving(owner))
		return
	var/mob/eye/camera/remote/remote_eye = owner.remote_control
	if(!remote_eye)
		return
	var/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/console = remote_eye.origin_ref?.resolve()
	if(!istype(console))
		return

	if(!length(console.target_zones))
		to_chat(owner, span_warning("No landing zones detected on the target body."))
		playsound(console, 'sound/machines/terminal/terminal_prompt_deny.ogg', 25, FALSE)
		return

	playsound(console, 'sound/machines/terminal/terminal_prompt.ogg', 25, FALSE)
	var/list/choices = list()
	for(var/obj/effect/landmark/overmap_landing_zone/zone as anything in console.target_zones)
		choices["[zone.zone_name] ([zone.zone_width]x[zone.zone_height])"] = zone

	var/selected = tgui_input_list(owner, "Choose a landing zone", "Landing Zones", choices)
	if(isnull(selected))
		playsound(console, 'sound/machines/terminal/terminal_prompt_deny.ogg', 25, FALSE)
		return
	if(QDELETED(src) || QDELETED(owner) || !isliving(owner))
		return

	var/obj/effect/landmark/overmap_landing_zone/chosen = choices[selected]
	if(!chosen)
		return
	var/turf/center = chosen.get_center_turf()
	if(!center)
		return

	playsound(console, 'sound/machines/terminal/terminal_prompt_confirm.ogg', 25, FALSE)
	remote_eye.setLoc(center)
	to_chat(owner, span_notice("Jumped to [chosen.zone_name]."))
	owner.overlay_fullscreen("flash", /atom/movable/screen/fullscreen/flash/static)
	owner.clear_fullscreen("flash", 3)
