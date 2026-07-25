// MODULE ID: OVERMAP
// Nonblocking, current-phase construction previews for the shipyard fabricator.

/obj/effect/overlay/shipyard_projection
	name = "shipyard construction projection"
	desc = "A flickering holographic preview of the shipyard fabricator's current construction phase."
	anchored = TRUE
	density = FALSE
	mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	flags_1 = HOLOGRAM_1
	layer = ABOVE_MOB_LAYER
	var/datum/ship_plan_op/source_operation

/obj/effect/overlay/shipyard_projection/Initialize(mapload, datum/ship_plan_op/operation)
	. = ..()
	if(!operation || !configure_appearance(operation))
		return INITIALIZE_HINT_QDEL
	source_operation = operation
	makeHologram()

/obj/effect/overlay/shipyard_projection/proc/configure_appearance(datum/ship_plan_op/operation)
	var/appearance_path
	switch(operation.op_type)
		if(SHIPYARD_OP_RODS)
			icon = 'icons/obj/smooth_structures/lattice.dmi'
			icon_state = "lattice-0"
		if(SHIPYARD_OP_PLATING)
			appearance_path = /turf/open/floor/plating
		if(SHIPYARD_OP_GIRDER)
			appearance_path = /obj/structure/girder
		if(SHIPYARD_OP_MACHINE_FRAME)
			appearance_path = /obj/structure/frame/machine
		if(SHIPYARD_OP_COMPUTER_FRAME)
			appearance_path = /obj/structure/frame/computer
		if(SHIPYARD_OP_TURF, SHIPYARD_OP_OBJECT, SHIPYARD_OP_MACHINE, SHIPYARD_OP_COMPUTER)
			appearance_path = operation.target_path
		if(SHIPYARD_OP_COMMISSION)
			return FALSE
	if(appearance_path)
		if(!ispath(appearance_path, /atom))
			return FALSE
		var/atom/appearance_source = appearance_path
		icon = initial(appearance_source.icon)
		icon_state = initial(appearance_source.icon_state)
	if(!icon)
		return FALSE
	if("dir" in operation.desired_vars)
		setDir(operation.desired_vars["dir"])
	return TRUE
