// MODULE ID: OVERMAP
// Silo-fed, landing-zone-bound phased shuttle construction machine.

#define SHIPYARD_STATE_IDLE "idle"
#define SHIPYARD_STATE_BUILDING "building"
#define SHIPYARD_STATE_PAUSED "paused"
#define SHIPYARD_STATE_FAULT "fault"
#define SHIPYARD_STATE_COMPLETE "complete"

#define SHIPYARD_OP_DELAY (1 SECONDS)
#define SHIPYARD_DEPLOY_TIME (1 SECONDS)
#define SHIPYARD_BEAM_TIME (0.5 SECONDS)
#define SHIPYARD_DISH_PIXEL_X 32

#define SHIPYARD_DISH_IDLE "shuttle_printer-dish_idle"
#define SHIPYARD_DISH_ACTIVE "shuttle_printer-dish_active"
#define SHIPYARD_DISH_ERROR "shuttle_printer-dish_error"
#define SHIPYARD_RPED "shuttle_printer-rped"
#define SHIPYARD_RPED_BLUESPACE "shuttle_printer-rped_bluespace"

/// Landing-zone claim held while a shipyard build is active.
/obj/effect/landmark/overmap_landing_zone
	var/datum/weakref/shipyard_claim

/obj/machinery/shipyard_fabricator
	name = "shipyard fabricator"
	desc = "A silo-fed construction projector that assembles a blueprint vessel inside a linked landing zone."
	icon = 'modular_nova/modules/overmap/icons/shuttle_printer.dmi'
	icon_state = "shuttle_printer"
	base_icon_state = "shuttle_printer"
	bound_width = 64
	appearance_flags = PIXEL_SCALE | KEEP_TOGETHER
	density = TRUE
	anchored = TRUE
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION * 2
	active_power_usage = BASE_MACHINE_ACTIVE_CONSUMPTION * 5
	circuit = null
	/// Hard-required remote ore-silo connection.
	var/datum/remote_materials/materials
	/// Landing controller that supplies the claimed zone.
	var/datum/weakref/linked_controller
	/// Inserted recipe disk.
	var/obj/item/ship_blueprint_disk/blueprint_disk
	/// Docked parts inventory.
	var/obj/item/storage/part_replacer/docked_rped
	/// Optional linked shuttle blueprints accepted for future serialization.
	var/obj/item/shuttle_blueprints/intake_blueprints
	var/state = SHIPYARD_STATE_IDLE
	var/operation_index = 1
	var/current_phase = 0
	var/next_operation_at = 0
	var/list/faults = list()
	var/paused_reason
	var/datum/weakref/claimed_zone
	var/obj/docking_port/mobile/built_shuttle
	var/rotated_plan = FALSE
	var/datum/weakref/last_operator
	/// Current-phase holograms keyed by their source operation ref.
	var/list/phase_projections = list()
	/// Material multiplier: T1 matter bins cost 150% of hand construction;
	/// T4 reaches parity at 100%.
	var/material_cost_multiplier = 1.5
	/// Delay between placements, reduced by laser + servo rating.
	var/fabrication_delay = 1 SECONDS
	/// Maximum Chebyshev distance in tiles from the machine to any printed tile.
	var/max_print_range = 20
	/// Whether the cover is open and the dish is extended.
	var/printer_deployed = FALSE
	/// Persistent dish overlay shown while deployed.
	var/dish_icon_state = SHIPYARD_DISH_IDLE
	/// Direction of the directional dish overlay.
	var/dish_direction = SOUTH

/// One constructible half of the two-frame shipyard fabricator.
/// Completing two horizontally adjacent halves consumes both and creates the
/// 64px-wide machine on the western turf.
/obj/machinery/shipyard_fabricator_frame_half
	name = "shipyard fabricator assembly"
	desc = "One half of a shipyard fabricator. Build an identical machine frame immediately east or west to complete the paired assembly."
	icon = 'modular_nova/modules/overmap/icons/shuttle_printer.dmi'
	icon_state = "shuttle_printer-base"
	base_icon_state = "shuttle_printer-base"
	density = TRUE
	anchored = TRUE
	circuit = /obj/item/circuitboard/machine/shipyard_fabricator

/obj/machinery/shipyard_fabricator_frame_half/on_construction(mob/user)
	. = ..()
	addtimer(CALLBACK(src, PROC_REF(try_complete_pair)), 1)

/obj/machinery/shipyard_fabricator_frame_half/Initialize(mapload)
	. = ..()
	if(!mapload)
		addtimer(CALLBACK(src, PROC_REF(try_complete_pair)), 1)

/obj/machinery/shipyard_fabricator_frame_half/proc/try_complete_pair()
	if(QDELETED(src) || !anchored)
		return FALSE
	var/obj/machinery/shipyard_fabricator_frame_half/partner
	for(var/direction in list(EAST, WEST))
		for(var/obj/machinery/shipyard_fabricator_frame_half/candidate in get_step(src, direction))
			if(candidate.anchored)
				partner = candidate
				break
		if(partner)
			break
	if(!partner)
		return FALSE
	var/turf/west_turf = x <= partner.x ? get_turf(src) : get_turf(partner)
	if(!west_turf)
		return FALSE
	var/list/combined_parts = list()
	combined_parts += component_parts || list()
	combined_parts += partner.component_parts || list()
	var/obj/item/circuitboard/machine/first_board = circuit
	circuit = null
	partner.circuit = null
	component_parts = null
	partner.component_parts = null
	for(var/atom/movable/movable_part in combined_parts)
		movable_part.forceMove(west_turf)
	qdel(partner)
	qdel(src)
	var/obj/machinery/shipyard_fabricator/fabricator = new(west_turf)
	fabricator.component_parts = combined_parts
	for(var/atom/movable/movable_part in combined_parts)
		movable_part.forceMove(fabricator)
	fabricator.circuit = first_board
	fabricator.RefreshParts()
	fabricator.update_appearance()
	playsound(fabricator, 'sound/machines/ping.ogg', 50, TRUE)
	return TRUE

/obj/machinery/shipyard_fabricator/Initialize(mapload)
	. = ..()
	materials = new(src, mapload, allow_standalone = FALSE)
	register_context()

/obj/machinery/shipyard_fabricator/update_icon_state()
	icon_state = printer_deployed ? "shuttle_printer-base" : "shuttle_printer"
	return ..()

/obj/machinery/shipyard_fabricator/update_overlays()
	. = ..()
	if(docked_rped)
		var/rped_icon_state = istype(docked_rped, /obj/item/storage/part_replacer/bluespace) ? SHIPYARD_RPED_BLUESPACE : SHIPYARD_RPED
		. += mutable_appearance(icon, rped_icon_state, layer + 0.1)
	if(!printer_deployed)
		return
	var/mutable_appearance/dish = mutable_appearance(icon, dish_icon_state, layer + 0.2)
	dish.dir = dish_direction
	. += dish

/obj/machinery/shipyard_fabricator/proc/deploy_printer()
	if(printer_deployed)
		dish_icon_state = SHIPYARD_DISH_IDLE
		update_appearance()
		return
	printer_deployed = TRUE
	dish_icon_state = SHIPYARD_DISH_IDLE
	update_appearance()
	var/mutable_appearance/cover_opening = mutable_appearance(icon, "shuttle_printer-cover_opening", layer + 0.1)
	flick_overlay_view(cover_opening, SHIPYARD_DEPLOY_TIME)
	var/mutable_appearance/dish_opening = mutable_appearance(icon, "shuttle_printer-dish_open", layer + 0.3)
	dish_opening.dir = dish_direction
	flick_overlay_view(dish_opening, SHIPYARD_DEPLOY_TIME)

/obj/machinery/shipyard_fabricator/proc/retract_printer()
	printer_deployed = FALSE
	dish_icon_state = SHIPYARD_DISH_IDLE
	update_appearance()

/obj/machinery/shipyard_fabricator/proc/set_dish_state(new_state)
	if(!printer_deployed)
		return
	dish_icon_state = new_state
	update_appearance()

/obj/machinery/shipyard_fabricator/proc/play_placement_effect(turf/target)
	if(!printer_deployed || !target)
		return
	var/turf/dish_turf = get_step(src, EAST)
	var/target_direction = get_dir(dish_turf, target)
	if(target_direction)
		dish_direction = target_direction
	dish_icon_state = SHIPYARD_DISH_ACTIVE
	update_appearance()
	Beam(
		target,
		icon_state = "rped_upgrade",
		time = SHIPYARD_BEAM_TIME,
		override_origin_pixel_x = SHIPYARD_DISH_PIXEL_X,
	)
	addtimer(CALLBACK(src, PROC_REF(finish_placement_effect)), SHIPYARD_BEAM_TIME, TIMER_UNIQUE | TIMER_OVERRIDE)

/obj/machinery/shipyard_fabricator/proc/finish_placement_effect()
	if(state == SHIPYARD_STATE_BUILDING)
		set_dish_state(SHIPYARD_DISH_IDLE)

/obj/machinery/shipyard_fabricator/RefreshParts()
	. = ..()
	var/bin_total = 0
	var/bin_count = 0
	var/placement_total = 0
	var/placement_count = 0
	var/scanner_total = 0
	var/scanner_count = 0
	for(var/datum/stock_part/matter_bin/bin in component_parts)
		bin_total += bin.tier
		bin_count++
	for(var/datum/stock_part/micro_laser/laser in component_parts)
		placement_total += laser.tier
		placement_count++
	for(var/datum/stock_part/servo/servo in component_parts)
		placement_total += servo.tier
		placement_count++
	for(var/datum/stock_part/scanning_module/scanner in component_parts)
		scanner_total += scanner.tier
		scanner_count++
	var/bin_rating = bin_count ? clamp(bin_total / bin_count, 1, 4) : 1
	var/placement_rating = placement_count ? clamp(placement_total / placement_count, 1, 4) : 1
	var/scanner_rating = scanner_count ? clamp(scanner_total / scanner_count, 1, 4) : 1
	material_cost_multiplier = 1.5 - ((bin_rating - 1) / 6)
	fabrication_delay = (1 SECONDS) / placement_rating
	max_print_range = max(1, round(CONFIG_GET(number/max_overmap_landing_zone_dimension) * scanner_rating / 4))

/obj/machinery/shipyard_fabricator/Destroy()
	STOP_PROCESSING(SSmachines, src)
	clear_phase_projections()
	release_zone()
	QDEL_NULL(materials)
	eject_all()
	return ..()

/obj/machinery/shipyard_fabricator/on_deconstruction(disassembled)
	abort_build()
	eject_all()
	return ..()

/obj/machinery/shipyard_fabricator/proc/eject_all()
	var/atom/drop = drop_location()
	blueprint_disk?.forceMove(drop)
	docked_rped?.forceMove(drop)
	intake_blueprints?.forceMove(drop)
	blueprint_disk = null
	docked_rped = null
	intake_blueprints = null
	if(!QDELETED(src))
		update_appearance()

/obj/machinery/shipyard_fabricator/add_context(atom/source, list/context, obj/item/held_item, mob/user)
	. = ..()
	if(!istype(held_item, /obj/item/storage/part_replacer))
		return
	var/action = docked_rped ? "Replace parts" : "Dock RPED"
	context[SCREENTIP_CONTEXT_LMB] = action
	context[SCREENTIP_CONTEXT_RMB] = action
	return CONTEXTUAL_SCREENTIP_SET

/obj/machinery/shipyard_fabricator/proc/dock_rped(mob/user, obj/item/storage/part_replacer/replacer)
	if(docked_rped)
		balloon_alert(user, "rped dock occupied")
		return FALSE
	if(!user.Adjacent(src))
		balloon_alert(user, "too far away")
		return FALSE
	if(!user.transferItemToLoc(replacer, src))
		return FALSE
	docked_rped = replacer
	update_appearance()
	balloon_alert(user, "rped docked")
	return TRUE

// RPEDs intercept machinery clicks before item_interaction(). Treat the first
// RPED as shipyard inventory; later RPEDs retain normal machine-part exchange.
/obj/machinery/shipyard_fabricator/exchange_parts(mob/user, obj/item/storage/part_replacer/replacer_tool)
	if(!docked_rped)
		return dock_rped(user, replacer_tool)
	return ..()

/obj/machinery/shipyard_fabricator/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	if(istype(tool, /obj/item/ship_blueprint_disk))
		if(blueprint_disk)
			balloon_alert(user, "disk slot occupied")
			return ITEM_INTERACT_BLOCKING
		var/obj/item/ship_blueprint_disk/disk = tool
		if(!disk.load_ship_plan())
			balloon_alert(user, "unreadable blueprint")
			return ITEM_INTERACT_BLOCKING
		if(!user.transferItemToLoc(tool, src))
			return ITEM_INTERACT_BLOCKING
		blueprint_disk = disk
		balloon_alert(user, "blueprint loaded")
		return ITEM_INTERACT_SUCCESS
	if(istype(tool, /obj/item/storage/part_replacer))
		return dock_rped(user, tool) ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING
	if(istype(tool, /obj/item/shuttle_blueprints))
		if(intake_blueprints)
			balloon_alert(user, "intake occupied")
			return ITEM_INTERACT_BLOCKING
		if(!user.transferItemToLoc(tool, src))
			return ITEM_INTERACT_BLOCKING
		intake_blueprints = tool
		balloon_alert(user, "blueprints loaded")
		return ITEM_INTERACT_SUCCESS
	return ..()

/obj/machinery/shipyard_fabricator/multitool_act(mob/living/user, obj/item/multitool/tool)
	if(istype(tool.buffer, /obj/machinery/computer/landing_controller))
		var/obj/machinery/computer/landing_controller/controller = tool.buffer
		if(controller.z != z)
			balloon_alert(user, "controller off-Z")
			return ITEM_INTERACT_BLOCKING
		linked_controller = WEAKREF(controller)
		balloon_alert(user, "landing zone linked")
		return ITEM_INTERACT_SUCCESS
	return ..()

/obj/machinery/shipyard_fabricator/examine(mob/user)
	. = ..()
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	. += span_notice("Landing zone: [controller ? controller.zone_label : "unlinked"].")
	. += span_notice("Silo: [materials?.silo ? "linked" : "unlinked"]; RPED: [docked_rped ? "docked" : "missing"]; disk: [blueprint_disk ? blueprint_disk.ship_plan?.name : "missing"].")
	if(paused_reason)
		. += span_warning(paused_reason)

/obj/machinery/shipyard_fabricator/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(ui)
		return
	ui = new(user, src, "ShipyardFabricator", name)
	ui.open()

/obj/machinery/shipyard_fabricator/ui_data(mob/user)
	var/list/data = list()
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	var/obj/effect/landmark/overmap_landing_zone/zone = controller?.active_zone
	data["state"] = state
	data["pausedReason"] = paused_reason
	data["planName"] = plan?.name
	data["planWidth"] = plan?.width || 0
	data["planHeight"] = plan?.height || 0
	data["operation"] = operation_index
	data["operationTotal"] = length(plan?.manifest)
	data["phase"] = current_phase
	data["phaseCounts"] = plan?.phase_counts() || list()
	var/show_debug_details = check_rights_for(user.client, R_ADMIN | R_DEBUG)
	data["skipped"] = plan?.skipped_report(show_debug_details, include_ignored = show_debug_details) || list()
	data["skippedCounts"] = plan?.skipped_counts() || list()
	data["faults"] = faults
	data["siloLinked"] = !!materials?.silo
	data["siloOnHold"] = materials?.on_hold()
	data["rpedDocked"] = !!docked_rped
	data["diskLoaded"] = !!blueprint_disk
	data["blueprintsLoaded"] = !!intake_blueprints
	data["materialMultiplier"] = material_cost_multiplier
	data["placementDelay"] = fabrication_delay
	data["maxPrintRange"] = max_print_range
	data["zoneLinked"] = !!controller
	data["zoneActive"] = !!zone
	data["zoneName"] = zone?.zone_name
	data["zoneWidth"] = zone?.zone_width || 0
	data["zoneHeight"] = zone?.zone_height || 0
	data["zoneOccupied"] = !!zone?.get_occupant()
	data["materials"] = material_summary(plan)
	data["parts"] = part_summary(plan)
	return data

/obj/machinery/shipyard_fabricator/proc/material_summary(datum/ship_plan/plan)
	var/list/result = list()
	if(!plan)
		return result
	for(var/material_path in plan.material_cost)
		var/datum/material/material = SSmaterials.get_material(material_path)
		var/available = materials?.mat_container?.get_material_amount(material_path) || 0
		result += list(list(
			"name" = material?.name || "[material_path]",
			"required" = round(plan.material_cost[material_path] * material_cost_multiplier / SHEET_MATERIAL_AMOUNT, 0.1),
			"available" = round(available / SHEET_MATERIAL_AMOUNT, 0.1),
		))
	return result

/obj/machinery/shipyard_fabricator/proc/part_summary(datum/ship_plan/plan)
	var/list/result = list()
	if(!plan)
		return result
	for(var/part_path in plan.required_parts)
		var/count = 0
		for(var/obj/item/part in docked_rped?.contents)
			if(istype(part, part_path))
				count++
		var/obj/item/item_path = part_path
		result += list(list(
			"name" = initial(item_path.name),
			"required" = plan.required_parts[part_path],
			"available" = count,
		))
	return result

/obj/machinery/shipyard_fabricator/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/ui_state)
	. = ..()
	if(.)
		return
	var/mob/living/user = usr
	switch(action)
		if("start")
			. = start_build(user)
		if("pause")
			pause_build("Paused by operator.")
			. = TRUE
		if("resume")
			. = resume_build(user)
		if("abort")
			abort_build()
			. = TRUE
		if("eject_disk")
			if(state == SHIPYARD_STATE_BUILDING)
				return FALSE
			blueprint_disk?.forceMove(drop_location())
			blueprint_disk = null
			. = TRUE
		if("eject_rped")
			if(state == SHIPYARD_STATE_BUILDING)
				return FALSE
			docked_rped?.forceMove(drop_location())
			docked_rped = null
			update_appearance()
			. = TRUE
		if("eject_blueprints")
			intake_blueprints?.forceMove(drop_location())
			intake_blueprints = null
			. = TRUE

/obj/machinery/shipyard_fabricator/proc/start_build(mob/living/user)
	if(state == SHIPYARD_STATE_BUILDING)
		return FALSE
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	if(!plan || !length(plan.manifest))
		paused_reason = "Insert a valid ship blueprint disk."
		return FALSE
	if(!docked_rped)
		paused_reason = "Dock an RPED containing required boards and stock parts."
		return FALSE
	if(!materials?.silo || !materials.can_use_resource())
		paused_reason = "A live ore silo connection is required."
		return FALSE
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	var/obj/effect/landmark/overmap_landing_zone/zone = controller?.active_zone
	if(!zone)
		paused_reason = "Link a controller with an active landing zone."
		return FALSE
	if(zone.get_occupant())
		paused_reason = "The linked landing zone is occupied."
		return FALSE
	if(zone.shipyard_claim?.resolve() != src && zone.shipyard_claim?.resolve())
		paused_reason = "The linked landing zone is claimed by another fabricator."
		return FALSE
	if(!zone.can_fit_shuttle(plan.width, plan.height))
		paused_reason = "The blueprint does not fit inside the linked landing zone."
		return FALSE
	rotated_plan = plan.width > zone.zone_width || plan.height > zone.zone_height
	var/printed_width = rotated_plan ? plan.height : plan.width
	var/printed_height = rotated_plan ? plan.width : plan.height
	var/turf/far_corner = locate(zone.x + printed_width - 1, zone.y + printed_height - 1, zone.z)
	if(!far_corner || get_dist(src, far_corner) > max_print_range)
		paused_reason = "Scanner resolution limits this fabricator to [max_print_range] tiles; the far hull corner is out of range."
		return FALSE
	zone.shipyard_claim = WEAKREF(src)
	claimed_zone = WEAKREF(zone)
	if(state == SHIPYARD_STATE_IDLE || state == SHIPYARD_STATE_COMPLETE)
		operation_index = 1
		current_phase = 0
		faults = list()
		built_shuttle = null
	last_operator = WEAKREF(user)
	paused_reason = null
	var/was_deployed = printer_deployed
	deploy_printer()
	state = SHIPYARD_STATE_BUILDING
	if(current_phase && !length(phase_projections))
		project_phase(current_phase)
	next_operation_at = world.time + (was_deployed ? 0 : SHIPYARD_DEPLOY_TIME)
	update_use_power(ACTIVE_POWER_USE)
	START_PROCESSING(SSmachines, src)
	return TRUE

/obj/machinery/shipyard_fabricator/proc/resume_build(mob/living/user)
	if(!(state in list(SHIPYARD_STATE_PAUSED, SHIPYARD_STATE_FAULT)))
		return FALSE
	return start_build(user)

/obj/machinery/shipyard_fabricator/proc/pause_build(reason)
	paused_reason = reason
	state = SHIPYARD_STATE_PAUSED
	set_dish_state(SHIPYARD_DISH_IDLE)
	update_use_power(IDLE_POWER_USE)
	STOP_PROCESSING(SSmachines, src)

/obj/machinery/shipyard_fabricator/proc/fault_build(datum/ship_plan_op/operation, reason)
	var/obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve()
	var/turf/target = get_operation_turf(operation, zone)
	paused_reason = reason
	faults += list(list(
		"x" = target?.x || 0,
		"y" = target?.y || 0,
		"phase" = operation?.phase || current_phase,
		"reason" = reason,
	))
	state = SHIPYARD_STATE_FAULT
	set_dish_state(SHIPYARD_DISH_ERROR)
	update_use_power(IDLE_POWER_USE)
	STOP_PROCESSING(SSmachines, src)

/obj/machinery/shipyard_fabricator/proc/abort_build()
	STOP_PROCESSING(SSmachines, src)
	clear_phase_projections()
	release_zone()
	state = SHIPYARD_STATE_IDLE
	operation_index = 1
	current_phase = 0
	paused_reason = null
	retract_printer()
	update_use_power(IDLE_POWER_USE)

/obj/machinery/shipyard_fabricator/proc/release_zone()
	var/obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve()
	if(zone?.shipyard_claim?.resolve() == src)
		zone.shipyard_claim = null
	claimed_zone = null

/obj/machinery/shipyard_fabricator/proc/clear_phase_projections()
	QDEL_LIST_ASSOC_VAL(phase_projections)
	phase_projections = list()

/obj/machinery/shipyard_fabricator/proc/clear_operation_projection(datum/ship_plan_op/operation)
	var/ref = REF(operation)
	var/obj/effect/overlay/shipyard_projection/projection = phase_projections[ref]
	if(projection)
		qdel(projection)
	phase_projections -= ref

/obj/machinery/shipyard_fabricator/proc/project_phase(phase)
	clear_phase_projections()
	if(!phase || phase == SHIPYARD_PHASE_COMMISSIONING)
		return
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	var/obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve()
	if(!plan || !zone)
		return
	for(var/datum/ship_plan_op/operation as anything in plan.manifest)
		if(operation.phase != phase)
			continue
		var/turf/target = get_operation_turf(operation, zone)
		if(!target || operation.satisfied(target))
			continue
		var/obj/effect/overlay/shipyard_projection/projection = new(target, operation)
		if(!QDELETED(projection))
			phase_projections[REF(operation)] = projection

/obj/machinery/shipyard_fabricator/process(seconds_per_tick)
	if(state != SHIPYARD_STATE_BUILDING)
		return PROCESS_KILL
	if(machine_stat & (NOPOWER | BROKEN))
		pause_build("Fabricator power lost.")
		return PROCESS_KILL
	if(world.time < next_operation_at)
		return
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	if(!plan || operation_index > length(plan.manifest))
		finish_build()
		return PROCESS_KILL
	var/datum/ship_plan_op/operation = plan.manifest[operation_index]
	if(operation.phase != current_phase)
		if(current_phase && !complete_phase(current_phase))
			return PROCESS_KILL
		current_phase = operation.phase
		project_phase(current_phase)
	var/result = operation.execute(src)
	if(result != TRUE)
		if(istext(result))
			fault_build(operation, result)
		else
			pause_build("Waiting for materials or parts.")
		return PROCESS_KILL
	clear_operation_projection(operation)
	operation_index++
	next_operation_at = world.time + fabrication_delay
	if(operation_index > length(plan.manifest))
		if(!complete_phase(current_phase))
			return PROCESS_KILL
		finish_build()
		return PROCESS_KILL

/obj/machinery/shipyard_fabricator/proc/get_operation_turf(datum/ship_plan_op/operation, obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve())
	if(!operation || !zone)
		return null
	if(rotated_plan)
		var/datum/ship_plan/plan = blueprint_disk?.ship_plan
		return locate(zone.x + operation.rel_y, zone.y + plan.width - 1 - operation.rel_x, zone.z)
	return locate(zone.x + operation.rel_x, zone.y + operation.rel_y, zone.z)

/obj/machinery/shipyard_fabricator/proc/complete_phase(phase)
	if(phase != SHIPYARD_PHASE_PLATING || built_shuttle)
		return TRUE
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	var/obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve()
	var/list/hull_turfs = list()
	for(var/datum/ship_plan_op/operation as anything in plan.manifest)
		if(operation.op_type != SHIPYARD_OP_PLATING)
			continue
		var/turf/hull = get_operation_turf(operation, zone)
		if(hull)
			hull_turfs |= hull
	if(!length(hull_turfs))
		fault_build(null, "No hull plating exists for shuttle registration.")
		return FALSE
	var/turf/origin = hull_turfs[1]
	var/mob/living/operator = last_operator?.resolve()
	var/shuttle_id = "shipyard_[REF(src)]_[world.time]"
	built_shuttle = create_shuttle(
		operator,
		origin,
		hull_turfs,
		list(),
		zone.exit_direction || NORTH,
		zone.exit_direction || NORTH,
		area_type = blueprint_disk.registration_area_type,
		docking_port_type = blueprint_disk.registration_port_type,
		name = plan.name,
		id = shuttle_id,
		custom = blueprint_disk.registration_is_custom,
	)
	if(!built_shuttle)
		fault_build(null, "Shuttle registration failed after plating.")
		return FALSE
	if(istype(built_shuttle, /obj/docking_port/mobile/custom))
		var/obj/item/shuttle_blueprints/master = new(drop_location())
		master.link_to_shuttle(built_shuttle, TRUE)
	return TRUE

/obj/machinery/shipyard_fabricator/proc/finish_build()
	clear_phase_projections()
	state = SHIPYARD_STATE_COMPLETE
	paused_reason = "Construction complete. Frames listed as incomplete require manual RPED finishing."
	retract_printer()
	update_use_power(IDLE_POWER_USE)
	release_zone()
	playsound(src, 'sound/machines/ping.ogg', 50, TRUE)

#undef SHIPYARD_OP_DELAY
#undef SHIPYARD_DEPLOY_TIME
#undef SHIPYARD_BEAM_TIME
#undef SHIPYARD_DISH_PIXEL_X

#undef SHIPYARD_DISH_IDLE
#undef SHIPYARD_DISH_ACTIVE
#undef SHIPYARD_DISH_ERROR

