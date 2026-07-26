// MODULE ID: OVERMAP
// Shipyard manifest, paired-frame construction, part scaling, and phase primitives.

/datum/unit_test/overmap_shipyard_fabricator
	abstract_type = /datum/unit_test/overmap_shipyard_fabricator
	priority = TEST_LONGER

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
	var/found_metal_barricade = FALSE
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
		else if(operation.target_path == /obj/structure/deployable_barricade/metal)
			found_metal_barricade = TRUE
			TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/iron], SHEET_MATERIAL_AMOUNT * 2, "Metal barricade should use its print cost.")
		else if(operation.target_path == /obj/structure/deployable_barricade/metal/plasteel)
			found_plasteel_barricade = TRUE
			TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/iron], SHEET_MATERIAL_AMOUNT * 2, "Plasteel barricade should retain the base print cost.")
			TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/alloy/plasteel], SHEET_MATERIAL_AMOUNT * 2, "Plasteel barricade should add its upgrade cost.")
		else if(operation.target_path == /obj/machinery/power/megacell_charger/wall)
			found_megacell_charger = TRUE
			TEST_ASSERT_EQUAL(operation.material_cost[/datum/material/iron], SHEET_MATERIAL_AMOUNT * 7, "Megacell charger should consume seven iron sheets.")
			TEST_ASSERT_EQUAL(operation.required_parts[/datum/stock_part/capacitor], 1, "Megacell charger should require one RPED capacitor.")
		else if(operation.target_path == /obj/machinery/cell_charger_multi/wall_mounted && operation.op_type == SHIPYARD_OP_MACHINE)
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
	TEST_ASSERT(cutter_wall_count, "Cutter blueprint should contain material-aware wall operations.")
	TEST_ASSERT(found_tiny_fan, "Cutter blueprint should generate its tiny fan.")
	TEST_ASSERT(found_metal_barricade && found_plasteel_barricade, "Cutter blueprint should generate both deployable barricade types.")
	TEST_ASSERT(found_megacell_charger, "Cutter blueprint should generate its wall megacell charger.")
	TEST_ASSERT(found_wall_multicell_charger, "Cutter blueprint should construct its wall-mounted multi-cell charger.")
	TEST_ASSERT(found_shuttle_chair, "Cutter blueprint should contain a material-aware shuttle chair.")
	for(var/family in generated_families)
		TEST_ASSERT(generated_families[family], "Cutter blueprint should generate its mapped [family] fixtures.")
	TEST_ASSERT_EQUAL(generic_cutter.registration_port_type, /obj/docking_port/mobile/custom, "Generic Cutter disk should retain custom registration.")
	TEST_ASSERT_EQUAL(generic_patrol.registration_port_type, /obj/docking_port/mobile/custom, "Generic Patrol disk should retain custom registration.")
	TEST_ASSERT_EQUAL(typed_cutter.registration_port_type, /obj/docking_port/mobile/overmap/frigate/solfed_cutter, "Typed Cutter disk should select its frigate port.")
	TEST_ASSERT_EQUAL(typed_patrol.registration_port_type, /obj/docking_port/mobile/overmap/frigate/solfed_patrol, "Typed Patrol disk should select its frigate port.")
	TEST_ASSERT_EQUAL(typed_cutter.registration_area_type, /area/shuttle/overmap/frigate, "Typed Cutter disk should select the frigate area.")
	TEST_ASSERT_EQUAL(typed_patrol.registration_area_type, /area/shuttle/overmap/frigate, "Typed Patrol disk should select the frigate area.")
	TEST_ASSERT(!typed_cutter.registration_is_custom && !typed_patrol.registration_is_custom, "Typed disks should register as non-custom shuttles.")

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
	registered_port = fabricator.built_shuttle
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

/datum/unit_test/overmap_shipyard_fabricator/phase_primitives

/datum/unit_test/overmap_shipyard_fabricator/phase_primitives/Run()
	var/turf/open/floor/origin = run_loc_floor_bottom_left
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
	TEST_ASSERT_EQUAL(plating.execute(fabricator), TRUE, "Plating phase should replay shuttle frame tiling.")
	TEST_ASSERT(plating.satisfied(get_turf(origin)), "Plating operation postcondition should pass.")
	qdel(rods)
	qdel(plating)

