// MODULE ID: OVERMAP
// Area spawn entry for the wall-mount NT distress beacon.
// Places via automapper on roundstart so no TG .dmm edits are needed.

/datum/area_spawn/distress_beacon
	target_areas = list(/area/station/command/bridge, /area/station/command/meeting_room)
	desired_atom = /obj/machinery/distress_beacon
	mode = AREA_SPAWN_MODE_MOUNT_WALL
