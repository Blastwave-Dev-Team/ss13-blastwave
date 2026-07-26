// MODULE ID: OVERMAP
// Execution and verification for declarative ship-plan operations.

/datum/ship_plan_op/proc/satisfied(turf/work_turf)
	if(!work_turf)
		return FALSE
	switch(op_type)
		if(SHIPYARD_OP_RODS)
			return HAS_TRAIT_FROM(work_turf, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE)
		if(SHIPYARD_OP_PLATING)
			return istype(work_turf, /turf/open/floor/plating)
		if(SHIPYARD_OP_GIRDER)
			return !!(locate(/obj/structure/girder) in work_turf)
		if(SHIPYARD_OP_MACHINE_FRAME)
			return !!(locate(/obj/structure/frame/machine) in work_turf)
		if(SHIPYARD_OP_COMPUTER_FRAME)
			return !!(locate(/obj/structure/frame/computer) in work_turf)
		if(SHIPYARD_OP_TURF)
			return istype(work_turf, target_path)
		if(SHIPYARD_OP_OBJECT, SHIPYARD_OP_GENERATED, SHIPYARD_OP_MACHINE, SHIPYARD_OP_COMPUTER, SHIPYARD_OP_COMMISSION)
			return !!(locate(target_path) in work_turf)
		if(SHIPYARD_OP_DECAL)
			// Paint leaves no object on the turf to detect, so it is always
			// pending until the build index moves past it.
			return FALSE
	return FALSE

/// Execute one operation. TRUE means complete, null means a replenishable
/// resource wait, and text means a world-state fault that needs intervention.
/datum/ship_plan_op/proc/execute(obj/machinery/shipyard_fabricator/fabricator)
	var/obj/effect/landmark/overmap_landing_zone/zone = fabricator.claimed_zone?.resolve()
	var/turf/work_turf = fabricator.get_operation_turf(src, zone)
	if(!zone || !work_turf || !zone.contains_turf(work_turf))
		return "Operation target is outside the claimed landing zone."
	if(satisfied(work_turf) && op_type != SHIPYARD_OP_COMMISSION)
		return TRUE
	if(length(material_cost))
		if(!fabricator.materials?.mat_container?.has_materials(material_cost, fabricator.material_cost_multiplier))
			fabricator.paused_reason = "Ore silo lacks material for [op_type] at ([work_turf.x], [work_turf.y])."
			return null

	fabricator.play_placement_effect(work_turf)

	var/result
	switch(op_type)
		if(SHIPYARD_OP_RODS)
			result = execute_rods(work_turf)
		if(SHIPYARD_OP_PLATING)
			result = execute_plating(work_turf)
		if(SHIPYARD_OP_GIRDER)
			result = execute_girder(work_turf)
		if(SHIPYARD_OP_MACHINE_FRAME)
			result = execute_machine_frame(work_turf)
		if(SHIPYARD_OP_COMPUTER_FRAME)
			result = execute_computer_frame(work_turf)
		if(SHIPYARD_OP_TURF)
			result = execute_turf(work_turf)
		if(SHIPYARD_OP_OBJECT)
			result = execute_object(work_turf)
		if(SHIPYARD_OP_DECAL)
			result = execute_decal(work_turf)
		if(SHIPYARD_OP_GENERATED)
			result = execute_generated(work_turf, fabricator)
		if(SHIPYARD_OP_MACHINE)
			result = execute_machine(work_turf, fabricator)
		if(SHIPYARD_OP_COMPUTER)
			result = execute_computer(work_turf, fabricator)
		if(SHIPYARD_OP_COMMISSION)
			result = execute_commission(work_turf)
		else
			return "Unknown shipyard operation '[op_type]'."
	if(result != TRUE)
		return result
	if(length(material_cost))
		fabricator.materials.use_materials(
			material_cost,
			coefficient = fabricator.material_cost_multiplier,
			action = "fabricate",
			name = fabricator.blueprint_disk?.ship_plan?.name || "ship",
		)
	return TRUE

/datum/ship_plan_op/proc/execute_rods(turf/open/work_turf)
	if(!istype(work_turf) || !isfloorturf(work_turf))
		return "Hull rods require an open floor."
	if(HAS_TRAIT(work_turf, TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		return TRUE
	var/obj/item/stack/rods/shuttle/rods = new(work_turf, 1)
	var/handled = work_turf.build_shuttle_frame_with_rods(rods, null)
	qdel(rods)
	return handled && HAS_TRAIT_FROM(work_turf, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE) \
		? TRUE \
		: "Unable to anchor shuttle frame rods on this turf."

/datum/ship_plan_op/proc/execute_plating(turf/open/work_turf)
	if(!istype(work_turf))
		return "Hull plating requires an open turf."
	if(!HAS_TRAIT_FROM(work_turf, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return "Shuttle frame rods are missing beneath this hull tile."
	var/obj/item/stack/tile/iron/tiles = new(work_turf, 1)
	var/handled = work_turf.shuttle_frame_build_plating_with_tile(tiles, null)
	qdel(tiles)
	return handled ? TRUE : "Unable to plate this shuttle frame tile."

/datum/ship_plan_op/proc/execute_girder(turf/work_turf)
	if(!isfloorturf(work_turf))
		return "Girder placement requires shuttle plating."
	if(locate(/obj/structure/girder) in work_turf)
		return TRUE
	new /obj/structure/girder(work_turf)
	return TRUE

/datum/ship_plan_op/proc/execute_machine_frame(turf/work_turf)
	if(!isfloorturf(work_turf))
		return "Machine frame placement requires shuttle plating."
	if(locate(/obj/structure/frame) in work_turf)
		return "Another construction frame occupies this tile."
	var/obj/structure/frame/machine/secured/frame = new(work_turf)
	frame.set_anchored(TRUE)
	return TRUE

/datum/ship_plan_op/proc/execute_computer_frame(turf/work_turf)
	if(!isfloorturf(work_turf))
		return "Computer frame placement requires shuttle plating."
	if(locate(/obj/structure/frame) in work_turf)
		return "Another construction frame occupies this tile."
	var/obj/structure/frame/computer/frame = new(work_turf)
	frame.set_anchored(TRUE)
	if(desired_vars["dir"])
		frame.setDir(desired_vars["dir"])
	return TRUE

/datum/ship_plan_op/proc/execute_turf(turf/work_turf)
	var/obj/structure/girder/girder = locate() in work_turf
	if(!girder)
		return "Wall construction requires a girder."
	qdel(girder)
	work_turf.ChangeTurf(target_path, null, CHANGETURF_INHERIT_AIR)
	return istype(get_turf(work_turf), target_path) ? TRUE : "Wall construction failed."

/datum/ship_plan_op/proc/execute_object(turf/work_turf)
	if(locate(target_path) in work_turf)
		return TRUE
	var/atom/movable/created = new target_path(work_turf)
	if(!created)
		return "Failed to construct [target_path]."
	if(desired_vars["dir"])
		created.setDir(desired_vars["dir"])
	return TRUE

/**
 * Paint a turf decal onto the deck.
 *
 * A decal applies itself during `Initialize()` and then deletes itself, so its
 * mapped direction and colour have to be in place before it is created. That is
 * what the map loader's preloader is for, and using it keeps the printed
 * markings identical to the ones in the blueprint.
 */
/datum/ship_plan_op/proc/execute_decal(turf/work_turf)
	if(isclosedturf(work_turf))
		return "Cannot paint [target_path] onto a wall."
	if(length(desired_vars))
		world.preloader_setup(desired_vars, target_path)
	var/atom/painted = new target_path(work_turf)
	if(GLOB.use_preloader)
		world.preloader_load(painted)
	return TRUE

/// Initialize away from the world, sanitize, then place and activate atomically.
/datum/ship_plan_op/proc/execute_generated(turf/work_turf, obj/machinery/shipyard_fabricator/fabricator)
	if(locate(target_path) in work_turf)
		return TRUE
	var/atom/movable/created = new target_path(null)
	if(!created || QDELETED(created))
		return "Failed to initialize [target_path]."
	if(!created.shipyard_prepare(desired_vars))
		qdel(created)
		return "Failed to prepare [target_path] for placement."
	if(!consume_required_parts(fabricator?.docked_rped, created))
		if(fabricator)
			fabricator.paused_reason = "RPED lacks parts for [target_path]."
		qdel(created)
		return null
	created.forceMove(work_turf)
	if(QDELETED(created))
		return "Failed to place [target_path]."
	created.shipyard_commission(desired_vars)
	var/datum/shipyard_route/route = get_shipyard_route(target_path)
	route?.commission(created, desired_vars)
	apply_mapping_helpers(created)
	return TRUE

/datum/ship_plan_op/proc/consume_required_parts(obj/item/storage/part_replacer/replacer, atom/movable/destination)
	if(!length(required_parts))
		return TRUE
	if(!replacer)
		return FALSE
	var/list/available_parts = replacer.get_sorted_parts()
	var/list/selected_parts = list()
	for(var/requirement in required_parts)
		var/target_path = requirement
		if(ispath(requirement, /datum/stock_part))
			var/datum/stock_part/stock_part = requirement
			target_path = initial(stock_part.physical_object_base_type)
		var/remaining = required_parts[requirement]
		for(var/obj/item/part as anything in available_parts)
			if(!istype(part, target_path))
				continue
			selected_parts += part
			available_parts -= part
			remaining--
			if(!remaining)
				break
		if(remaining)
			return FALSE
	for(var/obj/item/part as anything in selected_parts)
		if(!replacer.atom_storage.attempt_remove(part, destination))
			return FALSE
		qdel(part)
	return TRUE

/datum/ship_plan_op/proc/apply_mapping_helpers(atom/movable/target)
	for(var/list/helper_spec as anything in helper_specs)
		var/helper_path = helper_spec["path"]
		if(!ispath(helper_path, /obj/effect/mapping_helpers))
			continue
		var/list/helper_vars = helper_spec["vars"]
		new helper_path(get_turf(target), target, helper_vars)

/datum/ship_plan_op/proc/find_board(obj/item/storage/part_replacer/replacer)
	if(!replacer || !board_path)
		return null
	for(var/obj/item/circuitboard/board in replacer.contents)
		if(istype(board, board_path))
			return board
	return null

/**
 * Fill in the board components the manifest already billed to the ore silo.
 *
 * Stacks are only tracked as a remaining count on the frame, so satisfying them
 * is a matter of clearing that count; loose printable items still have to exist.
 */
/datum/ship_plan_op/proc/supply_printed_components(obj/structure/frame/machine/frame)
	var/list/printed = shipyard_board_requirements(board_path)["printed"]
	for(var/component_path in printed)
		var/remaining = frame.req_components[component_path]
		if(!remaining || remaining <= 0)
			continue
		if(!ispath(component_path, /obj/item/stack))
			for(var/index in 1 to remaining)
				var/obj/item/component = new component_path(frame)
				frame.components += component
		frame.req_components[component_path] = 0

/datum/ship_plan_op/proc/execute_machine(turf/work_turf, obj/machinery/shipyard_fabricator/fabricator)
	if(locate(target_path) in work_turf)
		return TRUE
	var/obj/structure/frame/machine/frame = locate() in work_turf
	if(!frame)
		return "Machine frame is missing."
	if(!frame.circuit)
		var/obj/item/circuitboard/machine/board = find_board(fabricator.docked_rped)
		if(!board)
			fabricator.paused_reason = "RPED lacks [board_path]."
			return null
		board.build_path = target_path
		if(!frame.install_board(last_operator(fabricator), board, FALSE))
			return "Machine board could not be installed."
	supply_printed_components(frame)
	frame.install_parts_from_part_replacer(last_operator(fabricator), fabricator.docked_rped, TRUE)
	for(var/component_path in frame.req_components)
		if(frame.req_components[component_path] > 0)
			fabricator.paused_reason = "RPED lacks parts for [frame.circuit.name]."
			return null
	var/obj/item/screwdriver/driver = new(fabricator)
	var/success = frame.finalize_construction(last_operator(fabricator), driver)
	qdel(driver)
	return success ? TRUE : "Machine frame finalization failed."

/datum/ship_plan_op/proc/execute_computer(turf/work_turf, obj/machinery/shipyard_fabricator/fabricator)
	if(locate(target_path) in work_turf)
		return TRUE
	var/obj/structure/frame/computer/frame = locate() in work_turf
	if(!frame)
		return "Computer frame is missing."
	if(!frame.circuit)
		var/obj/item/circuitboard/computer/board = find_board(fabricator.docked_rped)
		if(!board)
			fabricator.paused_reason = "RPED lacks [board_path]."
			return null
		if(!frame.install_board(last_operator(fabricator), board, FALSE))
			return "Computer board could not be installed."
	frame.state = FRAME_COMPUTER_STATE_GLASSED
	var/obj/item/screwdriver/driver = new(fabricator)
	var/success = frame.finalize_construction(last_operator(fabricator), driver)
	qdel(driver)
	return success ? TRUE : "Computer frame finalization failed."

/datum/ship_plan_op/proc/last_operator(obj/machinery/shipyard_fabricator/fabricator)
	return fabricator.last_operator?.resolve()

/datum/ship_plan_op/proc/execute_commission(turf/work_turf)
	var/atom/movable/target = locate(target_path) in work_turf
	if(!target)
		return "Commissioning target [target_path] is missing."
	target.shipyard_commission(desired_vars)
	var/datum/shipyard_route/route = get_shipyard_route(target_path)
	route?.commission(target, desired_vars)
	return TRUE

/// Nullspace preparation hook. Return FALSE to prevent world placement.
/atom/movable/proc/shipyard_prepare(list/desired_vars)
	if(!islist(desired_vars))
		return TRUE
	if("dir" in desired_vars)
		setDir(desired_vars["dir"])
	if("anchored" in desired_vars)
		set_anchored(desired_vars["anchored"])
	for(var/var_name in desired_vars)
		if(var_name in list("dir", "anchored"))
			continue
		if(var_name in vars)
			var/value = desired_vars[var_name]
			if(islist(value))
				var/list/list_value = value
				vars[var_name] = list_value.Copy()
			else
				vars[var_name] = value
	return TRUE

/// Safe default commissioning surface. Rich machines override this hook.
/atom/movable/proc/shipyard_commission(list/desired_vars)
	if(!islist(desired_vars))
		return
	if("dir" in desired_vars)
		setDir(desired_vars["dir"])
	if("anchored" in desired_vars)
		set_anchored(desired_vars["anchored"])
	for(var/var_name in list("color", "initialize_directions", "pipe_color", "piping_layer"))
		if((var_name in desired_vars) && (var_name in vars))
			vars[var_name] = desired_vars[var_name]
	update_appearance()

/obj/machinery/light/shipyard_prepare(list/desired_vars)
	. = ..()
	status = LIGHT_OK
	return TRUE

/obj/machinery/light/shipyard_commission(list/desired_vars)
	. = ..()
	power_change()
	update(instant = TRUE, play_sound = FALSE)

/obj/structure/closet/shipyard_prepare(list/desired_vars)
	. = ..()
	contents_initialized = TRUE
	is_maploaded = FALSE
	opened = FALSE
	for(var/atom/movable/content as anything in contents.Copy())
		qdel(content)
	return TRUE

/obj/machinery/portable_atmospherics/canister/shipyard_prepare(list/desired_vars)
	. = ..()
	QDEL_NULL(internal_cell)
	air_contents = new(volume)
	air_contents.temperature = T20C
	valve_open = FALSE
	holding = null
	return TRUE

/obj/machinery/power/apc/shipyard_prepare(list/desired_vars)
	. = ..()
	QDEL_NULL(cell)
	if(cell_type)
		cell = new cell_type(src)
		cell.charge = clamp(start_charge, 0, 100) * cell.maxcharge / 100
	has_electronics = APC_ELECTRONICS_SECURED
	opened = APC_COVER_CLOSED
	operating = TRUE
	set_machine_stat(machine_stat & ~MAINT)
	return TRUE

/obj/machinery/power/apc/shipyard_commission(list/desired_vars)
	. = ..()
	assign_to_area()
	make_terminal()
	terminal?.connect_to_network()
	update()

/obj/machinery/airalarm/shipyard_prepare(list/desired_vars)
	. = ..()
	buildstage = AIR_ALARM_BUILD_COMPLETE
	set_panel_open(FALSE)
	return TRUE

/obj/machinery/airalarm/shipyard_commission(list/desired_vars)
	. = ..()
	my_area = get_area(src)
	if(!("name" in desired_vars))
		name = "[get_area_name(src)] Air Alarm"
	check_enviroment()

/obj/machinery/power/terminal/shipyard_commission(list/desired_vars)
	. = ..()
	master = null

/obj/machinery/power/megacell_charger/shipyard_prepare(list/desired_vars)
	. = ..()
	buildstage = MEGACELL_CHARGER_COMPLETE
	panel_open = FALSE
	req_components = list()
	return TRUE

/obj/machinery/power/megacell_charger/shipyard_commission(list/desired_vars)
	. = ..()
	make_terminal()
	terminal?.connect_to_network()

// Frame-built rather than generated, so it does not pass through route
// commissioning and mounts itself here.
/obj/machinery/cell_charger_multi/wall_mounted/shipyard_commission(list/desired_vars)
	. = ..()
	find_and_mount_on_atom()
	RefreshParts()

/obj/machinery/power/shuttle_engine/overmap/shipyard_commission(list/desired_vars)
	. = ..()
	feed_connector?.disconnect_connector()
	feed_connector?.reconnect_connector()
	scan_for_injector()
	update_engine()

/obj/machinery/overmap/fuel_injector/shipyard_commission(list/desired_vars)
	. = ..()
	input_connector?.disconnect_connector()
	input_connector?.reconnect_connector()
	feed_connector?.disconnect_connector()
	feed_connector?.reconnect_connector()
	exhaust_connector?.disconnect_connector()
	exhaust_connector?.reconnect_connector()
	update_linked_engines()

