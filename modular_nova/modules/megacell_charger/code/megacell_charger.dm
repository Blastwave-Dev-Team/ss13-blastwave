/obj/machinery/power/megacell_charger
	name = "megacell charger frame"
	desc = "An APC wall frame being converted into a dedicated megacell charging station."
	icon = 'modular_nova/modules/aesthetics/apc/icons/apc.dmi'
	icon_state = "apc0"
	anchored = TRUE
	density = FALSE
	pass_flags = PASSTABLE
	use_power = IDLE_POWER_USE
	idle_power_usage = 5
	active_power_usage = 60
	power_channel = AREA_USAGE_EQUIP
	circuit = null
	/// Construction progress.
	var/buildstage = MEGACELL_CHARGER_FRAME
	/// Underfloor grid terminal, same pattern as APCs.
	var/obj/machinery/power/terminal/terminal
	/// Parts still required before welding.
	var/list/req_components = list(
		/obj/item/stack/sheet/iron = 5,
		/datum/stock_part/capacitor = 1,
	)
	/// Megacell currently in the charging slot.
	var/obj/item/stock_parts/power_store/battery/charging
	/// Grid draw per process tick when charging.
	var/charge_rate = STANDARD_BATTERY_RATE

/obj/machinery/power/megacell_charger/Initialize(mapload)
	. = ..()
	if(mapload && buildstage >= MEGACELL_CHARGER_COMPLETE)
		make_terminal()
		terminal?.connect_to_network()
		find_and_mount_on_atom()
		register_wall_bump_shock()
	else if(!mapload)
		buildstage = MEGACELL_CHARGER_FRAME
		panel_open = TRUE
	register_context()
	update_appearance()

/obj/machinery/power/megacell_charger/Destroy()
	unregister_wall_bump_shock()
	if(terminal)
		disconnect_terminal()
	QDEL_NULL(charging)
	return ..()

/obj/machinery/power/megacell_charger/setDir(newdir)
	. = ..()
	switch(newdir)
		if(NORTH)
			pixel_y = MEGACELL_CHARGER_PIXEL_OFFSET
		if(SOUTH)
			pixel_y = -MEGACELL_CHARGER_PIXEL_OFFSET
		if(EAST)
			pixel_x = MEGACELL_CHARGER_PIXEL_OFFSET
		if(WEST)
			pixel_x = -MEGACELL_CHARGER_PIXEL_OFFSET

/obj/machinery/power/megacell_charger/connect_to_network()
	if(terminal)
		terminal.connect_to_network()

/obj/machinery/power/megacell_charger/disconnect_terminal()
	if(terminal)
		terminal.master = null
		terminal = null

/obj/machinery/power/megacell_charger/proc/make_terminal(terminal_cable_layer = cable_layer)
	terminal = locate(/obj/machinery/power/terminal) in loc
	if(QDELETED(terminal))
		terminal = new /obj/machinery/power/terminal(loc)
	terminal.cable_layer = terminal_cable_layer
	terminal.setDir(dir)
	terminal.master = src

/obj/machinery/power/megacell_charger/can_terminal_dismantle()
	return panel_open && buildstage >= MEGACELL_CHARGER_TERMINAL

/obj/machinery/power/megacell_charger/shock(mob/living/shocking, chance = 50, shock_source, siemens_coeff = 1)
	shock_source = shock_source || terminal?.powernet
	if(!shock_source)
		return FALSE
	return ..()

/obj/machinery/power/megacell_charger/proc/shock_if_live(mob/living/user, chance = 50)
	if(buildstage < MEGACELL_CHARGER_COMPLETE)
		return FALSE
	if(!terminal?.powernet)
		return FALSE
	return shock(user, chance)

/obj/machinery/power/megacell_charger/proc/shock_on_conductive_tool(mob/living/user, obj/item/tool, chance = 50)
	if(buildstage < MEGACELL_CHARGER_COMPLETE)
		return FALSE
	if(!(tool.obj_flags & CONDUCTS_ELECTRICITY))
		return FALSE
	return shock_if_live(user, chance)

/obj/machinery/power/megacell_charger/proc/register_wall_bump_shock()
	unregister_wall_bump_shock()
	var/datum/component/atom_mounted/mount = GetComponent(/datum/component/atom_mounted)
	if(!mount?.hanging_support_atom)
		return
	RegisterSignal(mount.hanging_support_atom, COMSIG_ATOM_BUMPED, PROC_REF(on_support_bumped))

/obj/machinery/power/megacell_charger/proc/unregister_wall_bump_shock()
	var/datum/component/atom_mounted/mount = GetComponent(/datum/component/atom_mounted)
	if(!mount?.hanging_support_atom)
		return
	UnregisterSignal(mount.hanging_support_atom, COMSIG_ATOM_BUMPED)

/obj/machinery/power/megacell_charger/proc/on_support_bumped(datum/source, atom/movable/bumped_atom)
	SIGNAL_HANDLER
	if(isliving(bumped_atom))
		shock_if_live(bumped_atom)

/obj/machinery/power/megacell_charger/Bumped(atom/movable/bumped_atom)
	if(isliving(bumped_atom))
		shock_if_live(bumped_atom)
	return ..()

/obj/machinery/power/megacell_charger/proc/parts_complete()
	for(var/requirement in req_components)
		if(req_components[requirement] > 0)
			return FALSE
	return TRUE

/obj/machinery/power/megacell_charger/proc/update_buildstage_from_parts()
	if(buildstage < MEGACELL_CHARGER_TERMINAL)
		return
	if(parts_complete())
		buildstage = MEGACELL_CHARGER_PARTS
	else if(buildstage == MEGACELL_CHARGER_PARTS)
		buildstage = MEGACELL_CHARGER_TERMINAL

/obj/machinery/power/megacell_charger/proc/can_place_terminal(mob/living/user, obj/item/stack/cable_coil/installing_cable, silent = TRUE)
	if(buildstage != MEGACELL_CHARGER_FRAME)
		return FALSE
	if(panel_open)
		if(!silent && user)
			balloon_alert(user, "close the panel first!")
		return FALSE
	var/turf/host_turf = get_turf(src)
	if(host_turf.underfloor_accessibility < UNDERFLOOR_INTERACTABLE)
		if(!silent && user)
			balloon_alert(user, "remove the floor plating!")
		return FALSE
	if(!isnull(terminal))
		if(!silent && user)
			balloon_alert(user, "already wired!")
		return FALSE
	if(installing_cable.get_amount() < 10)
		if(!silent && user)
			balloon_alert(user, "need ten lengths of cable!")
		return FALSE
	return TRUE

/obj/machinery/power/megacell_charger/proc/cable_act(mob/living/user, obj/item/stack/cable_coil/installing_cable, is_right_clicking)
	if(buildstage != MEGACELL_CHARGER_FRAME)
		return NONE
	if(!can_place_terminal(user, installing_cable, silent = FALSE))
		return ITEM_INTERACT_BLOCKING

	var/terminal_cable_layer = cable_layer
	if(is_right_clicking)
		var/choice = tgui_input_list(user, "Select Power Input Cable Layer", "Select Cable Layer", GLOB.cable_name_to_layer)
		if(isnull(choice) \
			|| !user.is_holding(installing_cable) \
			|| !user.Adjacent(src) \
			|| user.incapacitated \
			|| !can_place_terminal(user, installing_cable, silent = TRUE) \
		)
			return ITEM_INTERACT_BLOCKING
		terminal_cable_layer = GLOB.cable_name_to_layer[choice]

	user.visible_message(span_notice("[user] starts adding cables to [src]."))
	balloon_alert(user, "adding cables...")
	playsound(src, 'sound/items/deconstruct.ogg', 50, TRUE)

	if(!do_after(user, 2 SECONDS, target = src))
		return ITEM_INTERACT_BLOCKING
	if(!can_place_terminal(user, installing_cable, silent = TRUE))
		return ITEM_INTERACT_BLOCKING

	var/turf/our_turf = get_turf(src)
	var/obj/structure/cable/cable_node = our_turf.get_cable_node(terminal_cable_layer)
	if(prob(50) && electrocute_mob(user, cable_node, cable_node, 1, TRUE))
		do_sparks(5, TRUE, src)
		return ITEM_INTERACT_BLOCKING

	installing_cable.use(10)
	user.visible_message(span_notice("[user] adds cables to [src]."))
	balloon_alert(user, "cables added")
	make_terminal(terminal_cable_layer)
	terminal.connect_to_network()
	buildstage = MEGACELL_CHARGER_TERMINAL
	panel_open = TRUE
	update_appearance()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/megacell_charger/proc/add_part(mob/living/user, obj/item/tool)
	if(buildstage < MEGACELL_CHARGER_TERMINAL || buildstage >= MEGACELL_CHARGER_COMPLETE)
		return FALSE
	if(!panel_open)
		balloon_alert(user, "open the panel!")
		return FALSE

	for(var/stock_part_base in req_components)
		if(req_components[stock_part_base] <= 0)
			continue

		if(ispath(stock_part_base, /obj/item/stack))
			if(!istype(tool, stock_part_base))
				continue
			var/obj/item/stack/stack = tool
			var/used_amount = min(round(stack.get_amount()), req_components[stock_part_base])
			if(!used_amount || !stack.use(used_amount))
				continue
			req_components[stock_part_base] -= used_amount
			to_chat(user, span_notice("You add [tool] to [src]."))
			update_buildstage_from_parts()
			update_appearance()
			return TRUE

		if(ispath(stock_part_base, /datum/stock_part))
			var/datum/stock_part/stock_part_datum_type = stock_part_base
			var/stock_part_path = initial(stock_part_datum_type.physical_object_type)
			if(!istype(tool, stock_part_path))
				continue
			var/datum/stock_part/stock_part_datum = GLOB.stock_part_datums_per_object[tool.type]
			if(isnull(stock_part_datum))
				stack_trace("[tool.type] does not have an associated stock part datum!")
				continue
			var/part_name = tool.name
			LAZYADD(component_parts, stock_part_datum)
			qdel(tool)
			req_components[stock_part_base]--
			to_chat(user, span_notice("You add [part_name] to [src]."))
			update_buildstage_from_parts()
			update_appearance()
			return TRUE

	balloon_alert(user, "can't add that!")
	return FALSE

/obj/machinery/power/megacell_charger/proc/eject_parts(mob/living/user)
	if(buildstage < MEGACELL_CHARGER_TERMINAL || buildstage >= MEGACELL_CHARGER_COMPLETE)
		return FALSE
	if(!panel_open)
		balloon_alert(user, "open the panel!")
		return FALSE

	for(var/datum/stock_part/capacitor/capacitor_datum in component_parts)
		component_parts -= capacitor_datum
		var/obj/item/stock_parts/capacitor/capacitor_item = new capacitor_datum.physical_object_type()
		if(!user.put_in_hands(capacitor_item))
			capacitor_item.forceMove(drop_location())
		req_components[/datum/stock_part/capacitor]++
		update_buildstage_from_parts()
		update_appearance()
		balloon_alert(user, "removed capacitor")
		return TRUE

	return FALSE

/obj/machinery/power/megacell_charger/proc/finish_construction(mob/living/user, obj/item/welder)
	name = "megacell charger"
	desc = "A wall-mounted charging station for megacells, field-modified from an APC frame."
	icon = 'modular_nova/modules/megacell_charger/icons/big_cell_charger.dmi'
	icon_state = "big_cell_charger"
	buildstage = MEGACELL_CHARGER_COMPLETE
	panel_open = FALSE
	connect_to_network()
	RefreshParts()
	register_wall_bump_shock()
	update_appearance()
	balloon_alert(user, "construction complete")

/obj/machinery/power/megacell_charger/proc/unfinish_construction(mob/living/user)
	name = "megacell charger frame"
	desc = "An APC wall frame being converted into a dedicated megacell charging station."
	icon = 'modular_nova/modules/aesthetics/apc/icons/apc.dmi'
	buildstage = MEGACELL_CHARGER_PARTS
	panel_open = TRUE
	unregister_wall_bump_shock()
	update_appearance()
	balloon_alert(user, "welds cut")

/obj/machinery/power/megacell_charger/proc/charge_power_store(amount, obj/item/stock_parts/power_store/target)
	var/demand = use_energy(min(amount, target.used_charge()), channel = power_channel, ignore_apc = TRUE)
	return target.give(demand)

/obj/machinery/power/megacell_charger/RefreshParts()
	if(!islist(component_parts))
		component_parts = isdatum(component_parts) ? list(component_parts) : list()
	. = ..()
	charge_rate = STANDARD_BATTERY_RATE
	for(var/datum/stock_part/capacitor/capacitor in component_parts)
		charge_rate *= capacitor.tier

/obj/machinery/power/megacell_charger/examine(mob/user)
	. = ..()
	switch(buildstage)
		if(MEGACELL_CHARGER_FRAME)
			. += "The frame is mounted but not wired to the grid."
			if(panel_open)
				. += span_notice("Close the panel, then add a power terminal with [EXAMINE_HINT("cable coil")].")
		if(MEGACELL_CHARGER_TERMINAL)
			. += "The frame is wired to the grid."
			if(!parts_complete())
				. += span_notice("Insert [req_components[/obj/item/stack/sheet/iron]] iron sheets and a capacitor.")
			else
				. += span_notice("All parts are in place. [EXAMINE_HINT("Weld")] it shut to finish.")
		if(MEGACELL_CHARGER_PARTS)
			. += span_notice("All internal parts are installed. [EXAMINE_HINT("Weld")] it shut to finish.")
		if(MEGACELL_CHARGER_COMPLETE)
			. += "There's [charging ? "\a [charging]" : "no megacell"] in the charger."
			if(charging)
				. += "Current charge: [round(charging.percent(), 1)]%."
			if(in_range(user, src) || isobserver(user))
				. += span_notice("The status display reads: Charging power: <b>[display_power(charge_rate, convert = FALSE)]</b>.")

/obj/machinery/power/megacell_charger/add_context(atom/source, list/context, obj/item/held_item, mob/user)
	. = ..()
	if(buildstage >= MEGACELL_CHARGER_COMPLETE)
		return
	if(held_item?.tool_behaviour == TOOL_SCREWDRIVER)
		context[SCREENTIP_CONTEXT_LMB] = panel_open ? "Close panel" : "Open panel"
	if(buildstage == MEGACELL_CHARGER_FRAME && !panel_open && istype(held_item, /obj/item/stack/cable_coil))
		context[SCREENTIP_CONTEXT_LMB] = "Wire terminal"
	if(buildstage >= MEGACELL_CHARGER_TERMINAL && buildstage < MEGACELL_CHARGER_COMPLETE && panel_open)
		if(istype(held_item, /obj/item/stack/sheet/iron) || istype(held_item, /obj/item/stock_parts/capacitor))
			context[SCREENTIP_CONTEXT_LMB] = "Insert part"
	if(buildstage == MEGACELL_CHARGER_PARTS && held_item?.tool_behaviour == TOOL_WELDER)
		context[SCREENTIP_CONTEXT_LMB] = "Finish construction"

/obj/machinery/power/megacell_charger/update_icon_state()
	if(buildstage >= MEGACELL_CHARGER_COMPLETE)
		icon_state = "big_cell_charger"
		return ..()
	icon_state = panel_open ? "apcmaint" : "apc0"
	return ..()

/obj/machinery/power/megacell_charger/update_overlays()
	. = ..()
	if(buildstage < MEGACELL_CHARGER_COMPLETE || !charging)
		return

	if(is_operational)
		var/charge_level = clamp(round(charging.percent() / 20) + 1, 1, 5)
		. += mutable_appearance(icon, "big_cell_charger-charging_[charge_level]")
		. += mutable_appearance(icon, "big_cell_charger-active_light")

	. += mutable_appearance(icon, "big_cell_charger-[charging.icon_state]")

	var/light_level = (charging.percent() >= 99.5) ? 2 : 1
	. += mutable_appearance(icon, "big_cell_charger-cell_light_[light_level]")

/obj/machinery/power/megacell_charger/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	if(buildstage < MEGACELL_CHARGER_COMPLETE)
		if(istype(tool, /obj/item/stack/cable_coil))
			return cable_act(user, tool, LAZYACCESS(modifiers, RIGHT_CLICK))
		if(add_part(user, tool))
			return ITEM_INTERACT_SUCCESS
		return NONE

	if(!istype(tool, /obj/item/stock_parts/power_store) && shock_on_conductive_tool(user, tool))
		return ITEM_INTERACT_BLOCKING

	if(istype(tool, /obj/item/stock_parts/power_store/battery))
		if(panel_open)
			return NONE
		if(machine_stat & BROKEN)
			to_chat(user, span_warning("[src] is broken!"))
			return ITEM_INTERACT_BLOCKING
		if(charging)
			to_chat(user, span_warning("There is already a megacell in the charger!"))
			return ITEM_INTERACT_BLOCKING

		var/obj/item/stock_parts/power_store/battery/inserting_battery = tool
		if(!is_type_in_typecache(inserting_battery, GLOB.megacell_charger_allowed_batteries))
			balloon_alert(user, "won't fit!")
			return ITEM_INTERACT_BLOCKING
		if(inserting_battery.chargerate <= 0)
			to_chat(user, span_warning("[inserting_battery] cannot be recharged!"))
			return ITEM_INTERACT_BLOCKING

		var/area/charge_area = get_area(src)
		if(!isarea(charge_area) || !charge_area.power_equip)
			to_chat(user, span_warning("[src] blinks red as you try to insert the megacell!"))
			return ITEM_INTERACT_BLOCKING
		if(!user.transferItemToLoc(tool, src))
			return ITEM_INTERACT_BLOCKING

		charging = inserting_battery
		user.visible_message(
			span_notice("[user] inserts a megacell into [src]."),
			span_notice("You insert a megacell into [src]."),
		)
		update_appearance()
		return ITEM_INTERACT_SUCCESS

	if(istype(tool, /obj/item/stock_parts/power_store/cell))
		balloon_alert(user, "too small!")
		return ITEM_INTERACT_BLOCKING

	return NONE

/obj/machinery/power/megacell_charger/screwdriver_act(mob/living/user, obj/item/tool)
	if(buildstage >= MEGACELL_CHARGER_COMPLETE)
		return NONE
	if(charging)
		return NONE

	toggle_panel_open()
	balloon_alert(user, panel_open ? "panel opened" : "panel closed")
	tool.play_tool_sound(src, 50)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/megacell_charger/wirecutter_act(mob/living/user, obj/item/tool)
	if(buildstage != MEGACELL_CHARGER_TERMINAL || !terminal)
		if(buildstage == MEGACELL_CHARGER_PARTS)
			balloon_alert(user, "uninstall the parts first!")
		return NONE
	if(!panel_open)
		balloon_alert(user, "open the panel!")
		return ITEM_INTERACT_BLOCKING

	terminal.dismantle(user, tool)
	buildstage = MEGACELL_CHARGER_FRAME
	update_appearance()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/power/megacell_charger/crowbar_act(mob/living/user, obj/item/tool)
	if(buildstage >= MEGACELL_CHARGER_COMPLETE)
		return NONE
	if(eject_parts(user))
		return ITEM_INTERACT_SUCCESS
	return NONE

/obj/machinery/power/megacell_charger/welder_act(mob/living/user, obj/item/tool)
	if(buildstage == MEGACELL_CHARGER_PARTS)
		if(!tool.tool_start_check(user, amount = 1))
			return ITEM_INTERACT_BLOCKING
		user.visible_message(span_notice("[user] starts welding [src] shut."))
		balloon_alert(user, "welding...")
		if(!tool.use_tool(src, user, 4 SECONDS, volume = 50))
			return ITEM_INTERACT_BLOCKING
		finish_construction(user, tool)
		return ITEM_INTERACT_SUCCESS

	if(buildstage == MEGACELL_CHARGER_COMPLETE)
		if(shock_on_conductive_tool(user, tool))
			return ITEM_INTERACT_BLOCKING
		if(charging)
			balloon_alert(user, "remove the megacell first!")
			return ITEM_INTERACT_BLOCKING
		if(!tool.tool_start_check(user, amount = 1))
			return ITEM_INTERACT_BLOCKING
		user.visible_message(span_notice("[user] starts cutting welds on [src]."))
		balloon_alert(user, "cutting welds...")
		if(!tool.use_tool(src, user, 4 SECONDS, volume = 50))
			return ITEM_INTERACT_BLOCKING
		unfinish_construction(user)
		return ITEM_INTERACT_SUCCESS

	if(buildstage == MEGACELL_CHARGER_FRAME && isnull(terminal) && !LAZYLEN(component_parts) && req_components[/obj/item/stack/sheet/iron] == 5)
		if(!panel_open)
			balloon_alert(user, "open the panel!")
			return ITEM_INTERACT_BLOCKING
		if(!tool.tool_start_check(user, amount = 1))
			return ITEM_INTERACT_BLOCKING
		user.visible_message(span_notice("[user] cuts [src] from the wall."))
		balloon_alert(user, "cutting frame...")
		if(!tool.use_tool(src, user, 5 SECONDS, volume = 50))
			return ITEM_INTERACT_BLOCKING
		new /obj/item/wallframe/apc(drop_location())
		qdel(src)
		return ITEM_INTERACT_SUCCESS

	return NONE

/obj/machinery/power/megacell_charger/attack_hand(mob/living/user, list/modifiers)
	. = ..()
	if(.)
		return
	if(buildstage < MEGACELL_CHARGER_COMPLETE)
		return
	if(shock_if_live(user))
		return
	if(!charging)
		return

	charging.add_fingerprint(user)
	user.visible_message(
		span_notice("[user] removes [charging] from [src]."),
		span_notice("You remove [charging] from [src]."),
	)
	user.put_in_hands(remove_battery())

/obj/machinery/power/megacell_charger/proc/remove_battery()
	. = charging
	charging.update_appearance()
	charging.forceMove(drop_location())
	charging = null
	update_appearance()

/obj/machinery/power/megacell_charger/attack_tk(mob/user)
	if(buildstage < MEGACELL_CHARGER_COMPLETE || !charging)
		return

	to_chat(user, span_notice("You telekinetically remove [charging] from [src]."))
	remove_battery()
	return COMPONENT_CANCEL_ATTACK_CHAIN

/obj/machinery/power/megacell_charger/Exited(atom/movable/gone, direction)
	. = ..()
	if(gone == charging)
		charging = null

/obj/machinery/power/megacell_charger/on_deconstruction(disassembled)
	charging?.forceMove(drop_location())

/obj/machinery/power/megacell_charger/emp_act(severity)
	. = ..()
	if(machine_stat & (BROKEN|NOPOWER) || . & EMP_PROTECT_CONTENTS)
		return
	charging?.emp_act(severity)

/obj/machinery/power/megacell_charger/process(seconds_per_tick)
	if(buildstage < MEGACELL_CHARGER_COMPLETE || !charging || charging.percent() >= 100 || !is_operational)
		return

	var/main_draw = charge_rate * seconds_per_tick
	if(!main_draw)
		return

	var/charge_given = charge_power_store(main_draw, charging)
	if(charge_given)
		use_energy((charge_given + active_power_usage) * 0.01)

	update_appearance()

// Mapper-facing complete wall units.

/obj/machinery/power/megacell_charger/wall
	name = "megacell charger"
	desc = "A wall-mounted charging station for megacells."
	icon = 'modular_nova/modules/megacell_charger/icons/big_cell_charger.dmi'
	icon_state = "big_cell_charger"
	buildstage = MEGACELL_CHARGER_COMPLETE
	req_components = list()

/obj/machinery/power/megacell_charger/wall/Initialize(mapload)
	. = ..()
	if(!mapload)
		buildstage = MEGACELL_CHARGER_COMPLETE
		panel_open = FALSE
		update_appearance()
	if(!LAZYLEN(component_parts))
		LAZYADD(component_parts, GLOB.stock_part_datums[/datum/stock_part/capacitor])
		RefreshParts()

MAPPING_DIRECTIONAL_HELPERS(/obj/machinery/power/megacell_charger, MEGACELL_CHARGER_PIXEL_OFFSET)
