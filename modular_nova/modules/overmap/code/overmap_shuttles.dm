// MODULE ID: OVERMAP
// Shuttle templates and typed mobile ports for overmap vessels.

/// Sync mobile port name, default area, overmap ship icon, and helm GPS tags.
/proc/sync_shuttle_display_name(obj/docking_port/mobile/shuttle, new_name)
	if(!shuttle || !new_name)
		return
	shuttle.name = new_name
	if(istype(shuttle, /obj/docking_port/mobile/custom))
		var/obj/docking_port/mobile/custom/custom_shuttle = shuttle
		if(custom_shuttle.default_area)
			rename_area(custom_shuttle.default_area, new_name)
	if(shuttle.current_ship)
		shuttle.current_ship.name = new_name
		if(istype(shuttle.current_ship, /obj/structure/overmap/ship/simulated))
			var/obj/structure/overmap/ship/simulated/ship = shuttle.current_ship
			ship.sync_helm_gps_beacons()
	else if(SSovermap?.helms)
		for(var/obj/machinery/computer/helm/helm as anything in SSovermap.helms)
			var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(helm)
			if(port == shuttle)
				helm.sync_gps_beacon()

/datum/map_template/shuttle/overmap
	who_can_purchase = null // admin / manipulator only

/datum/map_template/shuttle/overmap/frigate
	port_id = "overmap_frigate" // parent; skipped (no suffix)

/datum/map_template/shuttle/overmap/frigate/solfed_cutter
	prefix = "_maps/shuttles/overmap/frigates/"
	port_id = "solfed"
	suffix = "cutter"
	name = "SolFed Cutter"
	description = "Sol Federation patrol frigate."
	admin_notes = "SolFed patrol frigate, seats 4 + 3 crew."

/datum/map_template/shuttle/overmap/frigate/solfed_patrol
	prefix = "_maps/shuttles/overmap/frigates/"
	port_id = "solfed"
	suffix = "patrol"
	name = "SolFed Patrol"
	description = "Sol Federation patrol frigate."
	admin_notes = "SolFed patrol frigate, seats 3 crew, 2 spacepods."

/// Not a vessel anyone is meant to fly: a hull carrying one of every mapped
/// object family the shipyard claims to build, so a single build exercises
/// every construction route instead of whatever the fleet happens to use.
/datum/map_template/shuttle/overmap/shipyard_validation
	prefix = "_maps/shuttles/overmap/test/"
	port_id = "shipyard"
	suffix = "validation"
	name = "Shipyard Validation Hull"
	description = "Route coverage fixture for the shipyard fabricator."
	admin_notes = "Test fixture, not a playable ship. Every construction route has a representative here."

/obj/docking_port/mobile/overmap
	name = "overmap vessel"

/obj/docking_port/mobile/overmap/frigate
	name = "frigate"
	area_type = /area/shuttle/overmap/frigate

/obj/docking_port/mobile/overmap/frigate/solfed_cutter
	name = "SolFed Cutter"
	shuttle_id = "solfed_cutter"
	preferred_direction = WEST
	port_direction = EAST // match map airlock facing when mapped
	area_type = /area/shuttle/overmap/frigate

/obj/docking_port/mobile/overmap/frigate/solfed_patrol
	name = "SolFed Patrol"
	shuttle_id = "solfed_patrol"
	preferred_direction = WEST
	port_direction = EAST // match map airlock facing when mapped
	area_type = /area/shuttle/overmap/frigate
