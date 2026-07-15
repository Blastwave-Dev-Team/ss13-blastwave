// MODULE ID: APC_SHUTTLE_ROTATE
// Clear leftover perpendicular pixels after setDir; skip ROTATE_OFFSET in shuttleRotate.

/obj/machinery/power/apc/setDir(newdir)
	. = ..()
	switch(dir)
		if(NORTH, SOUTH)
			pixel_x = 0
		if(EAST, WEST)
			pixel_y = 0
	var/image/hud_image = hud_list[MALF_APC_HUD]
	if(hud_image)
		hud_image.pixel_w = pixel_x
		hud_image.pixel_z = pixel_y

// Default params must match /atom/proc/shuttleRotate (child procs do not inherit them).
/obj/machinery/power/apc/shuttleRotate(rotation, params = ROTATE_DIR|ROTATE_SMOOTH|ROTATE_OFFSET)
	params &= ~ROTATE_OFFSET
	return ..()
