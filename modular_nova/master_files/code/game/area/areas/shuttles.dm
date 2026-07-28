/area/shuttle/custom/Destroy()
	// Created/destroyed dynamically (blueprints releaseArea, custom port teardown).
	// Parent Destroy does not clear areas_in_z; scrub every bucket because turfs
	// are often reparented before qdel, so src.z may be stale.
	for(var/z_key in SSmapping.areas_in_z)
		SSmapping.areas_in_z[z_key] -= src
	return ..()
