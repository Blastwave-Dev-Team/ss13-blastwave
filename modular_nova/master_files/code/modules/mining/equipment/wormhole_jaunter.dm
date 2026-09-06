// MODULE ID: BLASTWAVE_BLUESPACE
// The jaunter picks its own exit, so it never reaches the
// check_teleport_valid() gate that stops every other bluespace teleport. Filter
// interdicted beacons out of the candidate list instead; if that empties the
// list the jaunter already has a "no destinations" failure path.
/obj/item/wormhole_jaunter/get_destinations()
	var/list/destinations = ..()
	for(var/obj/item/beacon/beacon as anything in destinations)
		var/turf/beacon_turf = get_turf(beacon)
		if(isnull(beacon_turf) || is_teleport_jammed(beacon_turf.z))
			destinations -= beacon

	return destinations
