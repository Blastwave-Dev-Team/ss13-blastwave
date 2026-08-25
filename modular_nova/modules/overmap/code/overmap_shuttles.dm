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

/datum/map_template/shuttle/overmap/frigate/ikea_sma
	prefix = "_maps/shuttles/overmap/frigates/"
	port_id = "ikea"
	suffix = "sma"
	name = "Space Ikea Sma"
	description = "Space Ikea Base Model"
	admin_notes = "Space Ikea base ship, seats 3 or 4 -ish"

/datum/map_template/shuttle/overmap/frigate/nt_personal
	prefix = "_maps/shuttles/overmap/frigates/"
	port_id = "nt"
	suffix = "personal"
	name = "NT Personal"
	description = "Nanotrasen personal transport frigate."
	admin_notes = "Whiteship-style personal ship, comes with the Shipyard Fabricator crate."

/datum/map_template/shuttle/overmap/frigate/interdyne_cargo
	prefix = "_maps/shuttles/overmap/frigates/"
	port_id = "interdyne"
	suffix = "cargo"
	name = "Interdyne Cargo"
	description = "Interdyne offsite cargo shuttle. Roundstart hull for the Interdyne hangar."
	admin_notes = "Replaces ruin_interdyne_cargo. Docks as interdyne_cargo_mining / interdyne_cargo_des_two / whiteship_home."

/datum/map_template/shuttle/overmap/frigate/tarkon_driver
	prefix = "_maps/shuttles/overmap/frigates/"
	port_id = "tarkon"
	suffix = "driver"
	name = "Tarkon Driver"
	description = "Tarkon offsite shuttle. Roundstart hull for Port Tarkon."
	admin_notes = "Replaces ruin_tarkon_driver. Docks as tarkon_driver_escapefromtarkon / whiteship_home."

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

/obj/docking_port/mobile/overmap/frigate/ikea_sma
	name = "Space Ikea Sma"
	shuttle_id = "ikea_sma"
	preferred_direction = WEST
	port_direction = EAST // match map airlock facing when mapped
	area_type = /area/shuttle/overmap/frigate

/obj/docking_port/mobile/overmap/frigate/nt_personal
	name = "NT Personal"
	shuttle_id = "nt_personal"
	preferred_direction = SOUTH // match current map port; update if airlock facing changes
	port_direction = SOUTH
	area_type = /area/shuttle/overmap/frigate

/obj/docking_port/mobile/overmap/frigate/interdyne_cargo
	name = "Interdyne Cargo"
	shuttle_id = "interdyne_cargo"
	preferred_direction = EAST
	port_direction = SOUTH
	area_type = /area/shuttle/overmap/frigate/interdyne_cargo

/obj/docking_port/mobile/overmap/frigate/tarkon_driver
	name = "Tarkon Driver"
	shuttle_id = "tarkon_driver"
	preferred_direction = WEST
	port_direction = SOUTH
	area_type = /area/shuttle/overmap/frigate/tarkon_driver

