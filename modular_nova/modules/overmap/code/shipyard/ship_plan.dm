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

// --- Material cost primitives ----------------------------------------------
// These are pure lookups over compile-time metadata, so they are global procs
// and cached where instantiation is involved.

/// Canonical autolathe cost for an exact output path.
/proc/shipyard_printable_material_cost(build_path)
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

/**
 * Material composition declared on an atom path.
 *
 * `custom_materials` is a list var, and DM cannot read the compile-time value
 * of a list var through `initial()`. The composition is therefore read off a
 * cached scratch instance, which also resolves it into material datums the way
 * the rest of the game sees it. Only items and structures are instantiated;
 * machinery is priced from its design, board, or route instead, so nothing
 * with a heavyweight or location-dependent `Initialize()` is built here.
 */
/proc/shipyard_declared_material_cost(atom_path)
	if(!ispath(atom_path, /obj/item) && !ispath(atom_path, /obj/structure))
		return list()
	var/static/list/declared_costs = list()
	var/list/declared = declared_costs[atom_path]
	if(isnull(declared))
		declared = list()
		var/obj/scratch = new atom_path(null)
		for(var/datum/material/material as anything in scratch.custom_materials)
			declared[material.type] = scratch.custom_materials[material]
		qdel(scratch)
		declared_costs[atom_path] = declared
	return declared.Copy()

/// Material content of a number of stack units, read from a scratch stack.
/proc/shipyard_stack_material_cost(stack_path, amount)
	if(!ispath(stack_path, /obj/item/stack) || amount <= 0)
		return list()
	var/list/unit_cost = shipyard_declared_material_cost(stack_path)
	var/list/result = list()
	for(var/material_path in unit_cost)
		result[material_path] = unit_cost[material_path] * amount
	return result

/**
 * Cost of the stacks an object is built from and deconstructs back into.
 *
 * The vars naming those stacks are declared ad hoc on individual structure
 * families rather than on a shared ancestor, so the families that expose them
 * are enumerated here. This is the construction recipe rather than the finished
 * composition, which is what makes a shuttle chair cost titanium and a wooden
 * table cost wood without either needing its own entry in the route registry.
 */
/proc/shipyard_build_stack_material_cost(atom_path)
	if(ispath(atom_path, /obj/structure/chair))
		var/obj/structure/chair/chair_type = atom_path
		return shipyard_stack_material_cost(initial(chair_type.buildstacktype), initial(chair_type.buildstackamount))
	if(ispath(atom_path, /obj/structure/fans))
		var/obj/structure/fans/fan_type = atom_path
		return shipyard_stack_material_cost(initial(fan_type.buildstacktype), initial(fan_type.buildstackamount))
	if(ispath(atom_path, /obj/structure/sink))
		var/obj/structure/sink/sink_type = atom_path
		return shipyard_stack_material_cost(initial(sink_type.buildstacktype), initial(sink_type.buildstackamount))
	if(ispath(atom_path, /obj/structure/window))
		var/obj/structure/window/window_type = atom_path
		return shipyard_stack_material_cost(initial(window_type.glass_type), initial(window_type.glass_amount))
	if(ispath(atom_path, /obj/structure/grille))
		var/obj/structure/grille/grille_type = atom_path
		return shipyard_stack_material_cost(initial(grille_type.rods_type), initial(grille_type.rods_amount))
	if(ispath(atom_path, /obj/structure/table))
		var/obj/structure/table/table_type = atom_path
		var/list/cost = shipyard_stack_material_cost(initial(table_type.framestack), initial(table_type.framestackamount))
		var/list/surface = shipyard_stack_material_cost(initial(table_type.buildstack), initial(table_type.buildstackamount))
		for(var/material_path in surface)
			cost[material_path] = (cost[material_path] || 0) + surface[material_path]
		return cost
	return list()

/// The shared singleton for a material path, or null if it is not one.
/proc/shipyard_material_singleton(material_path)
	if(!ispath(material_path, /datum/material))
		return null
	var/datum/material/material_type = material_path
	if(initial(material_type.init_flags) & MATERIAL_INIT_BESPOKE)
		return null
	return SSmaterials.get_material(material_path)

/// Silo-storable equivalent of one material, decomposing alloys the ore silo
/// cannot hold into the component materials it can.
/proc/shipyard_silo_equivalent_cost(material_path, amount)
	var/datum/material/material = shipyard_material_singleton(material_path)
	if(!material || (material.mat_flags & MATERIAL_SILO_STORED))
		return list((material_path) = amount)
	// Alloys report their own recursive breakdown; everything else reports
	// itself, and is then refused by the policy if the silo cannot hold it.
	var/list/decomposed = material.return_composition(amount)
	var/list/result = list()
	for(var/datum/material/component as anything in decomposed)
		result[component.type] = (result[component.type] || 0) + decomposed[component]
	return result

/// Reason this cost cannot be paid out of an ore silo, or null when it can.
/proc/shipyard_material_rejection(list/cost)
	for(var/material_path in cost)
		var/datum/material/material = shipyard_material_singleton(material_path)
		if(!material)
			return "unrecognized material input '[material_path]'"
		if(material.mat_flags & MATERIAL_CLASS_ORGANIC)
			return "organic material ([material.name])"
		if(!(material.mat_flags & MATERIAL_SILO_STORED))
			return "material the ore silo cannot store ([material.name])"
	return null

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
	// Frame and finalization operations both carry the board for verification,
	// but only the finalization step actually consumes one.
	if(operation.board_path && (operation.op_type == SHIPYARD_OP_MACHINE || operation.op_type == SHIPYARD_OP_COMPUTER))
		required_parts[operation.board_path] = (required_parts[operation.board_path] || 0) + 1
	for(var/part_path in operation.required_parts)
		required_parts[part_path] = (required_parts[part_path] || 0) + operation.required_parts[part_path]

/datum/ship_plan/proc/phase_counts()
	var/list/counts = list()
	for(var/datum/ship_plan_op/operation as anything in manifest)
		counts["[operation.phase]"] = (counts["[operation.phase]"] || 0) + 1
	return counts

/**
 * Operator-facing summary of everything the manifest will not build.
 *
 * Entries are grouped by reason so a blueprint reports "3 x wooden chair
 * (organic material)" once rather than one line per tile. Without debug rights
 * the report is limited to item names and counts.
 */
/datum/ship_plan/proc/skipped_report(show_debug_details = FALSE, include_ignored = FALSE)
	var/list/grouped = list()
	for(var/list/skipped as anything in skipped_contents)
		if(!include_ignored && skipped["category"] == SHIPYARD_SKIP_IGNORED)
			continue
		var/atom/skipped_type = skipped["path"]
		var/reason = skipped["reason"]
		var/key = show_debug_details ? "[skipped_type]|[reason]" : "[initial(skipped_type.name)]|[reason]"
		var/list/entry = grouped[key]
		if(!entry)
			entry = list("path" = skipped_type, "reason" = reason, "count" = 0)
			grouped[key] = entry
		entry["count"] += 1

	var/list/report = list()
	for(var/key in grouped)
		var/list/entry = grouped[key]
		var/atom/skipped_type = entry["path"]
		var/label = show_debug_details ? "[skipped_type]" : (initial(skipped_type.name) || "unknown item")
		var/count = entry["count"]
		var/reason = entry["reason"]
		report += "[count > 1 ? "[count]x " : ""][label][reason ? " ([reason])" : ""]"
	return report

/// Counts of skipped content per SHIPYARD_SKIP_* category.
/datum/ship_plan/proc/skipped_counts()
	var/list/counts = list()
	for(var/list/skipped as anything in skipped_contents)
		var/category = skipped["category"] || SHIPYARD_SKIP_UNSUPPORTED
		counts[category] = (counts[category] || 0) + 1
	return counts

/// A plan derived from a parsed shuttle DMM without loading it into the world.
/datum/ship_plan/template
	/// Blueprint this plan was parsed from. Held weakly: the shuttle template
	/// registry owns the template, and a plan long outlives the single parse it
	/// needed the template for.
	var/datum/weakref/source_template_ref
	/// Every distinct mapped path seen, mapped to the route that claimed it.
	/// Populated during classification so a blueprint can be validated in one
	/// pass instead of discovering one unsupported path per build attempt.
	var/list/classified_paths = list()

/datum/ship_plan/template/New(datum/map_template/shuttle/template)
	. = ..()
	if(!istype(template))
		return
	source_template_ref = WEAKREF(template)
	name = template.name
	width = template.width
	height = template.height
	build_manifest()

/datum/ship_plan/template/proc/build_manifest()
	var/datum/map_template/shuttle/source_template = source_template_ref?.resolve()
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
	if(!length(declared_materials))
		declared_materials = stack_material_cost(initial(wall_type.sheet_type), initial(wall_type.sheet_amount))
	if(!length(declared_materials))
		declared_materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

	// A hull tile cannot be skipped without leaving a hole, so an unpayable wall
	// material is reported rather than dropped. The build will fault on it.
	var/list/normalized = normalize_material_cost(declared_materials)
	var/rejection = shipyard_material_rejection(normalized)
	if(rejection)
		record_skipped(turf_path, null, null, rejection, SHIPYARD_SKIP_UNSUPPORTED)
	return normalized

/**
 * Resolve one tile's worth of the deck a blueprint asked for.
 *
 * Floors name the stack they are laid from and pry back up into, which prices a
 * titanium deck as titanium and a wooden one as wood without either needing an
 * entry of its own. An unpayable deck is skipped rather than faulted, unlike a
 * wall: an untiled tile is bare hull plating, where an unbuilt wall is a hole.
 */
/datum/ship_plan/template/proc/floor_material_cost(turf_path, rel_x, rel_y)
	var/turf/open/floor/floor_type = turf_path
	var/tile_amount = 1
	// A reinforced deck is rodded rather than tiled, and the count it comes back
	// up as lives on a var its own family declares.
	if(ispath(turf_path, /turf/open/floor/engine))
		var/turf/open/floor/engine/reinforced_type = turf_path
		tile_amount = initial(reinforced_type.floor_tile_amount)
	var/list/declared_materials = stack_material_cost(initial(floor_type.floor_tile), tile_amount)
	if(!length(declared_materials))
		declared_materials = initial(floor_type.custom_materials)
	return apply_material_policy(declared_materials, turf_path, rel_x, rel_y)

/// Resolve the material content of a number of stack units.
/datum/ship_plan/template/proc/stack_material_cost(stack_path, amount)
	return shipyard_stack_material_cost(stack_path, amount)

/// Merge a material dictionary into another without retaining shared lists.
/datum/ship_plan/template/proc/merge_material_cost(list/target, list/additional)
	for(var/material in additional)
		target[material] = (target[material] || 0) + additional[material]
	return target

/// Return the canonical autolathe cost for an exact output path.
/datum/ship_plan/template/proc/printable_material_cost(build_path)
	return shipyard_printable_material_cost(build_path)

/// Material declaration on an atom path, normalized into a fresh list.
/datum/ship_plan/template/proc/declared_material_cost(atom_path)
	return shipyard_declared_material_cost(atom_path)

/**
 * Unified cost resolution for one construction target.
 *
 * Precedence is deterministic so that a route only has to override the cases
 * its family genuinely gets wrong:
 *   1. explicit route override
 *   2. exact printable design
 *   3. construction stack recipe
 *   4. declared material composition
 *   5. wall mount frame composition
 *   6. machine board decomposition
 *   7. fail closed with an empty cost
 */
/datum/ship_plan/template/proc/resolve_construction_cost(produced_type, list/desired, datum/shipyard_route/route)
	if(length(route?.materials))
		return route.materials.Copy()

	var/list/resolved = printable_material_cost(produced_type)
	if(length(resolved))
		return resolved

	resolved = shipyard_build_stack_material_cost(produced_type)
	if(length(resolved))
		return resolved

	resolved = declared_material_cost(produced_type)
	if(length(resolved))
		return resolved

	var/frame_path = get_shipyard_wallframe(produced_type)
	if(frame_path)
		resolved = shipyard_printed_component_cost(frame_path, 1)
		if(length(resolved))
			return resolved

	var/board_path = route?.board_path
	if(!board_path && ispath(produced_type, /obj/machinery))
		var/obj/machinery/machine_type = produced_type
		board_path = initial(machine_type.circuit)
	if(ispath(board_path, /obj/item/circuitboard/machine))
		var/list/requirements = shipyard_board_requirements(board_path)
		var/list/board_materials = requirements["materials"]
		if(length(board_materials))
			return board_materials.Copy()

	return list()

/// Break alloys the ore silo cannot hold into the components it can.
/datum/ship_plan/template/proc/normalize_material_cost(list/cost)
	var/list/normalized = list()
	for(var/material_path in cost)
		var/amount = cost[material_path]
		if(!ispath(material_path, /datum/material) || amount <= 0)
			normalized[material_path] = amount
			continue
		merge_material_cost(normalized, shipyard_silo_equivalent_cost(material_path, amount))
	return normalized

/**
 * Normalize a resolved cost and fail closed when the silo could never pay it.
 *
 * Returns the payable cost, or an empty list after recording why the target was
 * skipped. Organic and non-silo-storable inputs are blacklisted automatically,
 * which is what keeps wood, bamboo, cloth, bone, and hide content out.
 */
/datum/ship_plan/template/proc/apply_material_policy(list/cost, produced_type, rel_x, rel_y)
	if(!length(cost))
		record_skipped(produced_type, rel_x, rel_y, "no fabrication material recipe", SHIPYARD_SKIP_UNSUPPORTED)
		return list()
	var/list/normalized = normalize_material_cost(cost)
	var/rejection = shipyard_material_rejection(normalized)
	if(rejection)
		record_skipped(produced_type, rel_x, rel_y, rejection, SHIPYARD_SKIP_BLACKLISTED)
		return list()
	return normalized

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
		var/datum/shipyard_route/route = get_shipyard_route(target_path)
		resolved_materials = route ? route.resolve_materials(src, target_path, desired) : declared_material_cost(target_path)
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

/// Add an object constructed directly on its turf, then commissioned in place.
/// Used where nullspace initialization would break network discovery.
/datum/ship_plan/template/proc/add_placement_operation(
	target_path,
	rel_x,
	rel_y,
	list/desired,
	phase = SHIPYARD_PHASE_NETWORKS,
	list/material_cost,
)
	add_operation(new /datum/ship_plan_op(
		phase,
		rel_x,
		rel_y,
		SHIPYARD_OP_OBJECT,
		target_path,
		material_cost,
		desired,
	))
	add_commission_operation(target_path, rel_x, rel_y, desired)

/**
 * Tile the deck a blueprint asked for over the hull.
 *
 * The plating phase lays every tile as bare hull plating, so a deck is only worth
 * an operation where the blueprint wants something else on top of it. Emitted
 * here rather than from content classification so that it sorts ahead of the
 * decals for the same tile, which the turf change underneath them would wipe.
 */
/datum/ship_plan/template/proc/add_deck_operation(turf_path, rel_x, rel_y, list/desired)
	// Plating in the blueprint is the hull layer the plating phase already laid.
	// Its subtypes vary by starting gas mix, which a built tile does not inherit
	// anyway, so they are the same tile as far as construction is concerned.
	if(!ispath(turf_path, /turf/open/floor) || ispath(turf_path, /turf/open/floor/plating))
		return
	var/list/cost = floor_material_cost(turf_path, rel_x, rel_y)
	if(!length(cost))
		return
	add_operation(new /datum/ship_plan_op(
		SHIPYARD_PHASE_STRUCTURE,
		rel_x,
		rel_y,
		SHIPYARD_OP_TURF,
		turf_path,
		cost,
		desired,
	))

/// Add a turf decal. Paint carries no material cost and leaves no object
/// behind, so it is neither billed nor commissioned.
/datum/ship_plan/template/proc/add_paint_operation(target_path, rel_x, rel_y, list/desired, phase = SHIPYARD_PHASE_STRUCTURE)
	add_operation(new /datum/ship_plan_op(
		phase,
		rel_x,
		rel_y,
		SHIPYARD_OP_DECAL,
		target_path,
		null,
		desired,
	))

/// Translate one parsed map cell into ordered, constructible operations.
/datum/ship_plan/template/proc/classify_model(list/model, rel_x, rel_y)
	var/list/members = model[1]
	var/list/member_attributes = model[2]
	var/turf_path
	var/list/turf_attributes
	var/has_apc = FALSE
	for(var/member_index in 1 to length(members))
		var/member_path = members[member_index]
		if(ispath(member_path, /turf))
			turf_path = member_path
			turf_attributes = member_attributes[member_index]
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
	else
		add_deck_operation(turf_path, rel_x, rel_y, sanitize_desired_vars(turf_attributes))

	for(var/member_index in 1 to length(members))
		var/member_path = members[member_index]
		if(ispath(member_path, /turf) || ispath(member_path, /area))
			continue
		if(is_route_owned_helper(member_path))
			continue
		var/list/desired = sanitize_desired_vars(member_attributes[member_index])
		classify_content(member_path, rel_x, rel_y, desired, members, member_attributes, has_apc)

/// TRUE when a mapping helper is replayed by the route of a colocated target
/// rather than classified as construction content of its own.
/datum/ship_plan/template/proc/is_route_owned_helper(member_path)
	for(var/helper_base in GLOB.shipyard_route_helper_bases)
		if(ispath(member_path, helper_base))
			return TRUE
	return FALSE

/// Dispatch one mapped object through its construction route.
/datum/ship_plan/template/proc/classify_content(
	member_path,
	rel_x,
	rel_y,
	list/desired,
	list/members,
	list/member_attributes,
	has_apc,
	depth = 0,
)
	if(depth >= SHIPYARD_EXPANSION_DEPTH)
		record_skipped(member_path, rel_x, rel_y, "spawner nesting is too deep to replay", SHIPYARD_SKIP_UNSUPPORTED)
		return
	var/datum/shipyard_route/route = get_shipyard_route(member_path)
	classified_paths[member_path] = route?.type
	if(!route)
		record_skipped(member_path, rel_x, rel_y, "no construction route", SHIPYARD_SKIP_UNSUPPORTED)
		return
	route.add_to_plan(src, member_path, rel_x, rel_y, desired, members, member_attributes, has_apc, depth)

/**
 * One line per distinct mapped path describing the decision made for it.
 *
 * This is the aggregate diagnostic: it reports the whole blueprint's coverage
 * at once rather than surfacing a single unsupported path per build attempt.
 */
/datum/ship_plan/template/proc/route_report()
	var/list/reasons = list()
	for(var/list/skipped as anything in skipped_contents)
		var/skipped_path = skipped["path"]
		if(reasons[skipped_path])
			continue
		reasons[skipped_path] = "[skipped["category"]]: [skipped["reason"]]"

	var/list/report = list()
	for(var/mapped_path in classified_paths)
		var/decision = reasons[mapped_path] || "built by [classified_paths[mapped_path]]"
		report += "[mapped_path] -> [decision]"
	return report

/**
 * Emit frame, board, and finalization operations for a constructible machine.
 *
 * Board components split two ways: anything the fabricator can print itself is
 * billed to the ore silo and injected at finalization, while finished stock
 * parts remain a requirement on the docked RPED.
 */
/datum/ship_plan/template/proc/add_machine_operations(machine_path, rel_x, rel_y, list/desired, computer, datum/shipyard_route/route)
	var/board_path = route?.board_path
	if(!board_path)
		var/obj/machinery/machine_type = machine_path
		board_path = initial(machine_type.circuit)
	if(!ispath(board_path, /obj/item/circuitboard))
		record_skipped(machine_path, rel_x, rel_y, "no constructible circuit board", SHIPYARD_SKIP_UNSUPPORTED)
		return

	var/list/requirements = shipyard_board_requirements(board_path)
	var/list/component_materials = apply_material_policy_soft(requirements["materials"], machine_path, rel_x, rel_y)
	var/list/board_parts = requirements["parts"]
	var/list/component_parts = board_parts.Copy()
	for(var/part_path in route?.required_parts)
		component_parts[part_path] = (component_parts[part_path] || 0) + route.required_parts[part_path]

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
	var/list/finalization_cost = list()
	if(computer)
		finalization_cost[/datum/material/glass] = SHEET_MATERIAL_AMOUNT * 2
	merge_material_cost(finalization_cost, component_materials)
	add_operation(new /datum/ship_plan_op(
		SHIPYARD_PHASE_FINAL,
		rel_x,
		rel_y,
		computer ? SHIPYARD_OP_COMPUTER : SHIPYARD_OP_MACHINE,
		machine_path,
		finalization_cost,
		desired,
		board_path,
		null,
		component_parts,
	))
	// A wall fixture still needs a commissioning pass with no mapped vars, so
	// the route can hang it on its neighbouring wall once the frame is closed.
	add_commission_operation(machine_path, rel_x, rel_y, desired, route?.wall_mounted)

/// Material policy for costs that only partially fund an operation. An
/// unpayable component is reported without cancelling the whole machine.
/datum/ship_plan/template/proc/apply_material_policy_soft(list/cost, produced_type, rel_x, rel_y)
	if(!length(cost))
		return list()
	var/list/normalized = normalize_material_cost(cost)
	var/rejection = shipyard_material_rejection(normalized)
	if(!rejection)
		return normalized
	record_skipped(produced_type, rel_x, rel_y, "component uses [rejection]", SHIPYARD_SKIP_UNSUPPORTED)
	return normalized

/datum/ship_plan/template/proc/record_skipped(target_path, rel_x, rel_y, reason, category = SHIPYARD_SKIP_UNSUPPORTED)
	skipped_contents += list(list(
		"path" = target_path,
		"x" = rel_x,
		"y" = rel_y,
		"reason" = reason,
		"category" = category,
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
		"alpha",
		"anchored",
		"areastring",
		"auto_name",
		"cable_color",
		"cable_layer",
		"cell_type",
		"chargemode",
		"color",
		"dir",
		"dpdir",
		"environ",
		"equipment",
		"greyscale_colors",
		"icon_state",
		"initialize_directions",
		"layer",
		"lighting",
		"locked",
		"name",
		"pipe_color",
		"pipe_flags",
		"piping_layer",
		// A wall fixture whose family has no directional subtypes is hung by
		// shifting it off the tile centre by hand, so the shift is the only record
		// of which wall the blueprint meant it to be on.
		"pixel_x",
		"pixel_y",
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
		/datum/map_template/shuttle/overmap/frigate/nt_personal,
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

