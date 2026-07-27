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
	/// Tint of the projection. Null leaves the default holographic blue.
	var/holo_color

/obj/effect/overlay/shipyard_projection/Initialize(mapload, datum/ship_plan_op/operation)
	. = ..()
	if(!operation || !configure_appearance(operation))
		return INITIALIZE_HINT_QDEL
	source_operation = operation
	makeHologram(color_override = holo_color)

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
		// Everything that ends up as the mapped atom itself previews as that atom,
		// however it gets built. Leaving an operation kind out of this list is
		// silent: the projection finds no icon and deletes itself on the spot.
		if(SHIPYARD_OP_TURF, SHIPYARD_OP_OBJECT, SHIPYARD_OP_GENERATED, SHIPYARD_OP_MACHINE, SHIPYARD_OP_COMPUTER, SHIPYARD_OP_DECAL)
			appearance_path = operation.target_path
		if(SHIPYARD_OP_COMMISSION)
			return FALSE
	if(appearance_path)
		if(!ispath(appearance_path, /atom))
			return FALSE
		var/atom/appearance_source = appearance_path
		icon = initial(appearance_source.icon)
		icon_state = initial(appearance_source.icon_state)
		// Plenty of types leave icon_state empty and compose it in
		// update_icon_state() from base_icon_state, which never runs for a
		// preview that is only ever an appearance.
		if(!icon_state)
			icon_state = initial(appearance_source.base_icon_state)
	if(!icon || !icon_state)
		return FALSE
	if("dir" in operation.desired_vars)
		setDir(operation.desired_vars["dir"])
	return TRUE

/// Marks the tile a build stalled on, and outlives the phase that created it.
/obj/effect/overlay/shipyard_projection/fault
	name = "shipyard fault marker"
	desc = "A stuttering red projection marking the tile the shipyard fabricator could not build on."
	holo_color = COLOR_RED

/obj/effect/overlay/shipyard_projection/fault/configure_appearance(datum/ship_plan_op/operation)
	if(..())
		return TRUE
	// Nothing to preview for this kind of operation, so mark the tile itself.
	icon = 'icons/effects/alphacolors.dmi'
	icon_state = "red"
	return TRUE
