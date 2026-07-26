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
	/// Finished stock parts consumed from the docked RPED before direct generation.
	var/list/required_parts = list()

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
	list/required_parts,
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
	if(required_parts)
		src.required_parts = required_parts.Copy()

/// Returns a JSON-friendly summary for the fabricator UI.
/datum/ship_plan_op/proc/as_list()
	return list(
		"phase" = phase,
		"x" = rel_x,
		"y" = rel_y,
		"operation" = op_type,
		"target" = target_path ? "[target_path]" : null,
	)

GLOBAL_LIST_INIT(shipyard_generators, build_shipyard_generator_registry())

/proc/build_shipyard_generator_registry()
	var/list/registry = list()
	for(var/generator_type in subtypesof(/datum/shipyard_generator))
		var/datum/shipyard_generator/generator = new generator_type
		if(generator.target_type)
			registry[generator.target_type] = generator
	return registry

/proc/get_shipyard_generator(target_type)
	while(target_type)
		var/datum/shipyard_generator/generator = GLOB.shipyard_generators[target_type]
		if(generator)
			return generator
		target_type = type2parent(target_type)
	return null

/// Declarative construction recipe for a directly reproduced mapped type.
/datum/shipyard_generator
	/// Base or exact map type handled by this recipe.
	var/target_type
	/// Silo materials. Empty recipes resolve the target's print/declaration cost.
	var/list/materials = list()
	/// Additional finished item paths whose autolathe costs come from the silo.
	var/list/autolathe_inputs = list()
	/// Finished stock parts consumed from the docked RPED.
	var/list/required_parts = list()
	/// Optional board for conventional machine-frame construction.
	var/board_path
	/// Mapping-helper family delegated to the completed target.
	var/helper_type
	/// Construction phase for direct generation.
	var/phase = SHIPYARD_PHASE_FINAL
	/// Suppress a standalone terminal when its tile already contains an APC.
	var/skip_on_apc_tile = FALSE

/datum/shipyard_generator/proc/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	var/list/result
	if(length(materials))
		result = materials.Copy()
	else
		result = plan.autolathe_material_cost(produced_type)
		if(!length(result))
			result = plan.declared_material_cost(produced_type)
	for(var/input_path in autolathe_inputs)
		plan.merge_material_cost(result, plan.autolathe_material_cost(input_path))
	return result

/datum/shipyard_generator/proc/add_to_plan(
	datum/ship_plan/template/plan,
	produced_type,
	rel_x,
	rel_y,
	list/desired,
	list/members,
	list/member_attributes,
	has_apc,
)
	if(skip_on_apc_tile && has_apc)
		return
	if(board_path)
		plan.add_machine_operations(produced_type, rel_x, rel_y, desired, FALSE, board_path)
		return
	var/list/helper_specs
	if(helper_type)
		helper_specs = plan.collect_helper_specs(members, member_attributes, helper_type)
	plan.add_generated_operation(
		produced_type,
		rel_x,
		rel_y,
		desired,
		helper_specs,
		phase,
		resolve_materials(plan, produced_type, desired),
		required_parts,
	)

/datum/shipyard_generator/light
	target_type = /obj/machinery/light
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

/datum/shipyard_generator/light/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	. = ..()
	var/light_item = ispath(produced_type, /obj/machinery/light/small) ? /obj/item/light/bulb : /obj/item/light/tube
	plan.merge_material_cost(., plan.autolathe_material_cost(light_item))

/datum/shipyard_generator/chair
	target_type = /obj/structure/chair

/datum/shipyard_generator/chair/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	// Chair subtypes declare their actual construction stock (for example, shuttle
	// seats use titanium while ordinary chairs use iron).
	return plan.declared_material_cost(produced_type)

/datum/shipyard_generator/closet
	target_type = /obj/structure/closet
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

/datum/shipyard_generator/canister
	target_type = /obj/machinery/portable_atmospherics/canister
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 10)

/datum/shipyard_generator/apc
	target_type = /obj/machinery/power/apc
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	autolathe_inputs = list(/obj/item/electronics/apc)
	helper_type = /obj/effect/mapping_helpers/apc

/datum/shipyard_generator/apc/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	. = ..()
	var/cell_type = desired["cell_type"]
	if(!ispath(cell_type, /obj/item/stock_parts/power_store))
		var/obj/machinery/power/apc/apc_type = produced_type
		cell_type = initial(apc_type.cell_type)
	var/list/cell_cost = plan.autolathe_material_cost(cell_type)
	if(!length(cell_cost))
		cell_cost = plan.declared_material_cost(cell_type)
	plan.merge_material_cost(., cell_cost)

/datum/shipyard_generator/airalarm
	target_type = /obj/machinery/airalarm
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	autolathe_inputs = list(/obj/item/electronics/airalarm)
	helper_type = /obj/effect/mapping_helpers/airalarm

/datum/shipyard_generator/terminal
	target_type = /obj/machinery/power/terminal
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT)
	phase = SHIPYARD_PHASE_NETWORKS
	skip_on_apc_tile = TRUE

/datum/shipyard_generator/airlock
	target_type = /obj/machinery/door
	materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2,
		/datum/material/glass = HALF_SHEET_MATERIAL_AMOUNT,
	)
	helper_type = /obj/effect/mapping_helpers/airlock

/datum/shipyard_generator/tiny_fan
	target_type = /obj/structure/fans/tiny
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

/datum/shipyard_generator/metal_barricade
	target_type = /obj/structure/deployable_barricade/metal
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

/datum/shipyard_generator/plasteel_barricade
	target_type = /obj/structure/deployable_barricade/metal/plasteel
	materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2,
		/datum/material/alloy/plasteel = SHEET_MATERIAL_AMOUNT * 2,
	)

/datum/shipyard_generator/megacell_charger
	target_type = /obj/machinery/power/megacell_charger
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 7)
	required_parts = list(/datum/stock_part/capacitor = 1)

/datum/shipyard_generator/wall_multicell_charger
	target_type = /obj/machinery/cell_charger_multi/wall_mounted
	board_path = /obj/item/circuitboard/machine/cell_charger_multi

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
	for(var/part_path in operation.required_parts)
		required_parts[part_path] = (required_parts[part_path] || 0) + operation.required_parts[part_path]

/datum/ship_plan/proc/phase_counts()
	var/list/counts = list()
	for(var/datum/ship_plan_op/operation as anything in manifest)
		counts["[operation.phase]"] = (counts["[operation.phase]"] || 0) + 1
	return counts

/datum/ship_plan/proc/skipped_report(show_debug_details = FALSE)
	var/list/report = list()
	for(var/list/skipped as anything in skipped_contents)
		var/atom/skipped_type = skipped["path"]
		var/item_name = initial(skipped_type.name) || "unknown item"
		if(show_debug_details)
			var/reason = skipped["reason"]
			var/rel_x = skipped["x"]
			var/rel_y = skipped["y"]
			report += "[skipped_type] at ([rel_x], [rel_y])[reason ? " ([reason])" : ""]"
		else
			report += item_name
	return report

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
/datum/ship_plan/template/proc/add_generated_operation(
	target_path,
	rel_x,
	rel_y,
	list/desired,
	list/helper_specs,
	phase = SHIPYARD_PHASE_FINAL,
	list/material_override,
	list/required_parts,
)
	var/list/resolved_materials = material_override
	if(!resolved_materials)
		var/datum/shipyard_generator/generator = get_shipyard_generator(target_path)
		resolved_materials = generator ? generator.resolve_materials(src, target_path, desired) : declared_material_cost(target_path)
	add_operation(new /datum/ship_plan_op(
		phase,
		rel_x,
		rel_y,
		SHIPYARD_OP_GENERATED,
		target_path,
		resolved_materials,
		desired,
		null,
		helper_specs,
		required_parts,
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
		var/datum/shipyard_generator/generator = get_shipyard_generator(member_path)
		if(generator)
			generator.add_to_plan(src, member_path, rel_x, rel_y, desired, members, member_attributes, has_apc)
		else if(ispath(member_path, /obj/machinery/computer))
			add_machine_operations(member_path, rel_x, rel_y, desired, TRUE)
		else if(ispath(member_path, /obj/machinery))
			if(ispath(member_path, /obj/machinery/atmospherics))
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
			record_skipped(member_path, rel_x, rel_y)

/datum/ship_plan/template/proc/add_machine_operations(machine_path, rel_x, rel_y, list/desired, computer, board_override)
	var/board_path = board_override
	if(computer)
		var/obj/machinery/computer/computer_type = machine_path
		board_path ||= initial(computer_type.circuit)
	else if(!board_path)
		var/obj/machinery/machine_type = machine_path
		board_path = initial(machine_type.circuit)
	if(!ispath(board_path, /obj/item/circuitboard))
		record_skipped(machine_path, rel_x, rel_y, "no constructible board")
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
	add_commission_operation(
		machine_path,
		rel_x,
		rel_y,
		desired,
		ispath(machine_path, /obj/machinery/cell_charger_multi/wall_mounted),
	)

/datum/ship_plan/template/proc/record_skipped(target_path, rel_x, rel_y, reason)
	skipped_contents += list(list(
		"path" = target_path,
		"x" = rel_x,
		"y" = rel_y,
		"reason" = reason,
	))

/datum/ship_plan/template/proc/add_commission_operation(target_path, rel_x, rel_y, list/desired, force = FALSE)
	if(!force && !length(desired))
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

