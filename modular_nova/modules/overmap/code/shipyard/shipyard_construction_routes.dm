// MODULE ID: OVERMAP
// Declarative construction routes. A route answers "how is this mapped type
// reproduced?"; the cost policy in ship_plan.dm answers "what does it cost?".

GLOBAL_LIST_INIT(shipyard_routes, build_shipyard_route_registry())

/proc/build_shipyard_route_registry()
	var/list/registry = list()
	for(var/route_type in subtypesof(/datum/shipyard_route))
		var/datum/shipyard_route/route = new route_type
		if(!route.target_type)
			continue
		if(registry[route.target_type])
			stack_trace("Duplicate shipyard construction route for [route.target_type].")
			continue
		registry[route.target_type] = route
	return registry

/// Nearest-ancestor route lookup for a mapped type.
/proc/get_shipyard_route(target_type)
	var/list/registry = GLOB.shipyard_routes
	while(target_type)
		var/datum/shipyard_route/route = registry[target_type]
		if(route)
			return route
		target_type = type2parent(target_type)
	return null

/// Mapping-helper families that a route delegates to its finished target, and
/// which must therefore not be classified as content in their own right.
GLOBAL_LIST_INIT(shipyard_route_helper_bases, build_shipyard_route_helper_bases())

/proc/build_shipyard_route_helper_bases()
	var/list/bases = list()
	for(var/target_type in GLOB.shipyard_routes)
		var/datum/shipyard_route/route = GLOB.shipyard_routes[target_type]
		if(route.helper_type)
			bases |= route.helper_type
	return bases

/// Atmospherics machinery path to the pipe fitting that constructs it.
GLOBAL_LIST_INIT(shipyard_pipe_fittings, build_shipyard_pipe_fitting_registry())

/proc/build_shipyard_pipe_fitting_registry()
	var/list/registry = list()
	for(var/obj/item/pipe/fitting_type as anything in typesof(/obj/item/pipe))
		var/machinery_path = initial(fitting_type.pipe_type)
		if(!machinery_path || registry[machinery_path])
			continue
		registry[machinery_path] = fitting_type
	return registry

/// Nearest-ancestor lookup for a fitting that dispenses this exact device.
/proc/get_shipyard_dedicated_pipe_fitting(machinery_type)
	var/list/registry = GLOB.shipyard_pipe_fittings
	while(machinery_type)
		var/fitting = registry[machinery_type]
		if(fitting)
			return fitting
		machinery_type = type2parent(machinery_type)
	return null

/// The fitting an RPD consumes to lay a mapped atmospherics device, which is
/// also what the device deconstructs back into. Devices without a dedicated
/// fitting bill the generic shape they are laid as.
/proc/get_shipyard_pipe_fitting(machinery_type)
	if(!ispath(machinery_type, /obj/machinery/atmospherics))
		return null

	var/dedicated = get_shipyard_dedicated_pipe_fitting(machinery_type)
	if(dedicated)
		return dedicated

	var/obj/machinery/atmospherics/device = machinery_type
	return initial(device.construction_type) || /obj/item/pipe

/**
 * Material content of the fitting an RPD consumes to lay a device.
 *
 * Generic fittings describe themselves from the device they are laid as, so
 * they are instantiated with it rather than bare; a fitting with no pipe type
 * runtimes while naming itself.
 */
/proc/shipyard_pipe_fitting_cost(machinery_type)
	var/fitting_path = get_shipyard_pipe_fitting(machinery_type)
	if(!fitting_path)
		return list()

	var/static/list/fitting_costs = list()
	var/list/cost = fitting_costs[fitting_path]
	if(isnull(cost))
		cost = list()
		var/obj/item/pipe/fitting = new fitting_path(null, machinery_type)
		for(var/datum/material/material as anything in fitting.custom_materials)
			cost[material.type] = fitting.custom_materials[material]
		qdel(fitting)
		fitting_costs[fitting_path] = cost
	return cost.Copy()

/// Wall-mounted machinery path to the frame item that becomes it.
GLOBAL_LIST_INIT(shipyard_wallframes, build_shipyard_wallframe_registry())

/proc/build_shipyard_wallframe_registry()
	var/list/registry = list()
	for(var/obj/item/wallframe/frame_type as anything in typesof(/obj/item/wallframe))
		var/mounted_path = initial(frame_type.result_path)
		if(!mounted_path || registry[mounted_path])
			continue
		registry[mounted_path] = frame_type
	return registry

/**
 * The frame a mapped wall fixture is mounted from.
 *
 * Wall equipment is built by making its frame and applying it to a wall, so the
 * frame is both the construction route and the thing that costs anything. Only
 * an exact match counts: subtypes of a mounted machine ship their own frames.
 */
/proc/get_shipyard_wallframe(machinery_type)
	var/list/registry = GLOB.shipyard_wallframes
	while(machinery_type)
		var/frame_type = registry[machinery_type]
		if(frame_type)
			return frame_type
		machinery_type = type2parent(machinery_type)
	return null

/// Cached decomposition of a machine board into silo materials, printed
/// components the fabricator makes itself, and finished RPED stock parts.
GLOBAL_LIST_EMPTY(shipyard_board_requirements)

/proc/shipyard_board_requirements(board_path)
	var/list/cached = GLOB.shipyard_board_requirements[board_path]
	if(cached)
		return cached

	var/list/requirements = list(
		"materials" = list(),
		"printed" = list(),
		"parts" = list(),
	)
	if(!ispath(board_path, /obj/item/circuitboard/machine))
		GLOB.shipyard_board_requirements[board_path] = requirements
		return requirements

	// `req_components` is a list var, which DM cannot read from a type path, so
	// the board is briefly instantiated to read its own component manifest.
	var/obj/item/circuitboard/machine/board = new board_path(null)
	var/list/components = board.req_components?.Copy() || list()
	var/list/defaults = board.def_components?.Copy()
	qdel(board)
	for(var/component_path in components)
		var/amount = components[component_path]
		if(amount <= 0)
			continue
		var/resolved_path = defaults?[component_path] || component_path
		// Stock parts stay physical: the shipyard pulls them from a docked RPED.
		if(ispath(resolved_path, /datum/stock_part) || ispath(resolved_path, /obj/item/stock_parts))
			requirements["parts"][component_path] = (requirements["parts"][component_path] || 0) + amount
			continue
		var/list/component_cost = shipyard_printed_component_cost(resolved_path, amount)
		if(!length(component_cost))
			requirements["parts"][component_path] = (requirements["parts"][component_path] || 0) + amount
			continue
		for(var/material_path in component_cost)
			requirements["materials"][material_path] = (requirements["materials"][material_path] || 0) + component_cost[material_path]
		requirements["printed"][component_path] = (requirements["printed"][component_path] || 0) + amount

	GLOB.shipyard_board_requirements[board_path] = requirements
	return requirements

/**
 * The physical item that satisfies a part requirement.
 *
 * Board manifests name stock parts as datums rather than items, so a docked
 * RPED is searched for the base item they describe. Every tier is a subtype of
 * that base, which is what lets a better part stand in for the one asked for.
 */
/proc/shipyard_part_item_type(requirement)
	if(!ispath(requirement, /datum/stock_part))
		return requirement
	var/datum/stock_part/stock_part = requirement
	return initial(stock_part.physical_object_base_type)

/// Designs whose output can satisfy one ship-plan dependency.
/proc/shipyard_dependency_designs(requirement)
	var/item_path = shipyard_part_item_type(requirement)
	var/allow_subtypes = ispath(item_path, /obj/item/stock_parts)
	var/list/result = list()
	for(var/design_id in SSresearch.techweb_designs)
		var/datum/design/design = SSresearch.techweb_designs[design_id]
		if(!(design.build_type & (IMPRINTER | PROTOLATHE | AUTOLATHE)))
			continue
		if(design.build_path == item_path || (allow_subtypes && ispath(design.build_path, item_path)))
			result += design
	return result

/// Baseline design embedded by a self-contained stock blueprint.
/proc/shipyard_dependency_design(requirement)
	var/item_path = shipyard_part_item_type(requirement)
	var/datum/design/nearest
	var/nearest_depth = INFINITY
	for(var/datum/design/design as anything in shipyard_dependency_designs(requirement))
		var/depth = 0
		var/cursor = design.build_path
		while(cursor && cursor != item_path)
			depth++
			cursor = type2parent(cursor)
		if(depth < nearest_depth)
			nearest = design
			nearest_depth = depth
	return nearest

/// Relative quality of a dependency design's output.
/proc/shipyard_dependency_design_rating(datum/design/design)
	if(!design)
		return -INFINITY
	var/static/list/ratings = list()
	if(!isnull(ratings[design.id]))
		return ratings[design.id]
	var/obj/item/part = new design.build_path(null)
	var/rating = part?.get_part_rating() || 0
	qdel(part)
	ratings[design.id] = rating
	return rating

/// Silo-storable material cost for a quantity of one selected design.
/proc/shipyard_design_material_cost(datum/design/design, amount = 1)
	if(!design || amount <= 0)
		return list()
	var/list/result = list()
	for(var/material in design.materials)
		var/material_path = material
		if(istype(material, /datum/material))
			var/datum/material/material_datum = material
			material_path = material_datum.type
		var/list/equivalent = shipyard_silo_equivalent_cost(material_path, design.materials[material] * amount)
		for(var/equivalent_path in equivalent)
			result[equivalent_path] = (result[equivalent_path] || 0) + equivalent[equivalent_path]
	if(shipyard_material_rejection(result))
		return list()
	return result

/// Baseline dependency cost used by static manifest analysis.
/proc/shipyard_dependency_material_cost(requirement, amount = 1)
	return shipyard_design_material_cost(shipyard_dependency_design(requirement), amount)

/// Silo cost of printing a quantity of a loose machine component.
/proc/shipyard_printed_component_cost(component_path, amount)
	if(ispath(component_path, /obj/item/stack))
		return shipyard_stack_material_cost(component_path, amount)
	var/list/unit_cost = shipyard_printable_material_cost(component_path)
	if(!length(unit_cost))
		unit_cost = shipyard_declared_material_cost(component_path)
	if(!length(unit_cost))
		return list()
	var/list/result = list()
	for(var/material_path in unit_cost)
		result[material_path] = unit_cost[material_path] * amount
	return result

/// Declarative construction recipe for one mapped type and its descendants.
/datum/shipyard_route
	/// Base or exact map type handled by this route.
	var/target_type
	/// How the target is reproduced. See SHIPYARD_ROUTE_* defines.
	var/strategy = SHIPYARD_ROUTE_GENERATE
	/// Explicit silo cost override. Highest precedence in cost resolution.
	var/list/materials
	/// Concrete types a spawner is replayed as. Used by SHIPYARD_ROUTE_EXPAND.
	var/list/expansion
	/// Extra printable items whose print cost is billed alongside the target.
	var/list/component_inputs
	/// Finished stock parts consumed from the docked RPED.
	var/list/required_parts
	/// Board override for frame construction. Derived from `circuit` when unset.
	var/board_path
	/// Mapping-helper family delegated to the completed target.
	var/helper_type
	/// Construction phase for direct generation and placement.
	var/phase = SHIPYARD_PHASE_FINAL
	/// Suppress a standalone terminal when its tile already contains an APC.
	var/skip_on_apc_tile = FALSE
	/// Hang the finished object on a neighbouring wall once it is in the world.
	var/wall_mounted = FALSE
	/// Join the finished machine to the local powernet once it is in the world.
	var/grid_connected = FALSE
	/// Operator-facing explanation when this route does not build anything.
	var/skip_reason
	/// Diagnostic grouping for skipped content. See SHIPYARD_SKIP_* defines.
	var/skip_category = SHIPYARD_SKIP_UNSUPPORTED

/// Strategy for one concrete descendant. Families whose members split across
/// primitives (atmospherics, generic machinery) resolve it per type.
/datum/shipyard_route/proc/get_strategy(produced_type)
	return strategy

/// TRUE when this route deliberately refuses to build its family.
/datum/shipyard_route/proc/is_blacklisted(produced_type)
	return get_strategy(produced_type) == SHIPYARD_ROUTE_SKIP && skip_category == SHIPYARD_SKIP_BLACKLISTED

/// Concrete types a spawner would have produced.
/datum/shipyard_route/proc/expanded_targets(produced_type, list/desired)
	return expansion

/**
 * Location-dependent activation shared by a whole family.
 *
 * Runs after the target's own `shipyard_commission()` so that per-type hooks
 * stay limited to behaviour the family cannot express declaratively.
 */
/datum/shipyard_route/proc/commission(atom/movable/target, list/desired)
	if(grid_connected)
		var/obj/machinery/power/powered = target
		if(istype(powered))
			powered.connect_to_network()
	// Anything built from a mount frame belongs on a wall by definition, so the
	// frame registry saves every such family from declaring it again.
	if(wall_mounted || get_shipyard_wallframe(target.type))
		var/obj/mountable = target
		if(isobj(mountable))
			mountable.find_and_mount_on_atom()

/// Silo materials for one concrete descendant, before policy normalization.
/datum/shipyard_route/proc/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	var/list/resolved = plan.resolve_construction_cost(produced_type, desired, src)
	for(var/input_path in component_inputs)
		plan.merge_material_cost(resolved, shipyard_printed_component_cost(input_path, 1))
	return resolved

/// Emit the operations that reproduce one mapped instance of this family.
/datum/shipyard_route/proc/add_to_plan(
	datum/ship_plan/template/plan,
	produced_type,
	rel_x,
	rel_y,
	list/desired,
	list/members,
	list/member_attributes,
	has_apc,
	depth = 0,
)
	var/route_strategy = get_strategy(produced_type)
	switch(route_strategy)
		if(SHIPYARD_ROUTE_OMIT)
			return
		if(SHIPYARD_ROUTE_SKIP)
			plan.record_skipped(produced_type, rel_x, rel_y, skip_reason, skip_category)
			return
		if(SHIPYARD_ROUTE_PAINT)
			plan.add_paint_operation(produced_type, rel_x, rel_y, desired, phase)
			return
		if(SHIPYARD_ROUTE_EXPAND)
			var/list/expanded = expanded_targets(produced_type, desired)
			if(!length(expanded))
				plan.record_skipped(produced_type, rel_x, rel_y, skip_reason, skip_category)
				return
			for(var/expanded_type in expanded)
				plan.classify_content(expanded_type, rel_x, rel_y, desired, members, member_attributes, has_apc, depth + 1)
			return
		if(SHIPYARD_ROUTE_MACHINE, SHIPYARD_ROUTE_COMPUTER)
			plan.add_machine_operations(
				produced_type,
				rel_x,
				rel_y,
				desired,
				route_strategy == SHIPYARD_ROUTE_COMPUTER,
				src,
			)
			return

	if(skip_on_apc_tile && has_apc)
		return

	var/list/resolved_materials = plan.apply_material_policy(
		resolve_materials(plan, produced_type, desired),
		produced_type,
		rel_x,
		rel_y,
	)
	if(!length(resolved_materials))
		return

	var/list/helper_specs
	if(helper_type)
		helper_specs = plan.collect_helper_specs(members, member_attributes, helper_type)

	if(route_strategy == SHIPYARD_ROUTE_PLACE)
		plan.add_placement_operation(produced_type, rel_x, rel_y, desired, phase, resolved_materials)
		return
	plan.add_generated_operation(
		produced_type,
		rel_x,
		rel_y,
		desired,
		helper_specs,
		phase,
		resolved_materials,
		required_parts,
	)

// --- Map-only and cosmetic content -----------------------------------------

/datum/shipyard_route/ignored
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_IGNORED

/datum/shipyard_route/ignored/effect
	target_type = /obj/effect
	skip_reason = "map-only effect"

/datum/shipyard_route/ignored/grime
	target_type = /obj/effect/decal
	skip_reason = "surface grime"

/// Turf decals are floor paint: applying one adds a decal to the turf and
/// deletes the effect, so the printer reproduces the blueprint's markings for
/// free instead of leaving the deck blank.
/datum/shipyard_route/turf_decal
	target_type = /obj/effect/turf_decal
	strategy = SHIPYARD_ROUTE_PAINT
	phase = SHIPYARD_PHASE_STRUCTURE

/datum/shipyard_route/ignored/mapping_helper
	target_type = /obj/effect/mapping_helpers
	skip_reason = "mapping helper"

/datum/shipyard_route/ignored/landmark
	target_type = /obj/effect/landmark
	skip_reason = "map landmark"

/datum/shipyard_route/ignored/random_spawner
	target_type = /obj/effect/spawner/random
	skip_reason = "randomized loot spawner"

/datum/shipyard_route/ignored/loose_item
	target_type = /obj/item
	skip_reason = "loose cargo"

/datum/shipyard_route/ignored/occupant
	target_type = /mob
	skip_reason = "living occupant"

/// Registering the finished hull is what creates its docking port, so the
/// mapped one is neither built nor missing and has nothing to report.
/datum/shipyard_route/docking_port
	target_type = /obj/docking_port
	strategy = SHIPYARD_ROUTE_OMIT

// --- Structure spawners -----------------------------------------------------
//
// A spawner's `spawn_list` is a list var, and several families rebuild it from
// their mapped direction during `Initialize()`, so it can be read neither from
// the type path nor from a scratch instance. Each family that the shipyard
// replays therefore declares the concrete structures it stands in for.

/datum/shipyard_route/structure_spawner
	target_type = /obj/effect/spawner/structure
	strategy = SHIPYARD_ROUTE_EXPAND
	skip_reason = "spawner output is decided at runtime"

/datum/shipyard_route/structure_spawner/window
	target_type = /obj/effect/spawner/structure/window
	expansion = list(/obj/structure/grille, /obj/structure/window/fulltile)

/datum/shipyard_route/structure_spawner/window/reinforced
	target_type = /obj/effect/spawner/structure/window/reinforced
	expansion = list(/obj/structure/grille, /obj/structure/window/reinforced/fulltile)

/datum/shipyard_route/structure_spawner/window/reinforced/tinted
	target_type = /obj/effect/spawner/structure/window/reinforced/tinted
	expansion = list(/obj/structure/grille, /obj/structure/window/reinforced/tinted/fulltile)

/datum/shipyard_route/structure_spawner/window/reinforced/shuttle
	target_type = /obj/effect/spawner/structure/window/reinforced/shuttle
	expansion = list(/obj/structure/grille, /obj/structure/window/reinforced/shuttle)

/datum/shipyard_route/structure_spawner/window/reinforced/plastitanium
	target_type = /obj/effect/spawner/structure/window/reinforced/plasma/plastitanium
	expansion = list(/obj/structure/grille, /obj/structure/window/reinforced/plasma/plastitanium)

/datum/shipyard_route/structure_spawner/window/plasma
	target_type = /obj/effect/spawner/structure/window/plasma
	expansion = list(/obj/structure/grille, /obj/structure/window/plasma/fulltile)

/datum/shipyard_route/structure_spawner/window/bronze
	target_type = /obj/effect/spawner/structure/window/bronze
	expansion = list(/obj/structure/grille, /obj/structure/window/bronze/fulltile)

/datum/shipyard_route/structure_spawner/window/ice
	target_type = /obj/effect/spawner/structure/window/ice
	expansion = list(/obj/structure/grille, /obj/structure/window/reinforced/fulltile/ice)

/datum/shipyard_route/structure_spawner/window/survival_pod
	target_type = /obj/effect/spawner/structure/window/survival_pod
	expansion = list(/obj/structure/grille, /obj/structure/window/reinforced/shuttle/survival_pod)

/// Hollow spawners choose their window set from the direction they were mapped
/// in, which the manifest cannot reconstruct from the type alone.
/datum/shipyard_route/structure_spawner/window/hollow
	target_type = /obj/effect/spawner/structure/window/hollow
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "hollow window spawner output depends on its mapped direction"

// --- Generic families -------------------------------------------------------

/// Anything structural the shipyard can price is generated atomically.
/datum/shipyard_route/structure
	target_type = /obj/structure
	phase = SHIPYARD_PHASE_FINAL

/// Greyscale furniture picks its stock when a crewmember crafts it, so the
/// blueprint records no material for the shipyard to bill.
/datum/shipyard_route/greyscale_table
	target_type = /obj/structure/table/greyscale
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "material is chosen at construction time"

/datum/shipyard_route/spacepod
	target_type = /obj/spacepod
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "vehicles are assembled at a vehicle fabricator"

/datum/shipyard_route/vehicle
	target_type = /obj/vehicle
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "vehicles are assembled at a vehicle fabricator"

/// Machines split by whether they have a constructible board. A machine
/// without one is not unbuildable, it is simply not built from a frame: wall
/// equipment mounts from a frame item, so it is generated whole and priced from
/// that stock instead.
/datum/shipyard_route/machinery
	target_type = /obj/machinery
	/// Strategy for members that do have a board to assemble around.
	var/board_strategy = SHIPYARD_ROUTE_MACHINE

/datum/shipyard_route/machinery/get_strategy(produced_type)
	var/obj/machinery/machine_type = produced_type
	return ispath(initial(machine_type.circuit), /obj/item/circuitboard) ? board_strategy : SHIPYARD_ROUTE_GENERATE

/datum/shipyard_route/machinery/computer
	target_type = /obj/machinery/computer
	board_strategy = SHIPYARD_ROUTE_COMPUTER

/// Wrenched down from a hand-held sensor, so the sensor is the whole cost.
/datum/shipyard_route/machinery/air_sensor
	target_type = /obj/machinery/air_sensor
	component_inputs = list(/obj/item/air_sensor)

/// Bins and chutes are welded from the same construct stock as the pipes they
/// terminate, at the scale of a fixture rather than a segment.
/datum/shipyard_route/machinery/disposal_fixture
	target_type = /obj/machinery/disposal
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 4)
	phase = SHIPYARD_PHASE_NETWORKS

// --- Networks ---------------------------------------------------------------

/datum/shipyard_route/cable
	target_type = /obj/structure/cable
	strategy = SHIPYARD_ROUTE_PLACE
	phase = SHIPYARD_PHASE_NETWORKS

/datum/shipyard_route/cable/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	return plan.stack_material_cost(/obj/item/stack/cable_coil, 1)

/datum/shipyard_route/atmospherics
	target_type = /obj/machinery/atmospherics
	strategy = SHIPYARD_ROUTE_PLACE
	phase = SHIPYARD_PHASE_NETWORKS

/datum/shipyard_route/atmospherics/get_strategy(produced_type)
	if(get_shipyard_dedicated_pipe_fitting(produced_type))
		return strategy
	var/obj/machinery/machine_type = produced_type
	return ispath(initial(machine_type.circuit), /obj/item/circuitboard) ? SHIPYARD_ROUTE_MACHINE : strategy

/datum/shipyard_route/atmospherics/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	if(get_strategy(produced_type) != strategy)
		return ..()
	return shipyard_pipe_fitting_cost(produced_type)

/// Disposal pipes are welded from a single pipe segment's worth of plating.
/datum/shipyard_route/disposal_pipe
	target_type = /obj/structure/disposalpipe
	strategy = SHIPYARD_ROUTE_PLACE
	phase = SHIPYARD_PHASE_NETWORKS
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT)

/datum/shipyard_route/disposal_outlet
	target_type = /obj/structure/disposaloutlet
	strategy = SHIPYARD_ROUTE_PLACE
	phase = SHIPYARD_PHASE_NETWORKS
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

/datum/shipyard_route/terminal
	target_type = /obj/machinery/power/terminal
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT)
	phase = SHIPYARD_PHASE_NETWORKS
	skip_on_apc_tile = TRUE
	grid_connected = TRUE

// --- Hull-integral structures ----------------------------------------------

/datum/shipyard_route/window
	target_type = /obj/structure/window
	strategy = SHIPYARD_ROUTE_PLACE
	phase = SHIPYARD_PHASE_STRUCTURE

/// A grille frames its window the way a girder frames a wall, so it goes down
/// with the rest of the framing and is standing before anything is glazed.
/datum/shipyard_route/grille
	target_type = /obj/structure/grille
	strategy = SHIPYARD_ROUTE_PLACE
	phase = SHIPYARD_PHASE_FRAMES

// --- Fixtures and furniture -------------------------------------------------

/datum/shipyard_route/light
	target_type = /obj/machinery/light
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	wall_mounted = TRUE

/datum/shipyard_route/light/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	. = ..()
	var/light_item = ispath(produced_type, /obj/machinery/light/small) ? /obj/item/light/bulb : /obj/item/light/tube
	plan.merge_material_cost(., plan.printable_material_cost(light_item))

/datum/shipyard_route/light_switch
	target_type = /obj/machinery/light_switch
	materials = list(/datum/material/iron = HALF_SHEET_MATERIAL_AMOUNT, /datum/material/glass = SMALL_MATERIAL_AMOUNT)
	wall_mounted = TRUE

/datum/shipyard_route/chair
	target_type = /obj/structure/chair

/datum/shipyard_route/chair/electric
	target_type = /obj/structure/chair/e_chair
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "electrified restraint furniture"

/datum/shipyard_route/chair/greyscale
	target_type = /obj/structure/chair/greyscale
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "material is chosen at construction time"

/datum/shipyard_route/chair/carp
	target_type = /obj/structure/chair/comfy/carp
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "requires carp hide"

/datum/shipyard_route/chair/mime
	target_type = /obj/structure/chair/mime
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "invisible furniture cannot be surveyed"

/datum/shipyard_route/chair/pillow
	target_type = /obj/structure/chair/pillow_small
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "soft furnishing has no fabrication stock"

/datum/shipyard_route/chair/shibari
	target_type = /obj/structure/chair/shibari_stand
	strategy = SHIPYARD_ROUTE_SKIP
	skip_category = SHIPYARD_SKIP_BLACKLISTED
	skip_reason = "restraint furniture"

/datum/shipyard_route/closet
	target_type = /obj/structure/closet
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

/datum/shipyard_route/tiny_fan
	target_type = /obj/structure/fans/tiny
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

/datum/shipyard_route/metal_barricade
	target_type = /obj/structure/deployable_barricade/metal
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)

/datum/shipyard_route/metal_barricade/plasteel
	target_type = /obj/structure/deployable_barricade/metal/plasteel
	materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2,
		/datum/material/alloy/plasteel = SHEET_MATERIAL_AMOUNT * 2,
	)

// --- Wall-mounted power and atmospherics equipment --------------------------

/datum/shipyard_route/airlock
	target_type = /obj/machinery/door
	materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2,
		/datum/material/glass = HALF_SHEET_MATERIAL_AMOUNT,
	)
	helper_type = /obj/effect/mapping_helpers/airlock

/// Poddoors are fabricated from substantially more stock than ordinary airlocks.
/datum/shipyard_route/blast_door
	target_type = /obj/machinery/door/poddoor
	materials = list(
		/datum/material/alloy/plasteel = SHEET_MATERIAL_AMOUNT * 15,
		/datum/material/iron = SMALL_MATERIAL_AMOUNT * 2,
		/datum/material/glass = SMALL_MATERIAL_AMOUNT * 2,
	)

/datum/shipyard_route/shutters
	target_type = /obj/machinery/door/poddoor/shutters
	materials = list(
		/datum/material/alloy/plasteel = SHEET_MATERIAL_AMOUNT * 5,
		/datum/material/iron = SMALL_MATERIAL_AMOUNT,
		/datum/material/glass = SMALL_MATERIAL_AMOUNT,
	)

/// Directional door buttons share the ordinary button frame recipe.
/datum/shipyard_route/door_button
	target_type = /obj/machinery/button/door
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT)
	wall_mounted = TRUE

/datum/shipyard_route/door_button/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	. = ..()
	var/obj/machinery/button/door/button_type = produced_type
	var/normal_control = desired["normaldoorcontrol"]
	if(isnull(normal_control))
		normal_control = initial(button_type.normaldoorcontrol)
	var/controller_path = normal_control ? /obj/item/assembly/control/airlock : /obj/item/assembly/control
	var/list/controller_cost = plan.printable_material_cost(controller_path)
	if(!length(controller_cost) && normal_control)
		controller_cost = plan.printable_material_cost(/obj/item/assembly/control)
		plan.merge_material_cost(controller_cost, plan.printable_material_cost(/obj/item/electronics/airlock))
	plan.merge_material_cost(., controller_cost)
	if(length(desired["req_access"]) || length(desired["req_one_access"]))
		plan.merge_material_cost(., plan.printable_material_cost(/obj/item/electronics/airlock))

/datum/shipyard_route/apc
	target_type = /obj/machinery/power/apc
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	component_inputs = list(/obj/item/electronics/apc)
	helper_type = /obj/effect/mapping_helpers/apc
	wall_mounted = TRUE

/datum/shipyard_route/apc/resolve_materials(datum/ship_plan/template/plan, produced_type, list/desired)
	. = ..()
	var/cell_type = desired["cell_type"]
	if(!ispath(cell_type, /obj/item/stock_parts/power_store))
		var/obj/machinery/power/apc/apc_type = produced_type
		cell_type = initial(apc_type.cell_type)
	var/list/cell_cost = plan.printable_material_cost(cell_type)
	if(!length(cell_cost))
		cell_cost = plan.declared_material_cost(cell_type)
	plan.merge_material_cost(., cell_cost)

/datum/shipyard_route/airalarm
	target_type = /obj/machinery/airalarm
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	component_inputs = list(/obj/item/electronics/airalarm)
	helper_type = /obj/effect/mapping_helpers/airalarm
	wall_mounted = TRUE

/datum/shipyard_route/firealarm
	target_type = /obj/machinery/firealarm
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2)
	component_inputs = list(/obj/item/electronics/firealarm)
	wall_mounted = TRUE

/datum/shipyard_route/canister
	target_type = /obj/machinery/portable_atmospherics/canister
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 10)

/datum/shipyard_route/megacell_charger
	target_type = /obj/machinery/power/megacell_charger
	materials = list(/datum/material/iron = SHEET_MATERIAL_AMOUNT * 7)
	required_parts = list(/datum/stock_part/capacitor = 1)
	wall_mounted = TRUE

/datum/shipyard_route/wall_multicell_charger
	target_type = /obj/machinery/cell_charger_multi/wall_mounted
	strategy = SHIPYARD_ROUTE_MACHINE
	board_path = /obj/item/circuitboard/machine/cell_charger_multi
	wall_mounted = TRUE
