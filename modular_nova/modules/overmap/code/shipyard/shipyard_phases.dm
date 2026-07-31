// MODULE ID: OVERMAP
// Execution and verification for declarative ship-plan operations.

/**
 * Whether a tile belongs to a hull, framed or finished.
 *
 * Frame membership is a trait until the hull is registered as a ship, at which
 * point the construction element hands the tile over to the shuttle and drops
 * the trait, so the trait alone stops answering this question partway through a
 * build - the plating phase is what registers, and every phase after it runs on
 * tiles that are no longer loose frame. Registration stacks a skipover under the
 * hull layer to mark what it took, and that survives everything laid on top.
 */
/proc/shipyard_hull_turf(turf/work_turf)
	if(!work_turf)
		return FALSE
	if(HAS_TRAIT(work_turf, TRAIT_SHUTTLE_CONSTRUCTION_TURF))
		return TRUE
	return !!work_turf.depth_to_find_baseturf(/turf/baseturf_skipover/shuttle)

/datum/ship_plan_op/proc/satisfied(turf/work_turf)
	if(!work_turf)
		return FALSE
	switch(op_type)
		if(SHIPYARD_OP_RODS)
			// Hull membership means the rod stage is behind us, including tiles
			// already plated over, which drop the rod source but stay in the hull.
			return shipyard_hull_turf(work_turf)
		if(SHIPYARD_OP_PLATING)
			// Rods do not change the turf's own type, so a pad that was already
			// plating still owes a hull layer. Plating is only done once that
			// layer has covered the exposed rods.
			return shipyard_hull_turf(work_turf) \
				&& !HAS_TRAIT_FROM(work_turf, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE)
		if(SHIPYARD_OP_GIRDER)
			return !!(locate(/obj/structure/girder) in work_turf)
		// Matched on our own stamp rather than on any frame at all, so a tile
		// stacking two machines still owes a second frame after the first goes
		// down. A finished machine has consumed its frame and owes nothing.
		if(SHIPYARD_OP_MACHINE_FRAME)
			if(locate(target_path) in work_turf)
				return TRUE
			return !!stamped_frame(work_turf, /obj/structure/frame/machine)
		if(SHIPYARD_OP_COMPUTER_FRAME)
			if(locate(target_path) in work_turf)
				return TRUE
			return !!stamped_frame(work_turf, /obj/structure/frame/computer)
		if(SHIPYARD_OP_TURF)
			return istype(work_turf, target_path)
		if(SHIPYARD_OP_OBJECT, SHIPYARD_OP_GENERATED, SHIPYARD_OP_MACHINE, SHIPYARD_OP_COMPUTER, SHIPYARD_OP_COMMISSION)
			return !!(locate(target_path) in work_turf)
		if(SHIPYARD_OP_DECAL)
			// Paint leaves no object on the turf to detect, so it is always
			// pending until the build index moves past it.
			return FALSE
	return FALSE

/**
 * Whether running this operation would only confirm what is already there.
 *
 * Resumed builds walk the whole manifest again, and the fabricator uses this to
 * tell a re-check apart from a real placement so catching up is not paced by
 * placement time.
 */
/datum/ship_plan_op/proc/needs_no_work(obj/machinery/shipyard_fabricator/fabricator)
	if(op_type == SHIPYARD_OP_COMMISSION)
		return FALSE
	return satisfied(fabricator.get_operation_turf(src))

/**
 * Something standing where hull work has to happen, or null when the tile is clear.
 *
 * Rods and plating go down before the plan places anything of its own, so
 * anything structural on the tile at that point was left by the crew and would
 * be silently built over.
 */
/datum/ship_plan_op/proc/hull_obstruction(turf/work_turf)
	if(op_type != SHIPYARD_OP_RODS && op_type != SHIPYARD_OP_PLATING)
		return null
	for(var/obj/blocker in work_turf)
		// Wide atoms such as the fabricator itself list themselves in the
		// contents of every turf they overlap, so only tenants count.
		if(blocker.loc != work_turf)
			continue
		if(isstructure(blocker) || ismachinery(blocker))
			return blocker
	return null

/// Execute one operation. TRUE means complete, null means a replenishable
/// resource wait, and text means a world-state fault that needs intervention.
/datum/ship_plan_op/proc/execute(obj/machinery/shipyard_fabricator/fabricator)
	var/obj/effect/landmark/overmap_landing_zone/zone = fabricator.claimed_zone?.resolve()
	var/turf/work_turf = fabricator.get_operation_turf(src, zone)
	if(!zone || !work_turf || !zone.contains_turf(work_turf))
		return "Operation target is outside the claimed landing zone."
	if(satisfied(work_turf) && op_type != SHIPYARD_OP_COMMISSION)
		return TRUE
	var/obj/blocker = hull_obstruction(work_turf)
	if(blocker)
		return "[blocker.name] blocks hull work at ([work_turf.x], [work_turf.y])."
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
			user_data = fabricator.consumer_id_data(),
		)
	return TRUE

/datum/ship_plan_op/proc/execute_rods(turf/open/work_turf)
	if(!istype(work_turf))
		return "Hull rods require an open turf."
	if(!work_turf.can_anchor_shuttle_frame_rods())
		return "Hull rods cannot anchor into the [work_turf.name]."
	if(shipyard_hull_turf(work_turf))
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

/// The machine a printed frame is bound to become.
///
/// One bare frame looks exactly like another, and a blueprint may stack two
/// machines on a single tile - a power connector and its portable SMES, for one -
/// so without this the second frame operation mistakes the first one's frame for
/// its own, lays nothing, and leaves its machine with no frame to be built in.
/obj/structure/frame/var/shipyard_target

/// The frame on this tile that this operation laid.
/datum/ship_plan_op/proc/stamped_frame(turf/work_turf, frame_type)
	for(var/obj/structure/frame/candidate in work_turf)
		if(istype(candidate, frame_type) && candidate.shipyard_target == target_path)
			return candidate
	return null

/**
 * The frame on this tile this operation should be working in.
 *
 * Its own by preference. Failing that it adopts an unstamped one of the right
 * type, which is either the crew lending a hand or a build that started before
 * frames carried a stamp; either way the tile wants a frame here, so adopting one
 * beats stacking a second on top of it.
 */
/datum/ship_plan_op/proc/claim_frame(turf/work_turf, frame_type)
	var/obj/structure/frame/claimed = stamped_frame(work_turf, frame_type)
	if(claimed)
		return claimed
	for(var/obj/structure/frame/candidate in work_turf)
		if(istype(candidate, frame_type) && isnull(candidate.shipyard_target))
			return candidate
	return null

/datum/ship_plan_op/proc/execute_machine_frame(turf/work_turf)
	if(!isfloorturf(work_turf))
		return "Machine frame placement requires shuttle plating."
	var/obj/structure/frame/machine/frame = claim_frame(work_turf, /obj/structure/frame/machine)
	if(!frame)
		frame = new /obj/structure/frame/machine/secured(work_turf)
	frame.set_anchored(TRUE)
	frame.shipyard_target = target_path
	return TRUE

/datum/ship_plan_op/proc/execute_computer_frame(turf/work_turf)
	if(!isfloorturf(work_turf))
		return "Computer frame placement requires shuttle plating."
	var/obj/structure/frame/computer/frame = claim_frame(work_turf, /obj/structure/frame/computer)
	if(!frame)
		frame = new /obj/structure/frame/computer(work_turf)
	frame.set_anchored(TRUE)
	frame.shipyard_target = target_path
	if(desired_vars["dir"])
		frame.setDir(desired_vars["dir"])
	return TRUE

/// A blueprint's turf is either a wall raised on a girder or a deck tiled over
/// the hull, which share nothing but the operation kind.
/datum/ship_plan_op/proc/execute_turf(turf/work_turf)
	if(ispath(target_path, /turf/closed))
		return execute_wall(work_turf)
	return execute_deck(work_turf)

/datum/ship_plan_op/proc/execute_wall(turf/work_turf)
	var/obj/structure/girder/girder = locate() in work_turf
	if(!girder)
		return "Wall construction requires a girder."
	qdel(girder)
	work_turf.ChangeTurf(target_path, null, CHANGETURF_INHERIT_AIR)
	return istype(get_turf(work_turf), target_path) ? TRUE : "Wall construction failed."

/**
 * Tile the blueprint's deck over the hull plating.
 *
 * Stacked on top rather than changed into, the way a crew-laid tile is: the hull
 * layer stays in the baseturf stack, so prying a deck back up exposes plating
 * rather than the landing pad, and the marker registration stacked under the hull
 * stays where it is - which is what keeps a finished deck legible as hull to a
 * build that is resumed over it.
 */
/datum/ship_plan_op/proc/execute_deck(turf/work_turf)
	if(!isfloorturf(work_turf))
		return "Deck tiling requires shuttle plating."
	if(!shipyard_hull_turf(work_turf))
		return "Deck tiling requires a shuttle hull tile."
	if(HAS_TRAIT_FROM(work_turf, TRAIT_SHUTTLE_CONSTRUCTION_TURF, SHUTTLE_ROD_TRAIT_SOURCE))
		return "Hull plating is missing beneath this deck tile."
	var/turf/decked = work_turf.place_on_top(target_path, flags = CHANGETURF_INHERIT_AIR)
	if(!istype(decked, target_path))
		return "Deck tiling failed."
	if(desired_vars["dir"])
		decked.setDir(desired_vars["dir"])
	return TRUE

/**
 * Place a mapped object straight onto the deck.
 *
 * The blueprint's vars go in through the map loader's preloader so that they are
 * set before `Initialize()` runs, which is the only point some of them are read.
 * Pipes derive their connection directions from `dir` there and never revisit the
 * question, and a unary device draws its pipe cap from that result, so a dir
 * applied afterwards leaves a vent both hunting for its pipe and drawing its cap
 * on the wrong side.
 */
/datum/ship_plan_op/proc/execute_object(turf/work_turf)
	if(locate(target_path) in work_turf)
		return TRUE
	if(length(desired_vars))
		world.preloader_setup(desired_vars, target_path)
	var/atom/movable/created = new target_path(work_turf)
	if(!created)
		GLOB.use_preloader = FALSE
		return "Failed to construct [target_path]."
	if(GLOB.use_preloader)
		world.preloader_load(created)
	created.shipyard_placed()
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
		var/target_path = shipyard_part_item_type(requirement)
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
	var/obj/structure/frame/machine/frame = claim_frame(work_turf, /obj/structure/frame/machine)
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
	var/obj/structure/frame/computer/frame = claim_frame(work_turf, /obj/structure/frame/computer)
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
	// After setDir(), which derives a wall fixture's offset from the wall it faces:
	// a blueprint that states the offset outright is hanging something its family
	// has no directional subtype for, and means the number it gave.
	for(var/var_name in list("color", "initialize_directions", "pipe_color", "piping_layer", "pixel_x", "pixel_y"))
		if((var_name in desired_vars) && (var_name in vars))
			vars[var_name] = desired_vars[var_name]
	update_appearance()

/// Activation hook for the direct-placement path, which has no nullspace stage:
/// the blueprint's vars arrive through the preloader before `Initialize()`, so all
/// that is left is whatever the object needs to learn from its surroundings.
/atom/movable/proc/shipyard_placed()
	return

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

/// Initialize() never goes looking for neighbouring pipes. That is SSair's job
/// during mapload and on_construction()'s when a player lays a pipe by hand, and
/// neither of them runs for a printed one, so an unconnected pipe would sit there
/// as a stub forever. This is on_construction()'s handshake without the colour and
/// layer handling, which would trample what the blueprint asked for.
/obj/machinery/atmospherics/shipyard_placed()
	. = ..()
	atmos_init()
	for(var/obj/machinery/atmospherics/neighbour in pipeline_expansion())
		neighbour.atmos_init()
		neighbour.add_member(src)
	SSair.add_to_rebuild_queue(src)

/**
 * A cable's Initialize() only sets the bitflags driving its icon and its links to
 * its neighbours. The powernet is somebody else's job: SSmachines builds them for
 * mapped cable once at roundstart, and the coil builds them for cable laid by
 * hand. Neither runs for a printed one, so the grid would come out fully linked
 * and completely dead, with every machine on it finding a cable to sit on and no
 * network to draw from. This is the coil's handshake.
 */
/obj/structure/cable/shipyard_placed()
	. = ..()
	var/datum/powernet/grid = new()
	grid.add_cable(src)
	for(var/direction in GLOB.cardinals)
		mergeConnectedNetworks(direction)
	mergeConnectedNetworksOnTurf()

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

/**
 * Re-establish the link this machine needs on top of a powernet.
 *
 * A terminal to draw through, a master to draw for, a connector to stand on: the
 * vars naming those are declared per family rather than on a shared ancestor, and
 * each family binds them either during mapload or by hand, neither of which
 * happens to a printed machine. Run late in the build, once everything the link
 * could point at exists. Only the families that have such a link implement it.
 */
/obj/machinery/proc/shipyard_pair()
	return

// make_terminal() adopts a terminal already standing on the tile rather than
// building a second one, and a printed terminal gives up its master on
// commissioning so that whichever machine needs it can claim it - so this repairs
// a terminal printed after the machine that draws through it just as well as a
// missing one.
/obj/machinery/power/apc/shipyard_pair()
	if(isnull(terminal) || terminal.master != src)
		make_terminal()

/obj/machinery/power/megacell_charger/shipyard_pair()
	if(isnull(terminal) || terminal.master != src)
		make_terminal()

/// A wall SMES draws through a terminal on an adjacent tile that faces it, and
/// breaks itself on finding none, which is the state a printed one starts in. This
/// is the search its mapload path runs.
/obj/machinery/power/smes/shipyard_pair()
	if(terminal)
		return
	for(var/direction in GLOB.cardinals)
		for(var/obj/machinery/power/terminal/candidate in get_step(src, direction))
			if(candidate.dir != REVERSE_DIR(direction) || candidate.master)
				continue
			terminal = candidate
			terminal.master = src
			set_machine_stat(machine_stat & ~BROKEN)
			update_appearance(UPDATE_OVERLAYS)
			return

/// A portable SMES is only wired while it stands on a connector, and printing one
/// leaves it loose: its construction hook drops the anchor deliberately, and the
/// pairing mapload does runs from post_machine_initialize(), which a machine built
/// out of a frame never reaches.
/obj/machinery/smesbank/shipyard_pair()
	if(connected_port)
		return
	var/obj/machinery/power/smes/connector/port = locate() in loc
	if(!connect_port(port))
		return
	connected_port.input_attempt = TRUE
	connected_port.output_attempt = TRUE

