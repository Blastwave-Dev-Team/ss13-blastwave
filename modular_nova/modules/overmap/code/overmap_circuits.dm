// MODULE ID: OVERMAP
// Circuit boards for overmap-specific machines. These mirror the existing
// shuttle / shuttle_engine boards so deconstructing and rebuilding works.

/obj/item/circuitboard/computer/shuttle/helm
	name = "Astrogation Helm"
	desc = "A computer board. Full ship piloting: throttle, heading, autopilot, and NavBall."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/helm

/obj/item/circuitboard/computer/shuttle/helm/viewscreen
	name = "Astrogation Viewscreen"
	desc = "A computer board. Displays the astrogation helm interface as a wall-mounted screen."
	build_path = /obj/machinery/computer/helm/viewscreen

/obj/item/circuitboard/computer/shuttle/overmap_nav
	name = "Astrogation Landing Console"
	desc = "A computer board. Camera-based landing at astrogation landing zones and points of interest."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav

/obj/item/circuitboard/machine/engine/overmap
	name = "Astrogation Thruster"
	desc = "A machine board. A basic low-thrust engine for interstellar travel."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/power/shuttle_engine/overmap
	needs_anchored = FALSE

/obj/item/circuitboard/machine/engine/overmap/void
	name = "Void Thruster"
	desc = "A machine board. Experimental zero-fuel engine. Thrust from nothing."
	build_path = /obj/machinery/power/shuttle_engine/overmap/void

/obj/item/circuitboard/machine/engine/overmap/standard
	name = "Hall-Nuclear-Thermal Engine"
	desc = "A machine board. High-performance astrogation engine with nuclear-thermal assist and a hall-only emergency mode."
	build_path = /obj/machinery/power/shuttle_engine/overmap/standard

/obj/item/circuitboard/machine/overmap/fuel_injector
	name = "Fuel Injector"
	desc = "A machine board. Processes piped or tanked propellant for linked astrogation engines."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/overmap/fuel_injector
	needs_anchored = FALSE
	// Frame construction requires a parts list: circuit_added() copies it
	// unconditionally, so a null list runtimes. These match RefreshParts().
	req_components = list(
		/datum/stock_part/matter_bin = 1,
		/datum/stock_part/micro_laser = 1,
	)

/obj/item/circuitboard/machine/landing_corner
	name = "Landing Zone Corner Beacon"
	desc = "A machine board. Marks one corner of an astrogation landing zone rectangle."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/landing_corner
	req_components = list(
		/datum/stock_part/scanning_module = 1,
		/obj/item/stack/sheet/glass = 1,
	)

/obj/item/circuitboard/machine/shipyard_fabricator
	name = "Shipyard Fabricator Assembly"
	desc = "A machine board for one half of a paired shipyard fabricator. Two adjacent completed frames are required."
	greyscale_colors = CIRCUIT_COLOR_ENGINEERING
	build_path = /obj/machinery/shipyard_fabricator_frame_half
	req_components = list(
		/datum/stock_part/matter_bin = 2,
		/datum/stock_part/micro_laser = 2,
		/datum/stock_part/scanning_module = 1,
		/datum/stock_part/servo = 1,
	)

/obj/item/circuitboard/computer/landing_controller
	name = "Landing Zone Controller"
	desc = "A computer board. Manages a field astrogation landing zone from four corner beacons. Open access; any vessel may land."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/landing_controller

/obj/item/circuitboard/computer/landing_controller/nanotrasen
	name = "Landing Zone Controller (Nanotrasen)"
	desc = "A computer board. Manages a Nanotrasen-authorized landing zone. Restricted console; Nanotrasen vessels only."
	build_path = /obj/machinery/computer/landing_controller/nanotrasen

/obj/item/circuitboard/computer/landing_controller/programmable
	name = "Landing Zone Controller (Programmable)"
	desc = "A landing zone controller computer board. Swipe an ID to associate it with your organization. Use in-hand to toggle between group or user-specific lock."
	build_path = /obj/machinery/computer/landing_controller/programmable
	/// LANDING_CONTROLLER_LOCK_FACTION or LANDING_CONTROLLER_LOCK_USER.
	var/program_mode = LANDING_CONTROLLER_LOCK_FACTION
	/// Pad dock affiliation when faction-programmed (`OVERMAP_AFFILIATION_*`); null = open.
	var/stored_dock_affiliation
	/// Bank account id bound in user mode.
	var/stored_owner_account_id
	/// Display name for the bound user (examine/UI).
	var/stored_owner_name

/obj/item/circuitboard/computer/landing_controller/programmable/Initialize(mapload)
	. = ..()
	register_context()

/obj/item/circuitboard/computer/landing_controller/programmable/proc/is_programmed()
	if(program_mode == LANDING_CONTROLLER_LOCK_USER)
		return !isnull(stored_owner_account_id) || length(stored_owner_name)
	return !isnull(stored_dock_affiliation)

/obj/item/circuitboard/computer/landing_controller/programmable/proc/clear_program()
	stored_dock_affiliation = null
	stored_owner_account_id = null
	stored_owner_name = null

/obj/item/circuitboard/computer/landing_controller/programmable/proc/mode_label()
	return program_mode == LANDING_CONTROLLER_LOCK_USER ? "User" : "Faction"

/obj/item/circuitboard/computer/landing_controller/programmable/attack_self(mob/user)
	clear_program()
	program_mode = (program_mode == LANDING_CONTROLLER_LOCK_FACTION) ? LANDING_CONTROLLER_LOCK_USER : LANDING_CONTROLLER_LOCK_FACTION
	balloon_alert(user, "[mode_label()] mode")
	to_chat(user, span_notice("Landing controller board set to [mode_label()] programming. Prior lock cleared."))
	playsound(src, 'sound/machines/terminal/terminal_select.ogg', 30, TRUE)

/obj/item/circuitboard/computer/landing_controller/programmable/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	var/obj/item/card/id/card = tool.GetID()
	if(isnull(card))
		return NONE
	if(is_programmed())
		if(!card_can_clear(card))
			balloon_alert(user, "access denied")
			playsound(src, 'sound/machines/terminal/terminal_error.ogg', 50, TRUE)
			return ITEM_INTERACT_BLOCKING
		clear_program()
		balloon_alert(user, "program cleared")
		playsound(src, 'sound/machines/terminal/terminal_off.ogg', 50, TRUE)
		return ITEM_INTERACT_SUCCESS

	if(program_mode == LANDING_CONTROLLER_LOCK_USER)
		if(isnull(card.registered_account?.account_id) && !length(card.registered_name))
			balloon_alert(user, "no owner on ID")
			playsound(src, 'sound/machines/terminal/terminal_error.ogg', 50, TRUE)
			return ITEM_INTERACT_BLOCKING
		stored_owner_account_id = card.registered_account?.account_id
		stored_owner_name = card.registered_name || card.registered_account?.account_holder || "bound user"
		stored_dock_affiliation = null
		balloon_alert(user, "user lock set")
		to_chat(user, span_notice("Board locked to [stored_owner_name]. Docking remains open to any vessel."))
		playsound(src, 'sound/machines/terminal/terminal_on.ogg', 50, TRUE)
		return ITEM_INTERACT_SUCCESS

	var/faction_id = get_id_overmap_faction(card)
	var/datum/overmap_faction/faction = get_overmap_faction(faction_id)
	if(isnull(faction))
		balloon_alert(user, "no faction on ID")
		to_chat(user, span_notice("That ID has no overmap faction lock (Tarkon/Interdyne/misc stay open)."))
		playsound(src, 'sound/machines/terminal/terminal_error.ogg', 50, TRUE)
		return ITEM_INTERACT_BLOCKING
	stored_dock_affiliation = faction_id
	stored_owner_account_id = null
	stored_owner_name = null
	balloon_alert(user, "faction lock set")
	to_chat(user, span_notice("Board locked to [faction.name] vessels and console login."))
	playsound(src, 'sound/machines/terminal/terminal_on.ogg', 50, TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/item/circuitboard/computer/landing_controller/programmable/proc/card_can_clear(obj/item/card/id/card)
	if(program_mode == LANDING_CONTROLLER_LOCK_USER)
		if(!isnull(stored_owner_account_id) && card.registered_account?.account_id == stored_owner_account_id)
			return TRUE
		if(length(stored_owner_name) && card.registered_name == stored_owner_name)
			return TRUE
		return FALSE
	return get_id_overmap_faction(card) == stored_dock_affiliation

/obj/item/circuitboard/computer/landing_controller/programmable/examine(mob/user)
	. = ..()
	. += span_notice("Programming mode: <b>[mode_label()]</b>. Use in-hand to toggle.")
	if(!is_programmed())
		. += span_notice("Unprogrammed — open docking and console access after construction.")
		. += span_notice("Swipe an ID to program.")
		return
	if(program_mode == LANDING_CONTROLLER_LOCK_USER)
		. += span_notice("User lock: [stored_owner_name || "bound account"]. Pad docking is open.")
	else
		var/datum/overmap_faction/faction = get_overmap_faction(stored_dock_affiliation)
		if(faction)
			. += span_notice("Faction lock: [faction.name] vessels and console login.")
	. += span_notice("Swipe an authorized ID to clear.")

/obj/item/circuitboard/computer/landing_controller/programmable/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	. = NONE
	if(isnull(held_item))
		context[SCREENTIP_CONTEXT_LMB] = "Toggle [program_mode == LANDING_CONTROLLER_LOCK_FACTION ? "User" : "Faction"] mode"
		return CONTEXTUAL_SCREENTIP_SET
	if(held_item.GetID())
		context[SCREENTIP_CONTEXT_LMB] = is_programmed() ? "Clear program" : "Program board"
		return CONTEXTUAL_SCREENTIP_SET
	return .
