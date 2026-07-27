// MODULE ID: OVERMAP
// Shipyard manifest, paired-frame construction, part scaling, and phase primitives.

/datum/unit_test/overmap_shipyard_fabricator
	abstract_type = /datum/unit_test/overmap_shipyard_fabricator
	priority = TEST_LONGER
/// The icon states a fabricator currently contributes through its overlay pass.
/datum/unit_test/overmap_shipyard_fabricator/proc/overlay_states(obj/machinery/shipyard_fabricator/fabricator)
	var/list/states = list()
	for(var/mutable_appearance/overlay as anything in fabricator.update_overlays())
		states += istext(overlay) ? overlay : overlay.icon_state
	return states

/datum/unit_test/overmap_shipyard_fabricator/manifest

/datum/unit_test/overmap_shipyard_fabricator/manifest/Run()
	var/datum/map_template/shuttle/template = new /datum/map_template/shuttle/whiteship/personalshuttle()
	var/datum/ship_plan/template/plan = new(template)
	TEST_ASSERT(length(plan.manifest), "Personal shuttle template should produce a shipyard manifest.")
	TEST_ASSERT(plan.width > 0 && plan.height > 0, "Manifest should retain parsed template dimensions.")
	TEST_ASSERT(plan.material_cost[/datum/material/iron] > 0, "Manifest should aggregate iron costs.")
	var/list/counts = plan.phase_counts()
	TEST_ASSERT(counts["[SHIPYARD_PHASE_RODS]"] > 0, "Manifest should contain hull rod operations.")
	TEST_ASSERT(counts["[SHIPYARD_PHASE_PLATING]"] > 0, "Manifest should contain hull plating operations.")
	TEST_ASSERT(counts["[SHIPYARD_PHASE_FINAL]"] > 0, "Manifest should contain final construction operations.")
	qdel(plan)

/datum/unit_test/overmap_shipyard_fabricator/solfed_disks

/datum/unit_test/overmap_shipyard_fabricator/solfed_disks/Run()
	var/static/list/disk_types = list(
		/obj/item/ship_blueprint_disk/solfed_cutter,
		/obj/item/ship_blueprint_disk/solfed_cutter/typed,
		/obj/item/ship_blueprint_disk/solfed_patrol,
		/obj/item/ship_blueprint_disk/solfed_patrol/typed,
	)
	var/list/disks = list()
	for(var/disk_type in disk_types)
		var/obj/item/ship_blueprint_disk/disk = allocate(disk_type)
		disks[disk_type] = disk
		disk.load_ship_plan()
		TEST_ASSERT(disk.ship_plan, "[disk_type] should initialize a ship plan.")
		TEST_ASSERT_EQUAL(disk.ship_plan.width, 18, "[disk_type] should retain the frigate template width.")
		TEST_ASSERT_EQUAL(disk.ship_plan.height, 12, "[disk_type] should retain the frigate template height.")
		TEST_ASSERT(length(disk.ship_plan.manifest), "[disk_type] should produce a non-empty construction manifest.")
		var/list/counts = disk.ship_plan.phase_counts()
		TEST_ASSERT(counts["[SHIPYARD_PHASE_RODS]"] > 0, "[disk_type] should contain rod operations.")
		TEST_ASSERT(counts["[SHIPYARD_PHASE_PLATING]"] > 0, "[disk_type] should contain plating operations.")
		TEST_ASSERT(counts["[SHIPYARD_PHASE_FINAL]"] > 0, "[disk_type] should contain final operations.")

	var/obj/item/ship_blueprint_disk/generic_cutter = disks[/obj/item/ship_blueprint_disk/solfed_cutter]
	var/obj/item/ship_blueprint_disk/typed_cutter = disks[/obj/item/ship_blueprint_disk/solfed_cutter/typed]
	var/obj/item/ship_blueprint_disk/generic_patrol = disks[/obj/item/ship_blueprint_disk/solfed_patrol]
	var/obj/item/ship_blueprint_disk/typed_patrol = disks[/obj/item/ship_blueprint_disk/solfed_patrol/typed]
	var/cutter_wall_count = 0
	var/found_tiny_fan = FALSE
	var/found_plasteel_barricade = FALSE
	var/found_megacell_charger = FALSE
	var/found_wall_multicell_charger = FALSE
	var/found_shuttle_chair = FALSE
	var/list/generated_families = list(
		"light" = FALSE,
		"chair" = FALSE,
		"closet" = FALSE,
		"canister" = FALSE,
		"apc" = FALSE,
		"airalarm" = FALSE,
		"terminal" = FALSE,
	)
	for(var/datum/ship_plan_op/operation as anything in generic_cutter.ship_plan.manifest)
		if(operation.target_path == /obj/structure/fans/tiny)
			found_tiny_fan = TRUE
			TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/iron], SHEET_MATERIAL_AMOUNT * 2, "Tiny fan should use its two-sheet construction cost.")
		else if(operation.target_path == /obj/structure/deployable_barricade/metal/plasteel)
			found_plasteel_barricade = TRUE
			// The barricade costs two iron sheets plus a two-sheet plasteel
			// upgrade, and the silo pays for plasteel as iron and plasma.
			TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/iron], SHEET_MATERIAL_AMOUNT * 4, "Plasteel barricade should bill its base and upgrade iron.")
			TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/plasma], SHEET_MATERIAL_AMOUNT * 2, "Plasteel barricade should bill the plasma half of its upgrade.")
			TEST_ASSERT(!operation.material_cost[/datum/material/alloy/plasteel], "Plasteel should be decomposed into silo-storable stock.")
		else if(operation.target_path == /obj/machinery/power/megacell_charger/wall)
			found_megacell_charger = TRUE
			TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/iron], SHEET_MATERIAL_AMOUNT * 7, "Megacell charger should consume seven iron sheets.")
			TEST_ASSERT_EQUAL(operation.required_parts[/datum/stock_part/capacitor], 1, "Megacell charger should require one RPED capacitor.")
		else if(ispath(operation.target_path, /obj/machinery/cell_charger_multi/wall_mounted) && operation.op_type == SHIPYARD_OP_MACHINE)
			found_wall_multicell_charger = TRUE
			TEST_ASSERT_EQUAL(operation.board_path, /obj/item/circuitboard/machine/cell_charger_multi, "Wall multi-cell charger should use the standard multi-cell charger board.")
		if(operation.op_type != SHIPYARD_OP_TURF || !ispath(operation.target_path, /turf/closed/wall))
			if(operation.op_type != SHIPYARD_OP_GENERATED)
				continue
			if(ispath(operation.target_path, /obj/machinery/light))
				generated_families["light"] = TRUE
			else if(ispath(operation.target_path, /obj/structure/chair))
				generated_families["chair"] = TRUE
				if(ispath(operation.target_path, /obj/structure/chair/comfy/shuttle))
					found_shuttle_chair = TRUE
					TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/titanium], SHEET_MATERIAL_AMOUNT * 2, "Shuttle chairs should retain their two-sheet titanium cost.")
					TEST_ASSERT(!operation.material_cost[/datum/material/iron], "Shuttle chair construction should not substitute iron for titanium.")
			else if(ispath(operation.target_path, /obj/structure/closet))
				generated_families["closet"] = TRUE
			else if(ispath(operation.target_path, /obj/machinery/portable_atmospherics/canister))
				generated_families["canister"] = TRUE
			else if(ispath(operation.target_path, /obj/machinery/power/apc))
				generated_families["apc"] = TRUE
				TEST_ASSERT(operation.material_cost[/datum/material/glass] >= SMALL_MATERIAL_AMOUNT, "APC generation should include its autolathe electronics cost.")
			else if(ispath(operation.target_path, /obj/machinery/airalarm))
				generated_families["airalarm"] = TRUE
			else if(ispath(operation.target_path, /obj/machinery/power/terminal))
				generated_families["terminal"] = TRUE
			continue
		cutter_wall_count++
		TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/titanium], SHEET_MATERIAL_AMOUNT * 2, "Cutter walls should retain their declared titanium cost.")
		TEST_ASSERT(!operation.material_cost[/datum/material/iron], "Cutter wall construction should not substitute iron for titanium.")
	var/list/missing_cutter_content = list()
	if(!cutter_wall_count)
		missing_cutter_content += "material-aware walls"
	if(!found_tiny_fan)
		missing_cutter_content += "tiny fan"
	if(!found_plasteel_barricade)
		missing_cutter_content += "plasteel barricade"
	if(!found_megacell_charger)
		missing_cutter_content += "wall megacell charger"
	if(!found_wall_multicell_charger)
		missing_cutter_content += "wall-mounted multi-cell charger"
	if(!found_shuttle_chair)
		missing_cutter_content += "material-aware shuttle chair"
	for(var/family in generated_families)
		if(!generated_families[family])
			missing_cutter_content += "[family] fixtures"
	if(length(missing_cutter_content))
		TEST_FAIL("Cutter blueprint omitted [length(missing_cutter_content)] expected type(s): [jointext(missing_cutter_content, ", ")]. Skipped entries: [jointext(generic_cutter.ship_plan.skipped_report(TRUE), "; ")]")
	var/deck_paint_count = 0
	for(var/datum/ship_plan_op/operation as anything in generic_patrol.ship_plan.manifest)
		if(operation.op_type != SHIPYARD_OP_DECAL)
			continue
		deck_paint_count++
		TEST_ASSERT(!length(operation.material_cost), "Deck paint should not be billed to the silo.")
	TEST_ASSERT(deck_paint_count, "Patrol blueprint should repaint its mapped deck markings.")
	TEST_ASSERT_EQUAL(generic_cutter.registration_port_type, /obj/docking_port/mobile/custom, "Generic Cutter disk should retain custom registration.")
	TEST_ASSERT_EQUAL(generic_patrol.registration_port_type, /obj/docking_port/mobile/custom, "Generic Patrol disk should retain custom registration.")
	TEST_ASSERT_EQUAL(typed_cutter.registration_port_type, /obj/docking_port/mobile/overmap/frigate/solfed_cutter, "Typed Cutter disk should select its frigate port.")
	TEST_ASSERT_EQUAL(typed_patrol.registration_port_type, /obj/docking_port/mobile/overmap/frigate/solfed_patrol, "Typed Patrol disk should select its frigate port.")
	TEST_ASSERT_EQUAL(typed_cutter.registration_area_type, /area/shuttle/overmap/frigate, "Typed Cutter disk should select the frigate area.")
	TEST_ASSERT_EQUAL(typed_patrol.registration_area_type, /area/shuttle/overmap/frigate, "Typed Patrol disk should select the frigate area.")
	TEST_ASSERT(!typed_cutter.registration_is_custom && !typed_patrol.registration_is_custom, "Typed disks should register as non-custom shuttles.")

/// A window sits on its grille, so the grille is framing work that has to be
/// standing before the structure pass glazes over it.
/datum/unit_test/overmap_shipyard_fabricator/window_framing

/datum/unit_test/overmap_shipyard_fabricator/window_framing/Run()
	var/datum/shipyard_route/grille_route = get_shipyard_route(/obj/structure/grille)
	var/datum/shipyard_route/window_route = get_shipyard_route(/obj/structure/window)
	TEST_ASSERT(grille_route, "Grilles should have a construction route.")
	TEST_ASSERT(window_route, "Windows should have a construction route.")
	TEST_ASSERT_EQUAL(grille_route.phase, SHIPYARD_PHASE_FRAMES, "Grilles should be laid with the rest of the framing.")
	TEST_ASSERT(grille_route.phase < window_route.phase, "Grilles should be standing before anything is glazed.")

	var/list/failures = list()
	for(var/target_type in GLOB.shipyard_routes)
		var/datum/shipyard_route/route = GLOB.shipyard_routes[target_type]
		if(route.strategy != SHIPYARD_ROUTE_EXPAND || !length(route.expansion))
			continue
		var/glazes = FALSE
		for(var/expanded in route.expansion)
			if(ispath(expanded, /obj/structure/window))
				glazes = TRUE
				break
		if(glazes && !(/obj/structure/grille in route.expansion))
			failures += "[target_type] glazes a window without framing it"
	if(length(failures))
		TEST_FAIL("Window framing found [length(failures)] issue(s):\n[jointext(failures, "\n")]")

/// Every mapped path in a fabricable blueprint must reach a documented
/// decision, so coverage gaps surface as one report instead of one per build.
/datum/unit_test/overmap_shipyard_fabricator/template_coverage

/datum/unit_test/overmap_shipyard_fabricator/template_coverage/Run()
	var/static/list/disk_types = list(
		// The fixture carries a representative of every route; the fleet blueprints
		// keep the real ships honest against route changes.
		/obj/item/ship_blueprint_disk/shipyard_validation,
		/obj/item/ship_blueprint_disk/solfed_cutter,
		/obj/item/ship_blueprint_disk/solfed_patrol,
	)
	var/list/failures = list()
	var/classified_total = 0
	for(var/disk_type in disk_types)
		var/obj/item/ship_blueprint_disk/disk = allocate(disk_type)
		disk.load_ship_plan()
		var/datum/ship_plan/template/plan = disk.ship_plan
		if(!istype(plan))
			failures += "[disk_type]: no template plan"
			continue
		classified_total += length(plan.classified_paths)
		for(var/mapped_path in plan.classified_paths)
			if(!plan.classified_paths[mapped_path])
				failures += "[disk_type]: [mapped_path] has no construction route"
		for(var/list/skipped as anything in plan.skipped_contents)
			if(ispath(skipped["path"], /obj/docking_port))
				failures += "[disk_type]: docking metadata belongs to commissioning and should not be reported at all"
			if(skipped["category"] != SHIPYARD_SKIP_UNSUPPORTED)
				continue
			failures += "[disk_type]: [skipped["path"]] is unsupported ([skipped["reason"]])"

	if(!classified_total)
		failures += "no blueprint content was classified at all"
	if(length(failures))
		TEST_FAIL("Blueprint route coverage found [length(failures)] issue(s):\n[jointext(unique_list(failures), "\n")]")

/// Generic families must price every mapped subtype, not just the ones that
/// happen to appear on the current blueprints.
/datum/unit_test/overmap_shipyard_fabricator/route_families

/datum/unit_test/overmap_shipyard_fabricator/route_families/Run()
	var/static/list/families = list(
		/obj/structure/chair,
		/obj/structure/window,
		/obj/structure/grille,
		/obj/structure/table,
		/obj/structure/rack,
		/obj/structure/cable,
		/obj/structure/closet,
	)
	var/datum/ship_plan/template/plan = new
	var/list/failures = list()
	var/priced_count = 0
	var/refused_count = 0
	for(var/family_path in families)
		for(var/obj/member_path as anything in typesof(family_path))
			if(member_path::abstract_type == member_path)
				continue
			var/datum/shipyard_route/route = get_shipyard_route(member_path)
			if(!route)
				failures += "[member_path]: no construction route"
				continue
			if(route.get_strategy(member_path) == SHIPYARD_ROUTE_SKIP)
				refused_count++
				continue
			var/list/resolved = plan.normalize_material_cost(route.resolve_materials(plan, member_path, list()))
			if(!length(resolved))
				failures += "[member_path]: no fabrication material recipe"
				continue
			if(shipyard_material_rejection(resolved))
				// Organic and non-silo composition is a valid, automatic refusal.
				refused_count++
				continue
			for(var/material_path in resolved)
				if(resolved[material_path] <= 0)
					failures += "[member_path]: non-positive [material_path] cost"
			priced_count++

	if(!priced_count)
		failures += "no family member resolved a payable cost"
	if(!refused_count)
		failures += "no family member was refused, so the blacklist path is untested"
	if(length(failures))
		TEST_FAIL("Route family coverage found [length(failures)] issue(s):\n[jointext(failures, "\n")]")
	qdel(plan)

/// Organic and non-silo stock is refused automatically; alloys the silo cannot
/// hold are broken down into the components it can.
/datum/unit_test/overmap_shipyard_fabricator/material_policy

/datum/unit_test/overmap_shipyard_fabricator/material_policy/Run()
	var/static/list/refused_materials = list(
		/datum/material/wood,
		/datum/material/bamboo,
		/datum/material/bone,
		/datum/material/cardboard,
		/datum/material/paper,
		/datum/material/meat,
		/datum/material/bronze,
		/datum/material/mythril,
	)
	var/static/list/accepted_materials = list(
		/datum/material/iron,
		/datum/material/glass,
		/datum/material/titanium,
		/datum/material/plasma,
	)
	var/datum/ship_plan/template/plan = new
	var/list/failures = list()

	for(var/material_path in refused_materials)
		var/list/normalized = plan.normalize_material_cost(list((material_path) = SHEET_MATERIAL_AMOUNT))
		if(!shipyard_material_rejection(normalized))
			failures += "[material_path] should be refused as unfabricable stock"
	for(var/material_path in accepted_materials)
		var/list/normalized = plan.normalize_material_cost(list((material_path) = SHEET_MATERIAL_AMOUNT))
		var/rejection = shipyard_material_rejection(normalized)
		if(rejection)
			failures += "[material_path] should be payable from the silo, got '[rejection]'"

	// Plasteel is not silo-stored, but its iron and plasma components are.
	var/list/plasteel_cost = plan.normalize_material_cost(list(/datum/material/alloy/plasteel = SHEET_MATERIAL_AMOUNT * 2))
	if(shipyard_material_rejection(plasteel_cost))
		failures += "plasteel should decompose into silo-storable components"
	if(plasteel_cost[/datum/material/alloy/plasteel])
		failures += "plasteel should not remain in a normalized cost"
	if(plasteel_cost[/datum/material/iron] != SHEET_MATERIAL_AMOUNT * 2)
		failures += "plasteel should contribute [SHEET_MATERIAL_AMOUNT * 2] iron, got [plasteel_cost[/datum/material/iron] || 0]"
	if(plasteel_cost[/datum/material/plasma] != SHEET_MATERIAL_AMOUNT * 2)
		failures += "plasteel should contribute [SHEET_MATERIAL_AMOUNT * 2] plasma, got [plasteel_cost[/datum/material/plasma] || 0]"

	// Composition declared on a type has to be readable, or every structure
	// priced from it silently reports as having no recipe at all.
	var/list/rack_cost = plan.declared_material_cost(/obj/structure/rack)
	if(rack_cost[/datum/material/iron] != SHEET_MATERIAL_AMOUNT)
		failures += "a rack should declare [SHEET_MATERIAL_AMOUNT] iron, got [rack_cost[/datum/material/iron] || 0]"
	var/list/wooden_rack_cost = plan.declared_material_cost(/obj/structure/rack/wooden)
	if(!shipyard_material_rejection(plan.normalize_material_cost(wooden_rack_cost)))
		failures += "a wooden rack should be refused from its own declared composition"

	// A wooden structure is refused without needing an explicit blacklist entry.
	var/list/wooden_cost = plan.apply_material_policy(
		list(/datum/material/wood = SHEET_MATERIAL_AMOUNT),
		/obj/structure/table/wood,
		0,
		0,
	)
	if(length(wooden_cost))
		failures += "wooden furniture should be refused by the automatic material policy"
	var/list/categories = plan.skipped_counts()
	if(!categories[SHIPYARD_SKIP_BLACKLISTED])
		failures += "an automatic material refusal should be reported as blacklisted"

	if(length(failures))
		TEST_FAIL("Material policy found [length(failures)] issue(s):\n[jointext(failures, "\n")]")
	qdel(plan)

/// Networks derive their cost from the item that actually builds them.
/datum/unit_test/overmap_shipyard_fabricator/network_routes

/datum/unit_test/overmap_shipyard_fabricator/network_routes/Run()
	var/static/list/pipe_fixtures = list(
		/obj/machinery/atmospherics/components/binary/pump = /obj/item/pipe/binary/pressure_pump,
		/obj/machinery/atmospherics/components/unary/vent_pump = /obj/item/pipe/directional/vent,
		/obj/machinery/atmospherics/components/unary/vent_scrubber = /obj/item/pipe/directional/scrubber,
		/obj/machinery/atmospherics/pipe/smart/simple/general/visible = /obj/item/pipe/quaternary/pipe,
	)
	// Devices with no fitting of their own are still laid by an RPD, so they
	// cost the generic fitting rather than falling through to no recipe.
	var/static/list/generic_fittings = list(
		/obj/machinery/atmospherics/components/binary/volume_pump = /obj/item/pipe/directional,
		/obj/machinery/atmospherics/components/binary/dp_vent_pump = /obj/item/pipe,
	)
	var/datum/ship_plan/template/plan = new
	var/list/failures = list()

	for(var/machinery_path in pipe_fixtures)
		var/expected_fitting = pipe_fixtures[machinery_path]
		var/resolved_fitting = get_shipyard_pipe_fitting(machinery_path)
		if(resolved_fitting != expected_fitting)
			failures += "[machinery_path]: expected fitting [expected_fitting], got [resolved_fitting || "none"]"
			continue
		var/datum/shipyard_route/route = get_shipyard_route(machinery_path)
		if(route.get_strategy(machinery_path) != SHIPYARD_ROUTE_PLACE)
			failures += "[machinery_path]: pipes should be placed directly, not frame-built"
		var/list/resolved = route.resolve_materials(plan, machinery_path, list())
		var/list/expected = shipyard_declared_material_cost(expected_fitting)
		if(!length(expected))
			failures += "[expected_fitting]: fitting declares no material composition to price from"
			continue
		for(var/material_path in expected)
			if(resolved[material_path] != expected[material_path])
				failures += "[machinery_path]: expected [expected[material_path]] [material_path], got [resolved[material_path] || 0]"

	for(var/machinery_path in generic_fittings)
		var/expected_fitting = generic_fittings[machinery_path]
		var/resolved_fitting = get_shipyard_pipe_fitting(machinery_path)
		if(resolved_fitting != expected_fitting)
			failures += "[machinery_path]: expected generic fitting [expected_fitting], got [resolved_fitting || "none"]"
			continue
		var/datum/shipyard_route/route = get_shipyard_route(machinery_path)
		var/list/resolved = route.resolve_materials(plan, machinery_path, list())
		if(resolved[/datum/material/iron] != SHEET_MATERIAL_AMOUNT)
			failures += "[machinery_path]: expected one fitting of iron, got [resolved[/datum/material/iron] || 0]"

	var/datum/shipyard_route/cable_route = get_shipyard_route(/obj/structure/cable)
	var/list/cable_cost = cable_route.resolve_materials(plan, /obj/structure/cable, list())
	var/list/coil_cost = shipyard_stack_material_cost(/obj/item/stack/cable_coil, 1)
	if(!length(coil_cost))
		failures += "cable coil metadata should describe a per-unit cost"
	for(var/material_path in coil_cost)
		if(cable_cost[material_path] != coil_cost[material_path])
			failures += "cable: expected [coil_cost[material_path]] [material_path], got [cable_cost[material_path] || 0]"

	if(length(failures))
		TEST_FAIL("Network route coverage found [length(failures)] issue(s):\n[jointext(failures, "\n")]")
	qdel(plan)

/// Frame-built machines must pair a frame with a board, bill printable board
/// components to the silo, and leave finished stock parts to the RPED.
/datum/unit_test/overmap_shipyard_fabricator/board_machines

/datum/unit_test/overmap_shipyard_fabricator/board_machines/Run()
	var/obj/item/ship_blueprint_disk/disk = allocate(/obj/item/ship_blueprint_disk/solfed_cutter)
	disk.load_ship_plan()
	var/datum/ship_plan/template/plan = disk.ship_plan
	TEST_ASSERT(istype(plan), "Board machine test requires the Cutter template plan.")

	var/list/failures = list()
	var/list/frame_coords = list()
	var/machine_count = 0
	var/decomposed_board_count = 0
	for(var/datum/ship_plan_op/operation as anything in plan.manifest)
		if(operation.op_type == SHIPYARD_OP_MACHINE_FRAME || operation.op_type == SHIPYARD_OP_COMPUTER_FRAME)
			frame_coords["[operation.target_path]@[operation.rel_x],[operation.rel_y]"] = TRUE
			continue
		if(operation.op_type != SHIPYARD_OP_MACHINE && operation.op_type != SHIPYARD_OP_COMPUTER)
			continue
		machine_count++
		if(!ispath(operation.board_path, /obj/item/circuitboard))
			failures += "[operation.target_path]: finalization has no circuit board"
		if(!frame_coords["[operation.target_path]@[operation.rel_x],[operation.rel_y]"])
			failures += "[operation.target_path]: finalization has no matching frame at ([operation.rel_x], [operation.rel_y])"
		var/list/requirements = shipyard_board_requirements(operation.board_path)
		if(length(requirements["parts"]) || length(requirements["materials"]))
			decomposed_board_count++
		for(var/part_path in requirements["parts"])
			if(!operation.required_parts[part_path])
				failures += "[operation.target_path]: board part [part_path] is not requested from the RPED"
		for(var/material_path in requirements["materials"])
			if(!operation.material_cost[material_path])
				failures += "[operation.target_path]: printable component material [material_path] is not billed to the silo"
		if(plan.required_parts[operation.board_path] < 1)
			failures += "[operation.target_path]: board [operation.board_path] is missing from the aggregate parts list"

	if(!machine_count)
		failures += "the Cutter blueprint produced no frame-built machines"
	if(!decomposed_board_count)
		failures += "no circuit board reported the components it is assembled from"
	if(length(failures))
		TEST_FAIL("Board machine coverage found [length(failures)] issue(s):\n[jointext(unique_list(failures), "\n")]")

/// Board manifests name stock parts as datums while an RPED holds items, so the
/// readout must translate between them or report everything as unavailable.
/datum/unit_test/overmap_shipyard_fabricator/rped_availability

/datum/unit_test/overmap_shipyard_fabricator/rped_availability/Run()
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(
		/obj/machinery/shipyard_fabricator,
		run_loc_floor_bottom_left,
	)
	var/obj/item/ship_blueprint_disk/disk = allocate(/obj/item/ship_blueprint_disk/solfed_cutter)
	disk.load_ship_plan()
	var/datum/ship_plan/template/plan = disk.ship_plan
	TEST_ASSERT(istype(plan), "RPED availability test requires the Cutter template plan.")

	var/list/stock_part_requirements = list()
	for(var/requirement in plan.required_parts)
		if(ispath(requirement, /datum/stock_part))
			stock_part_requirements += requirement
	TEST_ASSERT(length(stock_part_requirements), "Cutter blueprint should request stock parts from an RPED.")

	var/obj/item/storage/part_replacer/replacer = allocate(/obj/item/storage/part_replacer/bluespace)
	for(var/requirement in stock_part_requirements)
		var/obj/item/item_path = shipyard_part_item_type(requirement)
		TEST_ASSERT(ispath(item_path, /obj/item), "[requirement] should name a physical stock part item.")
		var/obj/item/part = allocate(item_path)
		part.forceMove(replacer)
	fabricator.docked_rped = replacer

	var/list/summary = fabricator.part_summary(plan)
	TEST_ASSERT_EQUAL(length(summary), length(plan.required_parts), "Every requirement should report a row.")

	var/list/failures = list()
	var/row_index = 0
	for(var/requirement in plan.required_parts)
		row_index++
		if(!ispath(requirement, /datum/stock_part))
			continue
		var/list/row = summary[row_index]
		var/obj/item/item_path = shipyard_part_item_type(requirement)
		if(row["available"] < 1)
			failures += "[requirement] reads as unavailable while the RPED holds one"
		if(row["name"] != initial(item_path.name))
			failures += "[requirement] is labelled '[row["name"]]' rather than '[initial(item_path.name)]'"
	if(length(failures))
		TEST_FAIL("RPED availability found [length(failures)] issue(s):\n[jointext(failures, "\n")]")

	// A better part satisfies a requirement for a plainer one, so the upgraded
	// tiers a bluespace RPED is stocked with have to count toward it.
	TEST_ASSERT(plan.required_parts[/datum/stock_part/capacitor], "Cutter blueprint should request baseline capacitors.")
	var/capacitor_row = 0
	row_index = 0
	for(var/requirement in plan.required_parts)
		row_index++
		if(requirement == /datum/stock_part/capacitor)
			capacitor_row = row_index
			break
	var/baseline = summary[capacitor_row]["available"]
	var/obj/item/upgraded = allocate(/obj/item/stock_parts/capacitor/quadratic)
	upgraded.forceMove(replacer)
	summary = fabricator.part_summary(plan)
	TEST_ASSERT_EQUAL(summary[capacitor_row]["available"], baseline + 1, "A quadratic capacitor should count toward a baseline capacitor requirement.")

/datum/unit_test/overmap_shipyard_fabricator/generated_objects

/datum/unit_test/overmap_shipyard_fabricator/generated_objects/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, origin)
	zone.zone_width = 4
	zone.zone_height = 2
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, get_step(origin, WEST))
	fabricator.claimed_zone = WEAKREF(zone)

	var/datum/ship_plan_op/closet_operation = new(
		SHIPYARD_PHASE_FINAL,
		0,
		0,
		SHIPYARD_OP_GENERATED,
		/obj/structure/closet/emcloset/wall,
	)
	TEST_ASSERT_EQUAL(closet_operation.execute_generated(origin), TRUE, "Closet shell should generate.")
	var/obj/structure/closet/generated_closet = locate() in origin
	TEST_ASSERT(generated_closet.contents_initialized, "Generated closet should suppress lazy contents.")
	TEST_ASSERT(!length(generated_closet.contents), "Generated closet should be empty before entering the world.")

	var/turf/canister_turf = get_step(origin, EAST)
	var/datum/ship_plan_op/canister_operation = new(
		SHIPYARD_PHASE_FINAL,
		1,
		0,
		SHIPYARD_OP_GENERATED,
		/obj/machinery/portable_atmospherics/canister/air,
	)
	TEST_ASSERT_EQUAL(canister_operation.execute_generated(canister_turf), TRUE, "Canister shell should generate.")
	var/obj/machinery/portable_atmospherics/canister/generated_canister = locate() in canister_turf
	TEST_ASSERT_EQUAL(generated_canister.air_contents.total_moles(), 0, "Generated canister should be empty before entering the world.")
	TEST_ASSERT(!generated_canister.internal_cell, "Generated canister should omit its mapload-only cell.")

	var/turf/light_turf = get_step(origin, NORTH)
	var/datum/ship_plan_op/light_operation = new(
		SHIPYARD_PHASE_FINAL,
		0,
		1,
		SHIPYARD_OP_GENERATED,
		/obj/machinery/light/floor/transport,
	)
	TEST_ASSERT_EQUAL(light_operation.execute_generated(light_turf), TRUE, "Light fixture should generate.")
	var/obj/machinery/light/generated_light = locate() in light_turf
	TEST_ASSERT_EQUAL(generated_light.status, LIGHT_OK, "Generated light fixture should be operational.")

	var/turf/chair_turf = get_step(light_turf, EAST)
	var/datum/ship_plan_op/chair_operation = new(
		SHIPYARD_PHASE_FINAL,
		1,
		1,
		SHIPYARD_OP_GENERATED,
		/obj/structure/chair/comfy/shuttle/tactical,
		null,
		list("dir" = EAST),
	)
	TEST_ASSERT_EQUAL(chair_operation.execute_generated(chair_turf), TRUE, "Chair should generate.")
	var/obj/structure/chair/generated_chair = locate() in chair_turf
	TEST_ASSERT_EQUAL(generated_chair.dir, EAST, "Generated chair should preserve its mapped direction.")

	var/obj/machinery/power/apc/generated_apc = new /obj/machinery/power/apc(null)
	TEST_ASSERT(generated_apc.shipyard_prepare(list("cell_type" = /obj/item/stock_parts/power_store/battery/bluespace, "start_charge" = 50)), "APC should prepare in nullspace.")
	TEST_ASSERT(istype(generated_apc.cell, /obj/item/stock_parts/power_store/battery/bluespace), "Prepared APC should use its DMM-selected cell type.")
	TEST_ASSERT_EQUAL(generated_apc.cell.charge, generated_apc.cell.maxcharge * 0.5, "Prepared APC should honor its mapped starting charge.")
	qdel(generated_apc)

	var/paint_overlays = length(origin.overlays)
	var/datum/ship_plan_op/paint_operation = new(
		SHIPYARD_PHASE_STRUCTURE,
		0,
		0,
		SHIPYARD_OP_DECAL,
		/obj/effect/turf_decal/stripes/line,
		null,
		list("dir" = WEST),
	)
	TEST_ASSERT_EQUAL(paint_operation.execute_decal(origin), TRUE, "Deck markings should paint onto a floor.")
	TEST_ASSERT(!(locate(/obj/effect/turf_decal) in origin), "Applied paint should not leave an effect behind.")
	TEST_ASSERT(length(origin.overlays) > paint_overlays, "Applied paint should add a decal to the turf.")
	TEST_ASSERT(!GLOB.use_preloader, "Painting should not leave the map preloader armed.")

	var/turf/airlock_turf = get_step(canister_turf, EAST)
	var/list/helper_specs = list(list(
		"path" = /obj/effect/mapping_helpers/airlock/access/any/engineering/engine_equipment,
		"vars" = list(),
	))
	var/datum/ship_plan_op/airlock_operation = new(
		SHIPYARD_PHASE_FINAL,
		2,
		0,
		SHIPYARD_OP_GENERATED,
		/obj/machinery/door/airlock/engineering/glass,
		null,
		null,
		null,
		helper_specs,
	)
	TEST_ASSERT_EQUAL(airlock_operation.execute_generated(airlock_turf), TRUE, "Airlock should generate with its helper.")
	var/obj/machinery/door/airlock/generated_airlock = locate() in airlock_turf
	TEST_ASSERT(ACCESS_ENGINE_EQUIP in generated_airlock.req_one_access, "Generated airlock should inherit access from the real mapping-helper subtype.")

/datum/unit_test/overmap_shipyard_fabricator/typed_registration
	var/datum/turf_reservation/typed_reservation
	var/obj/docking_port/mobile/registered_port

/datum/unit_test/overmap_shipyard_fabricator/typed_registration/Destroy()
	if(!QDELETED(registered_port))
		if(registered_port.current_ship)
			var/obj/structure/overmap/ship/simulated/ship = registered_port.current_ship
			ship.shuttle = null
			registered_port.current_ship = null
			qdel(ship)
		qdel(registered_port, force = TRUE)
	registered_port = null
	QDEL_NULL(typed_reservation)
	return ..()

/datum/unit_test/overmap_shipyard_fabricator/typed_registration/Run()
	typed_reservation = SSmapping.request_turf_block_reservation(
		3,
		3,
		1,
		reservation_type = /datum/turf_reservation/transit,
	)
	TEST_ASSERT(typed_reservation, "Typed registration test should reserve an isolated turf block.")
	var/turf/origin = typed_reservation.bottom_left_turfs[1]
	TEST_ASSERT(origin, "Typed registration reservation should provide an origin turf.")
	origin.ChangeTurf(/turf/open/floor/plating)
	origin = get_turf(origin)
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, origin)
	zone.zone_width = 1
	zone.zone_height = 1
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, get_step(origin, EAST))
	var/obj/item/ship_blueprint_disk/disk = allocate(/obj/item/ship_blueprint_disk/solfed_cutter/typed)
	QDEL_NULL(disk.ship_plan)
	var/datum/ship_plan/plan = new
	plan.name = "Typed Registration Test"
	plan.width = 1
	plan.height = 1
	plan.manifest = list(new /datum/ship_plan_op(
		SHIPYARD_PHASE_PLATING,
		0,
		0,
		SHIPYARD_OP_PLATING,
		/turf/open/floor/plating,
	))
	disk.ship_plan = plan
	disk.forceMove(fabricator)
	fabricator.blueprint_disk = disk
	fabricator.claimed_zone = WEAKREF(zone)
	TEST_ASSERT(fabricator.complete_phase(SHIPYARD_PHASE_PLATING), "Typed disk should register its plated hull.")
	registered_port = fabricator.built_shuttle_ref?.resolve()
	TEST_ASSERT(istype(registered_port, /obj/docking_port/mobile/overmap/frigate/solfed_cutter), "Typed Cutter disk should create the Cutter mobile-port subtype.")
	TEST_ASSERT(istype(get_area(origin), /area/shuttle/overmap/frigate), "Typed Cutter disk should create a frigate shuttle area.")

/datum/unit_test/overmap_shipyard_fabricator/part_scaling

/datum/unit_test/overmap_shipyard_fabricator/part_scaling/Run()
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, run_loc_floor_bottom_left)
	fabricator.component_parts = list(
		GLOB.stock_part_datums[/datum/stock_part/matter_bin],
		GLOB.stock_part_datums[/datum/stock_part/micro_laser],
		GLOB.stock_part_datums[/datum/stock_part/servo],
		GLOB.stock_part_datums[/datum/stock_part/scanning_module],
	)
	fabricator.RefreshParts()
	var/tier_one_range = fabricator.max_print_range
	var/tier_one_delay = fabricator.fabrication_delay
	TEST_ASSERT_EQUAL(fabricator.material_cost_multiplier, 1.5, "Tier-one matter bins should cost 150% of hand construction.")

	fabricator.component_parts = list(
		GLOB.stock_part_datums[/datum/stock_part/matter_bin/tier4],
		GLOB.stock_part_datums[/datum/stock_part/micro_laser/tier4],
		GLOB.stock_part_datums[/datum/stock_part/servo/tier4],
		GLOB.stock_part_datums[/datum/stock_part/scanning_module/tier4],
	)
	fabricator.RefreshParts()
	TEST_ASSERT_EQUAL(fabricator.material_cost_multiplier, 1, "Tier-four matter bins should reach hand-construction material parity.")
	TEST_ASSERT(fabricator.fabrication_delay < tier_one_delay, "Tier-four lasers and servos should place faster than tier one.")
	TEST_ASSERT(fabricator.max_print_range > tier_one_range, "Tier-four scanners should print farther than tier one.")
	TEST_ASSERT_EQUAL(fabricator.max_print_range, CONFIG_GET(number/max_overmap_landing_zone_dimension), "Tier-four scanner range should equal the maximum landing-zone dimension.")

/datum/unit_test/overmap_shipyard_fabricator/paired_frames

/datum/unit_test/overmap_shipyard_fabricator/paired_frames/Run()
	var/turf/west = run_loc_floor_bottom_left
	var/turf/east = get_step(west, EAST)
	TEST_ASSERT(east, "Paired-frame test requires an eastern tile.")
	var/obj/machinery/shipyard_fabricator_frame_half/left = allocate(/obj/machinery/shipyard_fabricator_frame_half, west)
	var/obj/machinery/shipyard_fabricator_frame_half/right = allocate(/obj/machinery/shipyard_fabricator_frame_half, east)
	TEST_ASSERT(left.try_complete_pair(), "Two adjacent anchored assembly halves should complete the fabricator.")
	var/obj/machinery/shipyard_fabricator/fabricator = locate() in west
	TEST_ASSERT(fabricator, "Paired frames should create the full fabricator on the western turf.")
	TEST_ASSERT_EQUAL(fabricator.bound_width, 64, "Completed shipyard fabricator should occupy two tiles.")
	TEST_ASSERT(QDELETED(left) || left != fabricator, "Assembly half should be consumed.")
	TEST_ASSERT(QDELETED(right) || right != fabricator, "Partner assembly half should be consumed.")

/datum/unit_test/overmap_shipyard_fabricator/paired_deconstruct

/datum/unit_test/overmap_shipyard_fabricator/paired_deconstruct/Run()
	var/turf/west = run_loc_floor_bottom_left
	var/turf/east = get_step(west, EAST)
	TEST_ASSERT(east, "Paired-deconstruct test requires an eastern tile.")
	var/obj/machinery/shipyard_fabricator_frame_half/left = allocate(/obj/machinery/shipyard_fabricator_frame_half, west)
	allocate(/obj/machinery/shipyard_fabricator_frame_half, east)
	TEST_ASSERT(left.try_complete_pair(), "Two adjacent anchored assembly halves should complete the fabricator.")
	var/obj/machinery/shipyard_fabricator/fabricator = locate() in west
	TEST_ASSERT(fabricator, "Paired frames should create the full fabricator.")

	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent, get_step(west, SOUTH))
	var/obj/item/crowbar/lever = allocate(/obj/item/crowbar)
	TEST_ASSERT_EQUAL(fabricator.crowbar_act(user, lever), ITEM_INTERACT_BLOCKING, "A sealed fabricator should refuse to come apart.")
	TEST_ASSERT(!QDELETED(fabricator), "A sealed fabricator should survive a crowbar.")

	fabricator.set_panel_open(TRUE)
	TEST_ASSERT_EQUAL(fabricator.crowbar_act(user, lever), ITEM_INTERACT_SUCCESS, "An open fabricator should come apart under a crowbar.")
	TEST_ASSERT(QDELETED(fabricator), "Deconstruction should consume the paired machine.")
	var/obj/structure/frame/machine/west_frame = locate() in west
	var/obj/structure/frame/machine/east_frame = locate() in east
	TEST_ASSERT(west_frame, "Deconstruction should leave a frame on the machine's own tile.")
	TEST_ASSERT(east_frame, "Deconstruction should leave a frame on the tile the machine's second half occupied.")
	TEST_ASSERT_EQUAL(east_frame.state, FRAME_STATE_WIRED, "The second frame should come back wired like the first.")
	TEST_ASSERT(east_frame.anchored, "The second frame should come back anchored like the first.")

/datum/unit_test/overmap_shipyard_fabricator/rped_docking

/datum/unit_test/overmap_shipyard_fabricator/rped_docking/Run()
	var/turf/west = run_loc_floor_bottom_left
	var/turf/user_turf = get_step(west, SOUTH)
	TEST_ASSERT(user_turf, "RPED docking test requires an adjacent turf.")
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, west)
	fabricator.component_parts = list(GLOB.stock_part_datums[/datum/stock_part/matter_bin])
	var/mob/living/carbon/human/user = allocate(/mob/living/carbon/human/consistent, user_turf)
	var/obj/item/storage/part_replacer/replacer = allocate(/obj/item/storage/part_replacer)
	user.put_in_hands(replacer, forced = TRUE)

	var/list/context = list()
	TEST_ASSERT_EQUAL(fabricator.add_context(fabricator, context, replacer, user), CONTEXTUAL_SCREENTIP_SET, "Holding an RPED should provide shipyard interaction context.")
	TEST_ASSERT_EQUAL(context[SCREENTIP_CONTEXT_LMB], "Dock RPED", "Shipyard hover text should advertise RPED docking.")
	TEST_ASSERT_EQUAL(replacer.interact_with_atom(fabricator, user, list()), ITEM_INTERACT_SUCCESS, "The RPED's machinery interaction should dock instead of exchanging fabricator parts.")
	TEST_ASSERT_EQUAL(fabricator.docked_rped, replacer, "The clicked RPED should become the shipyard parts inventory.")
	TEST_ASSERT(replacer.loc == fabricator, "A docked RPED should be transferred into the fabricator.")
	var/found_rped_overlay = FALSE
	for(var/mutable_appearance/overlay as anything in fabricator.update_overlays())
		if(overlay.icon_state == "shuttle_printer-rped")
			found_rped_overlay = TRUE
			break
	TEST_ASSERT(found_rped_overlay, "A docked RPED should appear in the printer's right-hand dock.")

	replacer.forceMove(user_turf)
	var/obj/item/storage/part_replacer/bluespace/bluespace_replacer = allocate(/obj/item/storage/part_replacer/bluespace, fabricator)
	fabricator.docked_rped = bluespace_replacer
	var/found_bluespace_overlay = FALSE
	for(var/mutable_appearance/overlay as anything in fabricator.update_overlays())
		if(overlay.icon_state == "shuttle_printer-rped_bluespace")
			found_bluespace_overlay = TRUE
			break
	TEST_ASSERT(found_bluespace_overlay, "A docked bluespace RPED should use its matching dock overlay.")

/datum/unit_test/overmap_shipyard_fabricator/phase_projections

/datum/unit_test/overmap_shipyard_fabricator/phase_projections/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/east = get_step(origin, EAST)
	var/turf/north = get_step(origin, NORTH)
	TEST_ASSERT(east && north, "Phase projection test requires adjacent fixture turfs.")
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, origin)
	zone.zone_width = 2
	zone.zone_height = 2
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, get_step(origin, WEST))
	var/obj/item/ship_blueprint_disk/disk = allocate(/obj/item/ship_blueprint_disk)
	var/datum/ship_plan/plan = new
	plan.width = 2
	plan.height = 2
	var/datum/ship_plan_op/first_rods = new(
		SHIPYARD_PHASE_RODS,
		0,
		0,
		SHIPYARD_OP_RODS,
		/turf/open/floor/plating,
	)
	var/datum/ship_plan_op/second_rods = new(
		SHIPYARD_PHASE_RODS,
		1,
		0,
		SHIPYARD_OP_RODS,
		/turf/open/floor/plating,
	)
	var/datum/ship_plan_op/plating = new(
		SHIPYARD_PHASE_PLATING,
		0,
		0,
		SHIPYARD_OP_PLATING,
		/turf/open/floor/plating,
	)
	plan.manifest = list(first_rods, second_rods, plating)
	disk.ship_plan = plan
	disk.forceMove(fabricator)
	fabricator.blueprint_disk = disk
	fabricator.claimed_zone = WEAKREF(zone)

	fabricator.project_phase(SHIPYARD_PHASE_RODS)
	TEST_ASSERT_EQUAL(length(fabricator.phase_projections), 2, "Rod phase should project only its two pending operations.")
	var/obj/effect/overlay/shipyard_projection/first_projection = fabricator.phase_projections[REF(first_rods)]
	TEST_ASSERT(first_projection, "Rod operation should have a keyed projection.")
	TEST_ASSERT(!first_projection.density, "Shipyard projections should not block movement.")
	TEST_ASSERT_EQUAL(first_projection.mouse_opacity, MOUSE_OPACITY_TRANSPARENT, "Shipyard projections should not intercept clicks.")
	TEST_ASSERT(first_projection.flags_1 & HOLOGRAM_1, "Shipyard projections should be marked as holograms.")
	TEST_ASSERT(length(first_projection.filters), "Shipyard projections should carry the holopad-style hologram filters.")

	fabricator.pause_build("Projection test pause.")
	TEST_ASSERT_EQUAL(length(fabricator.phase_projections), 2, "Pausing should retain current-phase projections.")
	fabricator.clear_operation_projection(first_rods)
	TEST_ASSERT_EQUAL(length(fabricator.phase_projections), 1, "A successful operation should remove only its own projection.")
	fabricator.fault_build(second_rods, "Projection test fault.")
	TEST_ASSERT_EQUAL(length(fabricator.phase_projections), 1, "Faulting should retain remaining current-phase projections.")

	fabricator.project_phase(SHIPYARD_PHASE_PLATING)
	TEST_ASSERT_EQUAL(length(fabricator.phase_projections), 1, "Changing phase should replace the previous projection set.")
	TEST_ASSERT(fabricator.phase_projections[REF(plating)], "Plating phase should project its pending operation.")
	fabricator.abort_build()
	TEST_ASSERT(!length(fabricator.phase_projections), "Aborting should clear all phase projections.")

	fabricator.claimed_zone = WEAKREF(zone)
	fabricator.rotated_plan = TRUE
	fabricator.project_phase(SHIPYARD_PHASE_RODS)
	first_projection = fabricator.phase_projections[REF(first_rods)]
	TEST_ASSERT_EQUAL(first_projection.loc, fabricator.get_operation_turf(first_rods, zone), "Rotated projections should use the fabricator's operation-turf transform.")
	fabricator.finish_build()
	TEST_ASSERT(!length(fabricator.phase_projections), "Completing construction should clear all phase projections.")

/datum/unit_test/overmap_shipyard_fabricator/printer_visuals

/datum/unit_test/overmap_shipyard_fabricator/printer_visuals/Run()
	var/turf/west = run_loc_floor_bottom_left
	var/turf/dish_turf = get_step(west, EAST)
	var/turf/target = get_step(dish_turf, NORTH)
	TEST_ASSERT(dish_turf && target, "Printer visual test requires east and northeast fixture turfs.")
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, west)

	TEST_ASSERT(!fabricator.printer_deployed, "Fresh printer should be retracted.")
	TEST_ASSERT_EQUAL(fabricator.icon_state, "shuttle_printer", "Retracted printer should use its inactive composite icon.")

	fabricator.deploy_printer()
	TEST_ASSERT(fabricator.printer_deployed, "Starting the printer should deploy its dish.")
	TEST_ASSERT_EQUAL(fabricator.icon_state, "shuttle_printer-base", "Deployed printer should expose its base icon.")
	TEST_ASSERT_EQUAL(fabricator.dish_icon_state, "shuttle_printer-dish_idle", "Deployed dish should settle into its idle state.")

	fabricator.state = "building"
	fabricator.play_placement_effect(target)
	TEST_ASSERT_EQUAL(fabricator.dish_direction, NORTH, "Dish should aim from the eastern machine tile toward the operation turf.")
	TEST_ASSERT_EQUAL(fabricator.dish_icon_state, "shuttle_printer-dish_active", "Placement should activate the directional dish.")

	fabricator.pause_build("Visual state test.")
	TEST_ASSERT(fabricator.printer_deployed, "Paused printer should remain deployed.")
	TEST_ASSERT_EQUAL(fabricator.dish_icon_state, "shuttle_printer-dish_idle", "Paused printer should return its dish to idle.")

	fabricator.fault_build(null, "Visual state test fault.")
	TEST_ASSERT(fabricator.printer_deployed, "Faulted printer should remain deployed.")
	TEST_ASSERT_EQUAL(fabricator.dish_icon_state, "shuttle_printer-dish_error", "Faulted printer should show the dish error state.")

	fabricator.abort_build()
	TEST_ASSERT(!fabricator.printer_deployed, "Aborting should retract the printer.")
	TEST_ASSERT_EQUAL(fabricator.icon_state, "shuttle_printer", "Aborting should restore the inactive composite icon.")

	fabricator.deploy_printer()
	fabricator.finish_build()
	TEST_ASSERT(!fabricator.printer_deployed, "Completing a build should retract the printer.")
	TEST_ASSERT_EQUAL(fabricator.icon_state, "shuttle_printer", "Completing a build should restore the inactive composite icon.")

/datum/unit_test/overmap_shipyard_fabricator/console_overlays

/datum/unit_test/overmap_shipyard_fabricator/console_overlays/Run()
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(
		/obj/machinery/shipyard_fabricator,
		run_loc_floor_bottom_left,
	)
	fabricator.set_machine_stat(fabricator.machine_stat & ~(NOPOWER | BROKEN))

	var/list/states = overlay_states(fabricator)
	TEST_ASSERT(("shuttle_printer-screen_idle" in states), "A powered idle fabricator should light its console screen.")
	TEST_ASSERT(!("shuttle_printer-maintenance_panel" in states), "A closed machine should not show its maintenance panel.")
	TEST_ASSERT(!("shuttle_printer-computer_disk" in states), "An empty disk slot should not show a disk.")
	TEST_ASSERT(!("shuttle_printer-rped_slot_light" in states), "An empty RPED dock should not light its slot.")

	fabricator.set_build_state("building")
	states = overlay_states(fabricator)
	TEST_ASSERT(("shuttle_printer-screen_working" in states), "A running build should show the working console screen.")

	fabricator.fault_build(null, "Console overlay test fault.")
	states = overlay_states(fabricator)
	TEST_ASSERT(("shuttle_printer-screen_error" in states), "A faulted build should show the error console screen.")
	fabricator.abort_build()

	var/obj/item/ship_blueprint_disk/disk = allocate(/obj/item/ship_blueprint_disk)
	disk.forceMove(fabricator)
	fabricator.blueprint_disk = disk
	var/obj/item/storage/part_replacer/replacer = allocate(/obj/item/storage/part_replacer)
	replacer.forceMove(fabricator)
	fabricator.docked_rped = replacer
	fabricator.set_panel_open(TRUE)
	states = overlay_states(fabricator)
	TEST_ASSERT(("shuttle_printer-computer_disk" in states), "A loaded blueprint should show in the disk slot.")
	TEST_ASSERT(("shuttle_printer-rped" in states), "A docked RPED should show on the machine.")
	TEST_ASSERT(("shuttle_printer-rped_slot_light" in states), "A docked RPED should light its slot.")
	TEST_ASSERT(("shuttle_printer-maintenance_panel" in states), "An open hatch should show the maintenance panel.")

	fabricator.set_machine_stat(fabricator.machine_stat | NOPOWER)
	states = overlay_states(fabricator)
	TEST_ASSERT(!("shuttle_printer-screen_idle" in states), "An unpowered fabricator should have a dark screen.")
	TEST_ASSERT(!("shuttle_printer-rped_slot_light" in states), "An unpowered fabricator should have a dark slot light.")
	TEST_ASSERT(("shuttle_printer-rped" in states), "A docked RPED should stay visible without power.")
	TEST_ASSERT(("shuttle_printer-maintenance_panel" in states), "An open hatch should stay visible without power.")

/datum/unit_test/overmap_shipyard_fabricator/phase_primitives

/datum/unit_test/overmap_shipyard_fabricator/phase_primitives/Run()
	var/turf/open/floor/origin = run_loc_floor_bottom_left
	// Landing pads are usually bare plating already, and rods leave the turf's
	// own type alone, so hull completion cannot be judged by turf type.
	origin = origin.ChangeTurf(/turf/open/floor/plating)
	TEST_ASSERT(isplatingturf(origin), "Phase fixture requires a bare plating pad.")
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, origin)
	zone.zone_width = 1
	zone.zone_height = 1
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, get_step(origin, WEST))
	fabricator.claimed_zone = WEAKREF(zone)

	var/datum/ship_plan_op/rods = new /datum/ship_plan_op(
		SHIPYARD_PHASE_RODS,
		0,
		0,
		SHIPYARD_OP_RODS,
		/turf/open/floor/plating,
		list(),
	)
	TEST_ASSERT_EQUAL(rods.execute(fabricator), TRUE, "Rod phase should replay shuttle frame rod construction.")
	TEST_ASSERT(rods.satisfied(get_turf(origin)), "Rod operation postcondition should pass.")

	var/datum/ship_plan_op/plating = new /datum/ship_plan_op(
		SHIPYARD_PHASE_PLATING,
		0,
		0,
		SHIPYARD_OP_PLATING,
		/turf/open/floor/plating,
		list(),
	)
	TEST_ASSERT(!plating.satisfied(get_turf(origin)), "Exposed frame rods on a plating pad should still owe a hull layer.")
	TEST_ASSERT_EQUAL(plating.execute(fabricator), TRUE, "Plating phase should replay shuttle frame tiling.")
	TEST_ASSERT(plating.satisfied(get_turf(origin)), "Plating operation postcondition should pass.")
	TEST_ASSERT(rods.satisfied(get_turf(origin)), "A plated tile should keep counting the rod stage as done so resumes do not rebill it.")
	qdel(rods)
	qdel(plating)

/datum/unit_test/overmap_shipyard_fabricator/resume_revalidation

/datum/unit_test/overmap_shipyard_fabricator/resume_revalidation/Run()
	var/turf/origin = run_loc_floor_bottom_left
	// The fabricator is two tiles wide, so the zone sits clear of its footprint.
	var/turf/zone_corner = locate(origin.x, origin.y + 2, origin.z)
	TEST_ASSERT(isfloorturf(zone_corner), "Revalidation test requires floor two tiles north of the fixture corner.")
	var/turf/obstructed = get_step(zone_corner, NORTH)
	TEST_ASSERT(isfloorturf(obstructed), "Revalidation test requires a two-by-two fixture block.")
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, zone_corner)
	zone.zone_width = 2
	zone.zone_height = 2
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, origin)
	var/obj/item/ship_blueprint_disk/disk = allocate(/obj/item/ship_blueprint_disk)
	var/datum/ship_plan/plan = new
	plan.width = 2
	plan.height = 2
	var/list/manifest = list()
	for(var/list/coordinate in list(list(0, 0), list(1, 0), list(0, 1), list(1, 1)))
		manifest += new /datum/ship_plan_op(
			SHIPYARD_PHASE_RODS,
			coordinate[1],
			coordinate[2],
			SHIPYARD_OP_RODS,
			/turf/open/floor/plating,
			list(),
		)
	plan.manifest = manifest
	disk.ship_plan = plan
	disk.forceMove(fabricator)
	fabricator.blueprint_disk = disk
	fabricator.claimed_zone = WEAKREF(zone)

	// Stand in for an aborted build: the first two tiles were already laid.
	for(var/index in 1 to 2)
		var/datum/ship_plan_op/placed = plan.manifest[index]
		TEST_ASSERT_EQUAL(placed.execute(fabricator), TRUE, "Fixture rod placement [index] should succeed.")
	var/obj/structure/railing/obstruction = allocate(/obj/structure/railing, obstructed)

	fabricator.state = "building"
	fabricator.machine_stat &= ~(NOPOWER | BROKEN)
	fabricator.next_operation_at = 0
	var/tick_started = world.time
	fabricator.process(1)

	TEST_ASSERT_EQUAL(fabricator.operation_index, 3, "Both standing tiles should be confirmed in a single tick.")
	TEST_ASSERT(fabricator.next_operation_at <= tick_started, "Confirming standing work should not charge placement time.")
	TEST_ASSERT_EQUAL(fabricator.state, "fault", "An obstructed tile should fault the build.")
	TEST_ASSERT(findtext(fabricator.paused_reason, "railing"), "The fault should name the obstruction, got '[fabricator.paused_reason]'.")
	TEST_ASSERT_EQUAL(length(fabricator.faults), 1, "The obstruction should be listed as a located fault.")
	var/obj/effect/overlay/shipyard_projection/fault/marker = fabricator.fault_marker
	TEST_ASSERT(marker, "Faulting should leave a marker on the offending tile.")
	TEST_ASSERT_EQUAL(marker.loc, obstructed, "The fault marker should sit on the obstructed tile.")
	TEST_ASSERT_EQUAL(marker.holo_color, COLOR_RED, "The fault marker should be a red hologram.")
	TEST_ASSERT(length(marker.filters), "The fault marker should carry the hologram filters.")

	qdel(obstruction)
	fabricator.state = "building"
	fabricator.next_operation_at = 0
	tick_started = world.time
	fabricator.process(1)
	TEST_ASSERT_EQUAL(fabricator.operation_index, 4, "Clearing the obstruction should let the tile be placed.")
	TEST_ASSERT(fabricator.next_operation_at > tick_started, "A real placement should charge placement time.")
	TEST_ASSERT(!length(fabricator.faults), "Working past a fault should drop it from the report.")

	fabricator.abort_build()
	TEST_ASSERT(!fabricator.fault_marker, "Aborting should clear the fault marker.")

/// A hull becomes a registered shuttle the moment its plating is finished, so
/// every later phase runs with a docking port sitting in the landing zone. An
/// interruption there must not strand the build behind its own occupancy check.
/datum/unit_test/overmap_shipyard_fabricator/resume_past_registration

/datum/unit_test/overmap_shipyard_fabricator/resume_past_registration/Run()
	var/turf/origin = run_loc_floor_bottom_left
	var/turf/zone_corner = locate(origin.x, origin.y + 2, origin.z)
	TEST_ASSERT(isfloorturf(zone_corner), "Occupancy test requires floor two tiles north of the fixture corner.")
	var/obj/effect/landmark/overmap_landing_zone/zone = allocate(/obj/effect/landmark/overmap_landing_zone, zone_corner)
	zone.zone_width = 2
	zone.zone_height = 2
	var/obj/machinery/shipyard_fabricator/fabricator = allocate(/obj/machinery/shipyard_fabricator, origin)
	// Stands in for the hull the plating phase registers. Dimensions are set
	// after creation because the port only reads them when asked for its bounds,
	// and registration is what puts a port on the list the zone searches.
	var/obj/docking_port/mobile/hull = allocate(/obj/docking_port/mobile, zone_corner)
	hull.width = 2
	hull.height = 2
	hull.register()
	TEST_ASSERT_EQUAL(zone.get_occupant(), hull, "The fixture hull should occupy the zone.")

	fabricator.built_shuttle_ref = WEAKREF(hull)
	fabricator.state = "paused"
	TEST_ASSERT(!fabricator.blocking_occupant(zone), "A paused build should not be blocked by the hull it registered itself.")

	fabricator.state = "fault"
	TEST_ASSERT(!fabricator.blocking_occupant(zone), "A faulted build should not be blocked by its own hull either.")

	fabricator.state = "complete"
	TEST_ASSERT_EQUAL(fabricator.blocking_occupant(zone), hull, "A finished ship still parked on the pad should block the next print.")

	fabricator.built_shuttle_ref = null
	fabricator.state = "paused"
	TEST_ASSERT_EQUAL(fabricator.blocking_occupant(zone), hull, "A ship the fabricator does not own should block a resume.")

