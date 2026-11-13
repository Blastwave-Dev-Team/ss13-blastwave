/area/shuttle/custom/Destroy()
	// Created/destroyed dynamically (blueprints releaseArea, custom port teardown).
	// Parent Destroy does not clear areas_in_z; scrub every bucket because turfs
	// are often reparented before qdel, so src.z may be stale.
	// A template load registers each fresh area twice (initTemplateBounds, then
	// the area's own Initialize), so every copy has to go, not just the first.
	for(var/z_key in SSmapping.areas_in_z)
		var/list/areas_on_z = SSmapping.areas_in_z[z_key]
		while(src in areas_on_z)
			areas_on_z -= src
	return ..()
