// MODULE ID: OVERMAP
// Declarative manifests for constructing shuttle templates in player landing zones.

/// A single declarative construction operation.
/datum/ship_plan_op
	var/phase
	var/rel_x
	var/rel_y
	var/op_type
	var/target_path
	var/board_path
	var/list/material_cost = list()
	var/list/desired_vars = list()
	/// Mapping-helper types and var edits to apply after generated placement.
	var/list/helper_specs = list()

/datum/ship_plan_op/New(
	phase,
	rel_x,
	rel_y,
	op_type,
	target_path,
	list/material_cost,
	list/desired_vars,
	board_path,
	list/helper_specs,
)
	src.phase = phase
	src.rel_x = rel_x
	src.rel_y = rel_y
	src.op_type = op_type
	src.target_path = target_path
	src.board_path = board_path
	if(material_cost)
		src.material_cost = material_cost.Copy()
	if(desired_vars)
		src.desired_vars = desired_vars.Copy()
	if(helper_specs)
		src.helper_specs = helper_specs.Copy()

/// Returns a JSON-friendly summary for the fabricator UI.
/datum/ship_plan_op/proc/as_list()
	return list(
		"phase" = phase,
		"x" = rel_x,
		"y" = rel_y,
		"operation" = op_type,
		"target" = target_path ? "[target_path]" : null,
	)

/// A load-source-agnostic ship recipe.
/datum/ship_plan
	var/name = "Unnamed vessel"
	var/width = 0
	var/height = 0
	var/shuttle_dir = NORTH
	var/list/manifest = list()
	var/list/skipped_contents = list()
	var/list/material_cost = list()
	var/list/required_parts = list()

/datum/ship_plan/Destroy()
	QDEL_LIST(manifest)
	return ..()

/datum/ship_plan/proc/get_manifest()
	return manifest

/datum/ship_plan/proc/get_material_cost()
	return material_cost.Copy()

/datum/ship_plan/proc/get_required_parts()
	return required_parts.Copy()

/datum/ship_plan/proc/add_operation(datum/ship_plan_op/operation)
	manifest += operation
	for(var/material_path in operation.material_cost)
		material_cost[material_path] = (material_cost[material_path] || 0) + operation.material_cost[material_path]
	if(operation.board_path)
		required_parts[operation.board_path] = (required_parts[operation.board_path] || 0) + 1

/datum/ship_plan/proc/phase_counts()
	var/list/counts = list()
	for(var/datum/ship_plan_op/operation as anything in manifest)
		counts["[operation.phase]"] = (counts["[operation.phase]"] || 0) + 1
	return counts

/// A plan derived from a parsed shuttle DMM without loading it into the world.
/datum/ship_plan/template
	var/datum/map_template/shuttle/source_template

/datum/ship_plan/template/New(datum/map_template/shuttle/template)
	. = ..()
	if(!istype(template))
		return
	source_template = template
	name = template.name
	width = template.width
	height = template.height
	build_manifest()

/datum/ship_plan/template/Destroy()
	QDEL_NULL(source_template)
	return ..()

/datum/ship_plan/template/proc/build_manifest()
	if(!source_template?.mappath)
		return FALSE
	if(!source_template.cached_map)
		source_template.cached_map = new /datum/parsed_map(file(source_template.mappath))
	var/datum/parsed_map/parsed = source_template.cached_map
	if(!parsed?.bounds)
		return FALSE
	var/list/model_cache = parsed.build_cache()
	if(!length(model_cache))
		return FALSE

	width = parsed.bounds[MAP_MAXX] - parsed.bounds[MAP_MINX] + 1
	height = parsed.bounds[MAP_MAXY] - parsed.bounds[MAP_MINY] + 1
	var/min_x = parsed.bounds[MAP_MINX]
	var/min_y = parsed.bounds[MAP_MINY]
	var/min_z = parsed.bounds[MAP_MINZ]

	for(var/datum/grid_set/grid_set as anything in parsed.gridSets)
		if(grid_set.zcrd != min_z)
			continue
		var/map_y = grid_set.ycrd
		for(var/line in grid_set.gridLines)
			var/map_x = grid_set.xcrd
			for(var/position in 1 to length(line) step parsed.key_len)
				var/model_key = copytext(line, position, position + parsed.key_len)
				var/list/model = model_cache[model_key]
				if(model)
					classify_model(model, map_x - min_x, map_y - min_y)
				map_x++
			map_y--

	sortTim(manifest, GLOBAL_PROC_REF(cmp_ship_plan_ops))
	return length(manifest) > 0

/// Resolve a wall's declared construction materials instead of assuming iron.
/datum/ship_plan/template/proc/wall_material_cost(turf_path)
	var/turf/closed/wall/wall_type = turf_path
	var/list/declared_materials = initial(wall_type.custom_materials)
	if(length(declared_materials))
		return declared_materials.Copy()

	var/obj/item/stack/sheet/sheet_type = initial(wall_type.sheet_type)
	var/list/per_sheet = initial(sheet_type.mats_per_unit)
	if(!length(per_sheet))
		var/material_type = initial(sheet_type.material_type)
		if(material_type)
			per_sheet = list()
			per_sheet[material_type] = SHEET_MATERIAL_AMOUNT
	if(!length(per_sheet))
		return list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

	var/list/result = list()
	var/sheet_amount = initial(wall_type.sheet_amount)
	for(var/material_path in per_sheet)
		result[material_path] = per_sheet[material_path] * sheet_amount
	return result

/// Merge a material dictionary into another without retaining shared lists.
/datum/ship_plan/template/proc/merge_material_cost(list/target, list/additional)
	for(var/material in additional)
		target[material] = (target[material] || 0) + additional[material]
	return target

/// Return the canonical autolathe cost for an exact output path.
/datum/ship_plan/template/proc/autolathe_material_cost(build_path)
	var/list/datum/design/candidates = SSresearch.item_to_design[build_path]
	for(var/datum/design/design as anything in candidates)
		if(!(design.build_type & AUTOLATHE))
			continue
		var/list/result = list()
		for(var/material in design.materials)
			var/material_key = material
			if(istype(material, /datum/material))
				var/datum/material/material_datum = material
				material_key = material_datum.type
			result[material_key] = design.materials[material]
		return result
	return list()

/// Material declaration on an atom path, normalized into a fresh list.
/datum/ship_plan/template/proc/declared_material_cost(atom_path)
	var/atom/atom_type = atom_path
	var/list/declared = initial(atom_type.custom_materials)
	return length(declared) ? declared.Copy() : list()

/// Costs for direct-generated fixtures and wall electronics.
/datum/ship_plan/template/proc/generated_material_cost(target_path, list/desired)
	var/list/result = autolathe_material_cost(target_path)
	if(!length(result))
		result = declared_material_cost(target_path)
	if(ispath(target_path, /obj/machinery/light))
		if(!length(result))
			result[/datum/material/iron] = SHEET_MATERIAL_AMOUNT * 2
		var/light_item = ispath(target_path, /obj/machinery/light/small) ? /obj/item/light/bulb : /obj/item/light/tube
		merge_material_cost(result, autolathe_material_cost(light_item))
	else if(ispath(target_path, /obj/structure/closet))
		if(!length(result))
			result[/datum/material/iron] = SHEET_MATERIAL_AMOUNT * 2
	else if(ispath(target_path, /obj/machinery/portable_atmospherics/canister))
		if(!length(result))
			result[/datum/material/iron] = SHEET_MATERIAL_AMOUNT * 10
	else if(ispath(target_path, /obj/machinery/power/apc))
		result[/datum/material/iron] = (result[/datum/material/iron] || 0) + SHEET_MATERIAL_AMOUNT * 2
		merge_material_cost(result, autolathe_material_cost(/obj/item/electronics/apc))
		var/cell_type = desired["cell_type"]
		if(!ispath(cell_type, /obj/item/stock_parts/power_store))
			var/obj/machinery/power/apc/apc_type = target_path
			cell_type = initial(apc_type.cell_type)
		var/list/cell_cost = autolathe_material_cost(cell_type)
		merge_material_cost(result, cell_cost)
		if(!length(cell_cost))
			merge_material_cost(result, declared_material_cost(cell_type))
	else if(ispath(target_path, /obj/machinery/airalarm))
		result[/datum/material/iron] = (result[/datum/material/iron] || 0) + SHEET_MATERIAL_AMOUNT * 2
		merge_material_cost(result, autolathe_material_cost(/obj/item/electronics/airalarm))
	else if(ispath(target_path, /obj/machinery/power/terminal))
		if(!length(result))
			result[/datum/material/iron] = SHEET_MATERIAL_AMOUNT
	else if(ispath(target_path, /obj/machinery/door))
		if(!length(result))
			result[/datum/material/iron] = SHEET_MATERIAL_AMOUNT * 2
			result[/datum/material/glass] = HALF_SHEET_MATERIAL_AMOUNT
	return result

/// Serialize colocated mapping helpers for a generated target family.
/datum/ship_plan/template/proc/collect_helper_specs(list/members, list/member_attributes, helper_base)
	var/list/result = list()
	for(var/member_index in 1 to length(members))
		var/helper_path = members[member_index]
		if(!ispath(helper_path, helper_base))
			continue
		var/list/helper_vars = member_attributes[member_index]
		result += list(list(
			"path" = helper_path,
			"vars" = islist(helper_vars) ? helper_vars.Copy() : list(),
		))
	return result

/// Add an object that is prepared in nullspace and commissioned on placement.
/datum/ship_plan/template/proc/add_generated_operation(target_path, rel_x, rel_y, list/desired, list/helper_specs, phase = SHIPYARD_PHASE_FINAL)
	add_operation(new /datum/ship_plan_op(
		phase,
		rel_x,
		rel_y,
		SHIPYARD_OP_GENERATED,
		target_path,
		generated_material_cost(target_path, desired),
		desired,
		null,
		helper_specs,
	))

/// Translate one parsed map cell into ordered, constructible operations.
/datum/ship_plan/template/proc/classify_model(list/model, rel_x, rel_y)
	var/list/members = model[1]
	var/list/member_attributes = model[2]
	var/turf_path
	var/has_apc = FALSE
	for(var/member_index in 1 to length(members))
		var/member_path = members[member_index]
		if(ispath(member_path, /turf))
			turf_path = member_path
		else if(ispath(member_path, /obj/machinery/power/apc))
			has_apc = TRUE
	if(!turf_path || ispath(turf_path, /turf/open/space) || ispath(turf_path, /turf/template_noop))
		return

	add_operation(new /datum/ship_plan_op(
		SHIPYARD_PHASE_RODS,
		rel_x,
		rel_y,
		SHIPYARD_OP_RODS,
		/turf/open/floor/plating,
		list(/datum/material/iron = HALF_SHEET_MATERIAL_AMOUNT),
	))
	add_operation(new /datum/ship_plan_op(
		SHIPYARD_PHASE_PLATING,
		rel_x,
		rel_y,
		SHIPYARD_OP_PLATING,
		/turf/open/floor/plating,
		list(/datum/material/iron = SHEET_MATERIAL_AMOUNT),
	))

	if(ispath(turf_path, /turf/closed))
		add_operation(new /datum/ship_plan_op(
			SHIPYARD_PHASE_FRAMES,
			rel_x,
			rel_y,
			SHIPYARD_OP_GIRDER,
			/obj/structure/girder,
			list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2),
		))
		add_operation(new /datum/ship_plan_op(
			SHIPYARD_PHASE_STRUCTURE,
			rel_x,
			rel_y,
			SHIPYARD_OP_TURF,
			turf_path,
			wall_material_cost(turf_path),
		))

	for(var/member_index in 1 to length(members))
		var/member_path = members[member_index]
		if(ispath(member_path, /turf) || ispath(member_path, /area) || ispath(member_path, /obj/docking_port))
			continue
		if(ispath(member_path, /obj/effect/mapping_helpers/airlock) \
			|| ispath(member_path, /obj/effect/mapping_helpers/airalarm) \
			|| ispath(member_path, /obj/effect/mapping_helpers/apc))
			continue
		var/list/desired = sanitize_desired_vars(member_attributes[member_index])
		if(ispath(member_path, /obj/machinery/computer))
			add_machine_operations(member_path, rel_x, rel_y, desired, TRUE)
		else if(ispath(member_path, /obj/machinery))
			if(ispath(member_path, /obj/machinery/door))
				add_generated_operation(
					member_path,
					rel_x,
					rel_y,
					desired,
					collect_helper_specs(members, member_attributes, /obj/effect/mapping_helpers/airlock),
				)
			else if(ispath(member_path, /obj/machinery/light))
				add_generated_operation(member_path, rel_x, rel_y, desired)
			else if(ispath(member_path, /obj/machinery/portable_atmospherics/canister))
				add_generated_operation(member_path, rel_x, rel_y, desired)
			else if(ispath(member_path, /obj/machinery/power/apc))
				add_generated_operation(
					member_path,
					rel_x,
					rel_y,
					desired,
					collect_helper_specs(members, member_attributes, /obj/effect/mapping_helpers/apc),
				)
			else if(ispath(member_path, /obj/machinery/airalarm))
				add_generated_operation(
					member_path,
					rel_x,
					rel_y,
					desired,
					collect_helper_specs(members, member_attributes, /obj/effect/mapping_helpers/airalarm),
				)
			else if(ispath(member_path, /obj/machinery/power/terminal))
				if(!has_apc)
					add_generated_operation(member_path, rel_x, rel_y, desired, phase = SHIPYARD_PHASE_NETWORKS)
			else if(ispath(member_path, /obj/machinery/atmospherics))
				add_operation(new /datum/ship_plan_op(
					SHIPYARD_PHASE_NETWORKS,
					rel_x,
					rel_y,
					SHIPYARD_OP_OBJECT,
					member_path,
					list(/datum/material/iron = SHEET_MATERIAL_AMOUNT),
					desired,
				))
				add_commission_operation(member_path, rel_x, rel_y, desired)
			else
				add_machine_operations(member_path, rel_x, rel_y, desired, FALSE)
		else if(ispath(member_path, /obj/structure/chair) || ispath(member_path, /obj/structure/closet))
			add_generated_operation(member_path, rel_x, rel_y, desired)
		else if(ispath(member_path, /obj/structure/cable) || ispath(member_path, /obj/structure/disposalpipe))
			add_operation(new /datum/ship_plan_op(
				SHIPYARD_PHASE_NETWORKS,
				rel_x,
				rel_y,
				SHIPYARD_OP_OBJECT,
				member_path,
				list(/datum/material/iron = HALF_SHEET_MATERIAL_AMOUNT),
				desired,
			))
			add_commission_operation(member_path, rel_x, rel_y, desired)
		else if(ispath(member_path, /obj/structure/grille) || ispath(member_path, /obj/structure/window))
			add_operation(new /datum/ship_plan_op(
				SHIPYARD_PHASE_STRUCTURE,
				rel_x,
				rel_y,
				SHIPYARD_OP_OBJECT,
				member_path,
				list(/datum/material/iron = HALF_SHEET_MATERIAL_AMOUNT, /datum/material/glass = SHEET_MATERIAL_AMOUNT),
				desired,
			))
			add_commission_operation(member_path, rel_x, rel_y, desired)
		else
			skipped_contents += "[member_path] at ([rel_x], [rel_y])"

/datum/ship_plan/template/proc/add_machine_operations(machine_path, rel_x, rel_y, list/desired, computer)
	var/board_path
	if(computer)
		var/obj/machinery/computer/computer_type = machine_path
		board_path = initial(computer_type.circuit)
	else
		var/obj/machinery/machine_type = machine_path
		board_path = initial(machine_type.circuit)
	if(!ispath(board_path, /obj/item/circuitboard))
		skipped_contents += "[machine_path] at ([rel_x], [rel_y]) (no constructible board)"
		return
	add_operation(new /datum/ship_plan_op(
		SHIPYARD_PHASE_FRAMES,
		rel_x,
		rel_y,
		computer ? SHIPYARD_OP_COMPUTER_FRAME : SHIPYARD_OP_MACHINE_FRAME,
		machine_path,
		list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 5),
		desired,
		board_path,
	))
	add_operation(new /datum/ship_plan_op(
		SHIPYARD_PHASE_FINAL,
		rel_x,
		rel_y,
		computer ? SHIPYARD_OP_COMPUTER : SHIPYARD_OP_MACHINE,
		machine_path,
		list(/datum/material/glass = computer ? SHEET_MATERIAL_AMOUNT * 2 : 0),
		desired,
		board_path,
	))
	add_commission_operation(machine_path, rel_x, rel_y, desired)

/datum/ship_plan/template/proc/add_commission_operation(target_path, rel_x, rel_y, list/desired)
	if(!length(desired))
		return
	add_operation(new /datum/ship_plan_op(
		SHIPYARD_PHASE_COMMISSIONING,
		rel_x,
		rel_y,
		SHIPYARD_OP_COMMISSION,
		target_path,
		null,
		desired,
	))

/datum/ship_plan/template/proc/sanitize_desired_vars(list/raw_vars)
	var/list/sanitized = list()
	if(!islist(raw_vars))
		return sanitized
	var/static/list/allowed = list(
		"anchored",
		"areastring",
		"auto_name",
		"cable_layer",
		"cell_type",
		"chargemode",
		"color",
		"dir",
		"environ",
		"equipment",
		"greyscale_colors",
		"initialize_directions",
		"lighting",
		"locked",
		"name",
		"pipe_color",
		"piping_layer",
		"req_access",
		"req_one_access",
		"start_charge",
		"welded",
	)
	for(var/var_name in allowed)
		if(var_name in raw_vars)
			sanitized[var_name] = raw_vars[var_name]
	return sanitized

/// Stable phase-first ordering for manifest operations.
/proc/cmp_ship_plan_ops(datum/ship_plan_op/left, datum/ship_plan_op/right)
	if(left.phase != right.phase)
		return left.phase - right.phase
	if(left.rel_y != right.rel_y)
		return left.rel_y - right.rel_y
	return left.rel_x - right.rel_x

/// Catalog v1: explicit opt-in shuttle templates only.
/proc/get_fabricable_ship_plans()
	var/static/list/fabricable_template_types = list(
		/datum/map_template/shuttle/whiteship/personalshuttle,
	)
	var/list/plans = list()
	for(var/template_type in fabricable_template_types)
		var/datum/map_template/shuttle/template = new template_type()
		var/datum/ship_plan/template/plan = new(template)
		if(length(plan.manifest))
			plans += plan
		else
			qdel(plan)
	return plans

