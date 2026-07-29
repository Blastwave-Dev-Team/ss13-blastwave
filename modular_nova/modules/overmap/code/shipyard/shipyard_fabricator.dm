// MODULE ID: OVERMAP
// Silo-fed, landing-zone-bound phased shuttle construction machine.

#define SHIPYARD_STATE_IDLE "idle"
#define SHIPYARD_STATE_BUILDING "building"
#define SHIPYARD_STATE_PAUSED "paused"
#define SHIPYARD_STATE_FAULT "fault"
#define SHIPYARD_STATE_COMPLETE "complete"

/// The step ran a placement, so the fabricator owes its placement delay.
#define SHIPYARD_STEP_PLACED "placed"
/// The step only confirmed work already standing, so the next one can run now.
#define SHIPYARD_STEP_CONFIRMED "confirmed"
/// The build stopped, whether finished, paused, or faulted.
#define SHIPYARD_STEP_HALT "halt"
/// Operations confirmed in a single tick while catching up to a resumed build.
#define SHIPYARD_CONFIRMS_PER_TICK 100

/// Active draw with the crudest stock parts the board accepts.
#define SHIPYARD_ACTIVE_POWER_TIER_ONE (600 KILO WATTS)
/// Active draw once every stock part is tier four.
#define SHIPYARD_ACTIVE_POWER_TIER_FOUR (200 KILO WATTS)

#define SHIPYARD_OP_DELAY (1 SECONDS)
#define SHIPYARD_DEPLOY_TIME (1 SECONDS)
#define SHIPYARD_BEAM_TIME (0.5 SECONDS)
#define SHIPYARD_DISH_PIXEL_X 32

#define SHIPYARD_DISH_IDLE "shuttle_printer-dish_idle"
#define SHIPYARD_DISH_ACTIVE "shuttle_printer-dish_active"
#define SHIPYARD_DISH_ERROR "shuttle_printer-dish_error"
#define SHIPYARD_RPED "shuttle_printer-rped"
#define SHIPYARD_RPED_BLUESPACE "shuttle_printer-rped_bluespace"
#define SHIPYARD_RPED_LIGHT "shuttle_printer-rped_slot_light"
#define SHIPYARD_SCREEN_IDLE "shuttle_printer-screen_idle"
#define SHIPYARD_SCREEN_WORKING "shuttle_printer-screen_working"
#define SHIPYARD_SCREEN_ERROR "shuttle_printer-screen_error"
#define SHIPYARD_PANEL "shuttle_printer-maintenance_panel"
#define SHIPYARD_DISK "shuttle_printer-computer_disk"

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
	active_power_usage = SHIPYARD_ACTIVE_POWER_TIER_ONE
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
	/// The hull this run registered as a shuttle once its plating was finished.
	/// Held weakly: the fabricator does not own the ship it printed and outlives
	/// it by an entire round, so a hard reference here would keep a scuttled
	/// vessel alive forever.
	var/datum/weakref/built_shuttle_ref
	var/rotated_plan = FALSE
	var/datum/weakref/last_operator
	/// Whether an operator holds a console session.
	var/authenticated = FALSE
	/// ID record captured at login. Every silo draw is billed against it.
	var/alist/operator_id_data
	/// Current-phase holograms keyed by their source operation ref.
	var/list/phase_projections = list()
	/// Red hologram left on the tile a faulted build could not finish.
	var/obj/effect/overlay/shipyard_projection/fault/fault_marker
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
	// The printer's art is a single 64x64 state spanning both tiles of the
	// finished machine, and the DMI carries no half-width state, so a half
	// wearing it looks exactly like a working fabricator. Cut the western column
	// out of the base state once and share it, so an assembly that still owes a
	// partner reads as unfinished.
	var/static/icon/half_icon
	if(!half_icon)
		half_icon = icon(icon, base_icon_state)
		half_icon.Crop(1, 1, ICON_SIZE_X, ICON_SIZE_Y * 2)
	icon = half_icon
	icon_state = ""
	if(!mapload)
		addtimer(CALLBACK(src, PROC_REF(try_complete_pair)), 1)

/// A half whose partner never gets built is still a machine bolted to the deck,
/// so it has to come apart the same way the assembled fabricator does. Without
/// these a misplaced assembly is permanent.
/obj/machinery/shipyard_fabricator_frame_half/screwdriver_act(mob/living/user, obj/item/tool)
	return default_deconstruction_screwdriver(user, tool)

/obj/machinery/shipyard_fabricator_frame_half/crowbar_act(mob/living/user, obj/item/tool)
	return default_deconstruction_crowbar(user, tool)

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
	var/lit = !(machine_stat & (NOPOWER | BROKEN))
	if(panel_open)
		. += mutable_appearance(icon, SHIPYARD_PANEL, layer + 0.05)
	if(blueprint_disk)
		. += mutable_appearance(icon, SHIPYARD_DISK, layer + 0.1)
	if(docked_rped)
		var/rped_icon_state = istype(docked_rped, /obj/item/storage/part_replacer/bluespace) ? SHIPYARD_RPED_BLUESPACE : SHIPYARD_RPED
		. += mutable_appearance(icon, rped_icon_state, layer + 0.1)
		if(lit)
			. += mutable_appearance(icon, SHIPYARD_RPED_LIGHT, layer + 0.15)
	if(lit)
		. += mutable_appearance(icon, screen_icon_state(), layer + 0.1)
	if(!printer_deployed)
		return
	var/mutable_appearance/dish = mutable_appearance(icon, dish_icon_state, layer + 0.2)
	dish.dir = dish_direction
	. += dish

/// Console face for the build the machine is currently sitting on.
/obj/machinery/shipyard_fabricator/proc/screen_icon_state()
	switch(state)
		if(SHIPYARD_STATE_BUILDING)
			return SHIPYARD_SCREEN_WORKING
		if(SHIPYARD_STATE_FAULT)
			return SHIPYARD_SCREEN_ERROR
	return SHIPYARD_SCREEN_IDLE

/// Assigns the build state and keeps the console screen in step with it.
/obj/machinery/shipyard_fabricator/proc/set_build_state(new_state)
	if(state == new_state)
		return
	state = new_state
	update_appearance()

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

	// The parent scales draw up with the summed energy rating of every part, and
	// this machine is paired from two boards, so it carries twelve of them: on
	// tier-four stock that reached 605 kW, far past what an APC can feed it.
	// Draw is taken from the average tier instead, so the part count stops
	// mattering, and better hardware spends less rather than more. Idle draw is
	// left at the declared trickle: a parked printer costs nothing to own.
	var/part_total = bin_total + placement_total + scanner_total
	var/part_count = bin_count + placement_count + scanner_count
	var/power_rating = part_count ? clamp(part_total / part_count, 1, 4) : 1
	var/tier_saving = (SHIPYARD_ACTIVE_POWER_TIER_ONE - SHIPYARD_ACTIVE_POWER_TIER_FOUR) / 3
	idle_power_usage = initial(idle_power_usage)
	active_power_usage = round(SHIPYARD_ACTIVE_POWER_TIER_ONE - ((power_rating - 1) * tier_saving), 1)
	update_current_power_usage()

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

/// The assembled machine spans two turfs, so it has to hand back a frame for
/// each half it was paired from rather than the single frame machines assume.
/obj/machinery/shipyard_fabricator/spawn_frame(disassembled)
	. = ..()
	var/turf/east_turf = get_step(src, EAST)
	if(!east_turf)
		return
	var/obj/structure/frame/machine/east_frame = new(east_turf)
	east_frame.state = FRAME_STATE_WIRED
	if(east_turf.is_blocked_turf(TRUE, source_atom = east_frame, ignore_atoms = list(src)))
		east_frame.deconstruct(disassembled)
		return
	east_frame.update_appearance(UPDATE_ICON_STATE)
	east_frame.set_anchored(anchored)
	if(!disassembled)
		east_frame.update_integrity(east_frame.max_integrity * 0.5)
	transfer_fingerprints_to(east_frame)

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
		update_appearance()
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

/obj/machinery/shipyard_fabricator/screwdriver_act(mob/living/user, obj/item/tool)
	if(state == SHIPYARD_STATE_BUILDING)
		balloon_alert(user, "build in progress")
		return ITEM_INTERACT_BLOCKING
	return default_deconstruction_screwdriver(user, tool)

/obj/machinery/shipyard_fabricator/crowbar_act(mob/living/user, obj/item/tool)
	if(state == SHIPYARD_STATE_BUILDING)
		balloon_alert(user, "build in progress")
		return ITEM_INTERACT_BLOCKING
	return default_deconstruction_crowbar(user, tool)

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

/// Secure login mirroring the landing zone controller: checks reach + access.
/obj/machinery/shipyard_fabricator/proc/secure_login(mob/user)
	if(!user.can_perform_action(src, ALLOW_SILICON_REACH) || !is_operational)
		return FALSE
	if(!allowed(user))
		balloon_alert(user, "access denied")
		playsound(src, 'sound/machines/terminal/terminal_error.ogg', 70, TRUE)
		return FALSE
	balloon_alert(user, "logged in")
	playsound(src, 'sound/machines/terminal/terminal_on.ogg', 70, TRUE)
	return TRUE

/// Identity the ore silo bills for this fabricator's draws. Never null: the
/// silo logs and access checks both read fields straight off this record.
/obj/machinery/shipyard_fabricator/proc/consumer_id_data()
	return operator_id_data || ID_DATA(null)

/obj/machinery/shipyard_fabricator/ui_data(mob/user)
	var/list/data = list()
	var/has_session = (authenticated && isliving(user)) || isAdminGhostAI(user)
	data["authenticated"] = has_session
	data["operatorName"] = operator_id_data?["name"]
	if(!has_session)
		return data

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
	data["zoneOccupied"] = !!blocking_occupant(zone)
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
		var/obj/item/item_path = shipyard_part_item_type(part_path)
		var/count = 0
		for(var/obj/item/part in docked_rped?.contents)
			if(istype(part, item_path))
				count++
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
	var/admin_ghost = isAdminGhostAI(user)

	switch(action)
		if("login")
			if(admin_ghost)
				authenticated = TRUE
				return TRUE
			authenticated = secure_login(user)
			if(authenticated)
				operator_id_data = ID_DATA(user)
				last_operator = WEAKREF(user)
			return TRUE
		if("logout")
			authenticated = FALSE
			operator_id_data = null
			balloon_alert(user, "logged out")
			playsound(src, 'sound/machines/terminal/terminal_off.ogg', 70, TRUE)
			return TRUE

	// Mirror ui_data: admin ghosts can act without a living login session.
	if(!((authenticated && isliving(user)) || admin_ghost))
		return FALSE

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
			update_appearance()
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

/**
 * The zone occupant that stands in this fabricator's way, or null when the pad
 * is clear enough to work on.
 *
 * A hull is registered as a real shuttle the moment its plating is finished, so
 * from that phase onward the zone is legitimately occupied by the ship being
 * printed. A run that is still going may disregard its own hull; a fresh print
 * may not, because the reference still names the last ship built here until the
 * new run replaces it.
 */
/obj/machinery/shipyard_fabricator/proc/blocking_occupant(obj/effect/landmark/overmap_landing_zone/zone)
	if(!zone)
		return null
	var/continuing = (state in list(SHIPYARD_STATE_BUILDING, SHIPYARD_STATE_PAUSED, SHIPYARD_STATE_FAULT))
	return zone.get_occupant(continuing ? built_shuttle_ref?.resolve() : null)

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
	if(!materials?.silo || !materials.can_use_resource(user_data = consumer_id_data()))
		paused_reason = "A live ore silo connection is required."
		return FALSE
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	var/obj/effect/landmark/overmap_landing_zone/zone = controller?.active_zone
	if(!zone)
		paused_reason = "Link a controller with an active landing zone."
		return FALSE
	if(blocking_occupant(zone))
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
		built_shuttle_ref = null
	last_operator = WEAKREF(user)
	paused_reason = null
	clear_fault_marker()
	var/was_deployed = printer_deployed
	deploy_printer()
	set_build_state(SHIPYARD_STATE_BUILDING)
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
	set_build_state(SHIPYARD_STATE_PAUSED)
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
		"step" = operation_index,
	))
	mark_fault_tile(operation, target)
	set_build_state(SHIPYARD_STATE_FAULT)
	set_dish_state(SHIPYARD_DISH_ERROR)
	update_use_power(IDLE_POWER_USE)
	STOP_PROCESSING(SSmachines, src)

/**
 * Drops the faults the build has since worked past.
 *
 * A fault is a standing request for someone to go fix something, so resuming
 * does not retire it: the step that failed has to actually land. Phase
 * completion faults are recorded against the step they stalled on too, so they
 * clear the same way once that step gets through.
 */
/obj/machinery/shipyard_fabricator/proc/retire_resolved_faults()
	for(var/list/fault in faults.Copy())
		if(fault["step"] >= operation_index)
			continue
		faults -= list(fault)

/// Paints the offending tile red so the fault report has somewhere to point.
/obj/machinery/shipyard_fabricator/proc/mark_fault_tile(datum/ship_plan_op/operation, turf/target)
	clear_fault_marker()
	if(!operation || !target)
		return
	fault_marker = new(target, operation)
	if(QDELETED(fault_marker))
		fault_marker = null

/obj/machinery/shipyard_fabricator/proc/clear_fault_marker()
	QDEL_NULL(fault_marker)

/obj/machinery/shipyard_fabricator/proc/abort_build()
	STOP_PROCESSING(SSmachines, src)
	clear_phase_projections()
	release_build_claim()
	release_zone()
	set_build_state(SHIPYARD_STATE_IDLE)
	operation_index = 1
	current_phase = 0
	paused_reason = null
	retract_printer()
	update_use_power(IDLE_POWER_USE)

/// Let go of the hull this run registered, so it can be filed away or scuttled.
/// A hull still under the printer refuses teardown: its claim and operation
/// index would go stale the moment anything was taken off it.
/obj/machinery/shipyard_fabricator/proc/release_build_claim()
	var/obj/docking_port/mobile/registered = built_shuttle_ref?.resolve()
	if(registered?.shipyard_build_claim?.resolve() == src)
		registered.shipyard_build_claim = null

/obj/machinery/shipyard_fabricator/proc/release_zone()
	var/obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve()
	if(zone?.shipyard_claim?.resolve() == src)
		zone.shipyard_claim = null
	claimed_zone = null

/obj/machinery/shipyard_fabricator/proc/clear_phase_projections()
	QDEL_LIST_ASSOC_VAL(phase_projections)
	phase_projections = list()
	clear_fault_marker()

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
	// Confirming work that already stands costs nothing to place, so a resumed
	// build races back to where it left off instead of paying placement time per
	// tile all over again.
	for(var/step in 1 to SHIPYARD_CONFIRMS_PER_TICK)
		var/outcome = advance_operation()
		if(outcome == SHIPYARD_STEP_HALT)
			return PROCESS_KILL
		if(outcome == SHIPYARD_STEP_PLACED)
			return

/**
 * Runs the operation the build index points at and moves the index along.
 *
 * Returns SHIPYARD_STEP_PLACED when something was built and the placement delay
 * applies, SHIPYARD_STEP_CONFIRMED when the tile already held the work and the
 * next operation can run immediately, or SHIPYARD_STEP_HALT when the build
 * finished, paused, or faulted.
 */
/obj/machinery/shipyard_fabricator/proc/advance_operation()
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	if(!plan || operation_index > length(plan.manifest))
		finish_build()
		return SHIPYARD_STEP_HALT
	var/datum/ship_plan_op/operation = plan.manifest[operation_index]
	if(operation.phase != current_phase)
		if(current_phase && !complete_phase(current_phase))
			return SHIPYARD_STEP_HALT
		current_phase = operation.phase
		project_phase(current_phase)
	var/confirming = operation.needs_no_work(src)
	var/result = operation.execute(src)
	if(result != TRUE)
		if(istext(result))
			fault_build(operation, result)
		else
			pause_build("Waiting for materials or parts.")
		return SHIPYARD_STEP_HALT
	clear_operation_projection(operation)
	operation_index++
	if(length(faults))
		retire_resolved_faults()
	if(operation_index > length(plan.manifest))
		if(!complete_phase(current_phase))
			return SHIPYARD_STEP_HALT
		finish_build()
		return SHIPYARD_STEP_HALT
	if(confirming)
		return SHIPYARD_STEP_CONFIRMED
	next_operation_at = world.time + fabrication_delay
	return SHIPYARD_STEP_PLACED

/obj/machinery/shipyard_fabricator/proc/get_operation_turf(datum/ship_plan_op/operation, obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve())
	if(!operation || !zone)
		return null
	if(rotated_plan)
		var/datum/ship_plan/plan = blueprint_disk?.ship_plan
		return locate(zone.x + operation.rel_y, zone.y + plan.width - 1 - operation.rel_x, zone.z)
	return locate(zone.x + operation.rel_x, zone.y + operation.rel_y, zone.z)

/// Every tile the manifest lays hull plating on.
/obj/machinery/shipyard_fabricator/proc/hull_turfs()
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	if(!plan)
		return list()
	var/obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve()
	var/list/turfs = list()
	for(var/datum/ship_plan_op/operation as anything in plan.manifest)
		if(operation.op_type != SHIPYARD_OP_PLATING)
			continue
		var/turf/hull = get_operation_turf(operation, zone)
		if(hull)
			turfs |= hull
	return turfs

/obj/machinery/shipyard_fabricator/proc/complete_phase(phase)
	if(phase != SHIPYARD_PHASE_PLATING || built_shuttle_ref?.resolve())
		return TRUE
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	var/obj/effect/landmark/overmap_landing_zone/zone = claimed_zone?.resolve()
	var/list/hull_turfs = hull_turfs()
	if(!length(hull_turfs))
		fault_build(null, "No hull plating exists for shuttle registration.")
		return FALSE
	var/turf/origin = hull_turfs[1]
	var/mob/living/operator = last_operator?.resolve()
	var/shuttle_id = "shipyard_[REF(src)]_[world.time]"
	var/obj/docking_port/mobile/registered = create_shuttle(
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
	if(!registered)
		fault_build(null, "Shuttle registration failed after plating.")
		return FALSE
	built_shuttle_ref = WEAKREF(registered)
	registered.shipyard_build_claim = WEAKREF(src)
	assign_mapped_areas(registered, zone)
	if(istype(registered, /obj/docking_port/mobile/custom))
		var/obj/item/shuttle_blueprints/master = new(drop_location())
		master.link_to_shuttle(registered, TRUE)
	return TRUE

/**
 * Divide the registered hull up the way the blueprint divided it.
 *
 * `create_shuttle()` merges every tile it is handed into one area, which is
 * wrong for any hull the blueprint drew more than one room on: `area.apc` is a
 * single slot, so a ship with two APCs has them overwriting each other. The
 * largest mapped area stays as the registration area the ship is docked and
 * named by, and each of the others becomes an instance of its own mapped type -
 * a type rather than a rename, so that exporting and reloading the hull
 * reproduces the same division instead of collapsing it again.
 */
/obj/machinery/shipyard_fabricator/proc/assign_mapped_areas(obj/docking_port/mobile/registered, obj/effect/landmark/overmap_landing_zone/zone)
	var/datum/ship_plan/plan = blueprint_disk?.ship_plan
	if(!length(plan?.tile_areas))
		return
	var/list/grouped = list()
	for(var/datum/ship_plan_op/operation as anything in plan.manifest)
		if(operation.op_type != SHIPYARD_OP_PLATING)
			continue
		var/area_type = plan.tile_areas["[operation.rel_x],[operation.rel_y]"]
		if(!ispath(area_type, /area/shuttle))
			continue
		var/turf/hull = get_operation_turf(operation, zone)
		if(!hull)
			continue
		var/list/tiles = grouped[area_type]
		if(!tiles)
			tiles = list()
			grouped[area_type] = tiles
		tiles += hull
	if(length(grouped) < 2)
		return

	var/dominant
	for(var/area_type in grouped)
		if(!dominant || length(grouped[area_type]) > length(grouped[dominant]))
			dominant = area_type
	for(var/area_type in grouped)
		if(area_type == dominant)
			continue
		var/area/carved = new area_type()
		carved.setup(initial(carved.name))
		registered.shuttle_areas[carved] = TRUE
		set_turfs_to_area(grouped[area_type], carved)
		carved.reg_in_areas_in_z()
		carved.create_area_lighting_objects()
		carved.power_change()

/**
 * Bring the finished ship's power grid up.
 *
 * Printed cable goes live as it is laid, but a build has several ways to leave a
 * hole in that. A power machine that landed on its tile before the cable did found
 * nothing to join and is never asked a second time. The terminals that APCs and
 * chargers draw through are not built until their own commissioning step, later
 * than the cable that would have connected them. A portable SMES is printed loose
 * on the deck rather than on its connector. Repairing all of it once here, in
 * dependency order - the links, then the grid, then everything drawing off it -
 * settles those without the manifest having to run in any particular order.
 */
/obj/machinery/shipyard_fabricator/proc/energize_hull()
	var/list/hull = hull_turfs()
	for(var/turf/deck as anything in hull)
		for(var/obj/machinery/machine in deck)
			// Wide machines list themselves in every turf they overlap.
			if(machine.loc == deck)
				machine.shipyard_pair()
	for(var/turf/deck as anything in hull)
		for(var/obj/structure/cable/cable in deck)
			cable.propagate_if_no_network()
	for(var/turf/deck as anything in hull)
		for(var/obj/machinery/power/machine in deck)
			if(machine.loc == deck)
				machine.connect_to_network()

/obj/machinery/shipyard_fabricator/proc/finish_build()
	// Before the zone is released: the hull is located through the zone it was
	// built in.
	energize_hull()
	clear_phase_projections()
	release_build_claim()
	set_build_state(SHIPYARD_STATE_COMPLETE)
	paused_reason = "Construction complete. Frames listed as incomplete require manual RPED finishing."
	retract_printer()
	update_use_power(IDLE_POWER_USE)
	release_zone()
	playsound(src, 'sound/machines/ping.ogg', 50, TRUE)

#undef SHIPYARD_STEP_PLACED
#undef SHIPYARD_STEP_CONFIRMED
#undef SHIPYARD_STEP_HALT
#undef SHIPYARD_CONFIRMS_PER_TICK

#undef SHIPYARD_ACTIVE_POWER_TIER_ONE
#undef SHIPYARD_ACTIVE_POWER_TIER_FOUR

#undef SHIPYARD_OP_DELAY
#undef SHIPYARD_DEPLOY_TIME
#undef SHIPYARD_BEAM_TIME
#undef SHIPYARD_DISH_PIXEL_X

#undef SHIPYARD_DISH_IDLE
#undef SHIPYARD_DISH_ACTIVE
#undef SHIPYARD_DISH_ERROR

#undef SHIPYARD_RPED_LIGHT
#undef SHIPYARD_SCREEN_IDLE
#undef SHIPYARD_SCREEN_WORKING
#undef SHIPYARD_SCREEN_ERROR
#undef SHIPYARD_PANEL
#undef SHIPYARD_DISK

