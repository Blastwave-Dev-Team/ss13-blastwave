// MODULE ID: OVERMAP
// Shuttle templates and typed mobile ports for overmap vessels.

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
