// MODULE ID: OVERMAP
// Nav console - takes the helm's "Act" docking request and resolves a
// landing pad on the target body. M4 declares the type and registration
// surface so SSovermap.bind_existing_consoles compiles; the actual
// place_landing_spot override + z_lock plumbing lands in M6.

/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav
	name = "overmap navigation computer"
	desc = "Designates a landing pad on whatever overmap body the bound shuttle is currently next to."
	circuit = /obj/item/circuitboard/computer/shuttle/overmap_nav
	// Don't lock to /turf/open/space - we want to land on lavaland / icebox.
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
	/// The currently-targeted overmap body, if any. Set by simulated.dock()
	/// when the helm "Act"s on a body. Drives `z_lock` filtering so the
	/// player can only place landing pads on the active target's Zs.
	var/obj/structure/overmap/level/target_level

/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/Initialize(mapload)
	. = ..()
	LAZYADD(SSovermap.navs, src)
	// See helm.Initialize: shuttle templates load with mapload=TRUE post-roundstart via
	// InitializeAtoms, so we bind unconditionally once SSovermap is up.
	if(SSovermap.initialized)
		link_shuttle()

/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/Destroy()
	LAZYREMOVE(SSovermap.navs, src)
	linked_port = null
	target_level = null
	return ..()

/// Bind this nav to the shuttle that contains it. After `link_shuttle()` the
/// nav console is wired against the right mobile port; `set_target_level()`
/// further narrows where the player can place a pad to the active overmap
/// target's `linked_levels`.
/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/proc/link_shuttle()
	linked_port = SSshuttle.get_containing_shuttle(src)
	if(!linked_port)
		return
	shuttleId = linked_port.shuttle_id

/// Called from `simulated.dock()` to filter `z_lock` and `jump_to_ports` to
/// the body the helm just Act'd on. The player walks from helm to nav and
/// designates a landing pad with the existing shuttle_docker UI; that pad
/// becomes the target of the next launch via the standard `placeLandingSpot`.
/obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav/proc/set_target_level(obj/structure/overmap/level/target)
	target_level = target
	if(!target)
		z_lock = list()
		return
	z_lock = target.linked_levels.Copy()
	for(var/port_id in jump_to_ports.Copy())
		remove_jumpable_port(port_id)
	if(linked_port)
		add_jumpable_port("[linked_port.shuttle_id]_[target.id]")
	add_jumpable_port("[OVERMAP_DOCK_PREFIX]_[target.id]")
	refresh_eye()
