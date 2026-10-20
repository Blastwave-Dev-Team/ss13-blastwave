// MODULE ID: OVERMAP
// The ship lockbox: a vault whose contents survive the ship being filed.
//
// It holds roster entries, not items. Whatever goes in is written down and
// deleted, and is only built again when someone takes it out, so a filing
// copies a list rather than walking real objects.

/// Wrong PINs before the keypad locks out.
#define LOCKBOX_MAX_ATTEMPTS 3
#define LOCKBOX_LOCKOUT_TIME (30 SECONDS)

/datum/armor/ship_lockbox
	melee = 70
	bullet = 60
	laser = 60
	energy = 60
	bomb = 50
	fire = 80
	acid = 80

/**
 * The one container on a ship whose contents survive being saved.
 *
 * Everything else aboard, paperwork and fixture state aside, is discarded on
 * teardown. A single bounded container is what keeps that tractable: the
 * payload is auditable, appraisal has a fixed scope, and a player knows exactly
 * what is coming back with them.
 */
/obj/machinery/ship_lockbox
	name = "ship lockbox"
	desc = "A serialized storage unit, associated with the ship it's stored within. Comes with the latest in NT cargo manifest technology, for insurance purposes. Allegedly tamper-proof."
	icon = 'modular_nova/modules/overmap/icons/vaults.dmi'
	max_integrity = 600
	integrity_failure = 0.25
	armor_type = /datum/armor/ship_lockbox
	interaction_flags_machine = INTERACT_MACHINE_OFFLINE
	/// Roster entries, each with its appraisal cached under "value". Nothing is
	/// kept in contents.
	var/list/stored_entries = list()
	/// Top-level entries a deposit may bring it up to.
	var/max_entries = 30
	/// Sprite prefix for the base states.
	var/skin
	/// Sprite prefix for the overlays and screens every skin shares.
	var/overlay_prefix
	/// Locked against everyone but the hull's owner. Means nothing on a hull
	/// with no owner.
	var/locked = TRUE
	var/door_open = FALSE
	/// "opening" or "closing" while the door animates.
	var/door_motion
	/// A one-shot screen state playing over the steady one.
	var/screen_flash
	var/failed_attempts = 0
	var/lockout_until = 0
	/// How long each one-shot animation runs, by state suffix.
	var/list/animation_lengths = list(
		"opening" = 0.95 SECONDS,
		"closing" = 0.97 SECONDS,
		"on" = 0.15 SECONDS,
		"off" = 0.24 SECONDS,
		"correct" = 0.9 SECONDS,
		"incorrect" = 0.85 SECONDS,
	)

/obj/machinery/ship_lockbox/Initialize(mapload)
	. = ..()
	register_context()
	update_appearance()

/obj/machinery/ship_lockbox/examine(mob/user)
	. = ..()
	. += span_notice("It holds [length(stored_entries)] of [max_entries] items.")
	if(is_broken())
		. += span_warning("Its door has been forced and its keypad is dead.")
	else if(!hull_owner())
		. += span_notice("It is not bound to any vessel's owner, and stays unlocked.")
	else if(is_locked())
		. += span_notice("It is locked. Its owner can open it with their ID and PIN.")

/obj/machinery/ship_lockbox/add_context(atom/source, list/context, obj/item/held_item, mob/user)
	if(held_item?.GetID())
		context[SCREENTIP_CONTEXT_LMB] = "Swipe ID"
		return CONTEXTUAL_SCREENTIP_SET
	if(held_item)
		if(is_raised() && is_accessible())
			context[SCREENTIP_CONTEXT_LMB] = "Store"
			return CONTEXTUAL_SCREENTIP_SET
		return NONE
	if(!is_raised())
		if(!is_locked())
			context[SCREENTIP_CONTEXT_LMB] = "Raise"
			return CONTEXTUAL_SCREENTIP_SET
		return NONE
	if(is_accessible())
		context[SCREENTIP_CONTEXT_LMB] = "Open storage"
		if(door_open)
			context[SCREENTIP_CONTEXT_RMB] = "Close and lock"
		return CONTEXTUAL_SCREENTIP_SET
	if(!is_locked())
		context[SCREENTIP_CONTEXT_LMB] = "Open door"
		return CONTEXTUAL_SCREENTIP_SET
	return NONE

// --- State ------------------------------------------------------------------

/// The character who owns the hull this stands on, or null.
/obj/machinery/ship_lockbox/proc/hull_owner()
	var/obj/docking_port/mobile/hull = SSshuttle.get_containing_shuttle(src)
	return hull?.ship_owner_id

/obj/machinery/ship_lockbox/proc/is_broken()
	return machine_stat & BROKEN

/obj/machinery/ship_lockbox/proc/is_locked()
	return locked && !is_broken() && hull_owner()

/// Whether items can go in and come out right now.
/obj/machinery/ship_lockbox/proc/is_accessible()
	return is_broken() || door_open

/// A floor vault can sink into the deck; a wall vault is always out.
/obj/machinery/ship_lockbox/proc/is_raised()
	return TRUE

/obj/machinery/ship_lockbox/proc/in_lockout()
	return world.time < lockout_until

/// A balloon alert for `user`, when there is one; code can drive the vault too.
/obj/machinery/ship_lockbox/proc/alert_user(mob/user, text)
	if(user)
		balloon_alert(user, text)

/// Play a one-shot screen state over the steady one.
/obj/machinery/ship_lockbox/proc/flash_screen(state)
	screen_flash = state
	update_appearance()
	addtimer(CALLBACK(src, PROC_REF(end_flash), state), animation_lengths[state], TIMER_UNIQUE | TIMER_OVERRIDE)

/obj/machinery/ship_lockbox/proc/end_flash(state)
	if(screen_flash != state)
		return
	screen_flash = null
	update_appearance()

/obj/machinery/ship_lockbox/on_set_is_operational(old_value)
	if(is_broken())
		return
	flash_screen(is_operational ? "on" : "off")

/obj/machinery/ship_lockbox/atom_break(damage_flag)
	. = ..()
	door_motion = null
	update_appearance()

// --- Door -------------------------------------------------------------------

/obj/machinery/ship_lockbox/proc/open_door(mob/user)
	if(door_open || door_motion || is_broken() || is_locked() || !is_raised())
		return FALSE
	if(!is_operational)
		alert_user(user, "no power!")
		return FALSE
	door_motion = "opening"
	playsound(src, 'sound/machines/click.ogg', 50, TRUE)
	update_appearance()
	addtimer(CALLBACK(src, PROC_REF(finish_door_motion)), animation_lengths["opening"], TIMER_UNIQUE | TIMER_OVERRIDE)
	return TRUE

/// Shut and lock at once, so nothing more goes in or out from the first frame.
/obj/machinery/ship_lockbox/proc/close_door(mob/user)
	if(!door_open || door_motion || is_broken())
		return FALSE
	door_open = FALSE
	locked = TRUE
	door_motion = "closing"
	SStgui.close_uis(src)
	playsound(src, 'sound/machines/click.ogg', 50, TRUE)
	update_appearance()
	addtimer(CALLBACK(src, PROC_REF(finish_door_motion)), animation_lengths["closing"], TIMER_UNIQUE | TIMER_OVERRIDE)
	return TRUE

/obj/machinery/ship_lockbox/proc/finish_door_motion()
	var/finished = door_motion
	door_motion = null
	if(finished == "opening" && !is_broken())
		door_open = TRUE
	update_appearance()
	if(finished == "closing")
		on_door_closed()

/// Hook for whatever follows the door shutting.
/obj/machinery/ship_lockbox/proc/on_door_closed()
	return

// --- Interaction ------------------------------------------------------------

/obj/machinery/ship_lockbox/interact(mob/user)
	if(door_motion)
		return
	if(is_accessible())
		ui_interact(user)
		return
	if(is_locked())
		alert_user(user, "locked!")
		return
	open_door(user)

/obj/machinery/ship_lockbox/attack_hand_secondary(mob/user, list/modifiers)
	. = ..()
	if(. == SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN)
		return
	close_door(user)
	return SECONDARY_ATTACK_CANCEL_ATTACK_CHAIN

/obj/machinery/ship_lockbox/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	var/obj/item/card/id/card = tool.GetID()
	if(card)
		INVOKE_ASYNC(src, PROC_REF(prompt_unlock), user, card)
		return ITEM_INTERACT_SUCCESS
	if(user.combat_mode)
		return NONE
	// Left to the tool acts, so the panel can be worked with the door open.
	if(tool.tool_behaviour in list(TOOL_SCREWDRIVER, TOOL_CROWBAR, TOOL_WRENCH))
		return NONE
	if(!is_raised() || !is_accessible())
		alert_user(user, "closed!")
		return ITEM_INTERACT_BLOCKING
	return deposit(tool, user) ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING

/obj/machinery/ship_lockbox/screwdriver_act(mob/living/user, obj/item/tool)
	if(!is_accessible())
		alert_user(user, "locked!")
		return ITEM_INTERACT_BLOCKING
	if(default_deconstruction_screwdriver(user, icon_state, icon_state, tool))
		update_appearance()
		return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_BLOCKING

/obj/machinery/ship_lockbox/crowbar_act(mob/living/user, obj/item/tool)
	if(!is_accessible())
		alert_user(user, "locked!")
		return ITEM_INTERACT_BLOCKING
	return default_deconstruction_crowbar(tool) ? ITEM_INTERACT_SUCCESS : ITEM_INTERACT_BLOCKING

/// Everything it holds is built at its feet, the way a smartfridge spills.
/obj/machinery/ship_lockbox/on_deconstruction(disassembled)
	spill_entries()

/obj/machinery/ship_lockbox/proc/spill_entries()
	var/atom/spill_at = drop_location()
	for(var/list/entry as anything in stored_entries)
		shipyard_restore_roster_entry(entry, spill_at)
	stored_entries.Cut()

// --- ID and PIN ---------------------------------------------------------------

/obj/machinery/ship_lockbox/proc/prompt_unlock(mob/user, obj/item/card/id/card)
	if(!is_locked())
		attempt_unlock(user, card, null)
		return
	if(!is_operational || in_lockout())
		attempt_unlock(user, card, null)
		return
	var/pin = tgui_input_number(user, "Enter your PIN.", name, max_value = ATM_PIN_MAX, min_value = ATM_PIN_MIN)
	if(isnull(pin) || QDELETED(src) || !user.can_perform_action(src, FORBID_TELEKINESIS_REACH))
		return
	attempt_unlock(user, card, pin)

/**
 * Unlock for the hull's owner, presenting their own ID and their ledger PIN -
 * the same pairing the ATM asks for. All of it has to hold, and a failure
 * does not say which part failed.
 */
/obj/machinery/ship_lockbox/proc/attempt_unlock(mob/user, obj/item/card/id/card, pin)
	if(!is_operational)
		alert_user(user, "no power!")
		return FALSE
	if(in_lockout())
		alert_user(user, "locked out!")
		playsound(src, 'sound/machines/terminal/terminal_error.ogg', 50, TRUE)
		return FALSE
	if(!is_locked())
		on_unlocked(user)
		return TRUE
	var/mob/living/carbon/human/human = user
	if(!istype(human) || human.mind?.character_uuid != hull_owner() || !personal_id_matches(human, card) || !atm_pin_matches(human, pin))
		refuse_unlock(user)
		return FALSE
	failed_attempts = 0
	locked = FALSE
	playsound(src, 'sound/machines/terminal/terminal_on.ogg', 50, TRUE)
	flash_screen("correct")
	on_unlocked(user)
	return TRUE

/// Hook for whatever follows a successful swipe.
/obj/machinery/ship_lockbox/proc/on_unlocked(mob/user)
	return

/obj/machinery/ship_lockbox/proc/refuse_unlock(mob/user)
	alert_user(user, "access denied!")
	playsound(src, 'sound/machines/terminal/terminal_error.ogg', 50, TRUE)
	failed_attempts++
	if(failed_attempts < LOCKBOX_MAX_ATTEMPTS)
		flash_screen("incorrect")
		return
	failed_attempts = 0
	lockout_until = world.time + LOCKBOX_LOCKOUT_TIME
	screen_flash = null
	update_appearance()
	addtimer(CALLBACK(src, TYPE_PROC_REF(/atom, update_appearance)), LOCKBOX_LOCKOUT_TIME + 1, TIMER_UNIQUE | TIMER_OVERRIDE)

// --- Storage ----------------------------------------------------------------

/**
 * Why `item` cannot go into the vault, or null when it can.
 *
 * Anything that is someone, or that carries who someone is, stays out: living
 * things and minds, ID cards and PDAs. So do high-risk steal targets, and other
 * one-of-a-kind things that would be duplicated or kept out of play by a vault
 * that outlives the round.
 */
/obj/machinery/ship_lockbox/proc/lockbox_refusal(obj/item/item)
	if((item.item_flags & ABSTRACT) || (item.flags_1 & HOLOGRAM_1) || HAS_TRAIT(item, TRAIT_NODROP))
		return "won't take that"
	for(var/atom/movable/thing as anything in item.get_all_contents())
		var/held_in = thing == item ? "" : " inside \the [item]"
		if(ismob(thing))
			return "won't take \the [thing][held_in]"
		if(istype(thing, /obj/item/card/id) || istype(thing, /obj/item/modular_computer/pda))
			return "won't take \the [thing][held_in]"
		if(lockbox_high_risk_paths()[thing.type])
			return "won't take \the [thing][held_in]"
		if(thing.GetComponent(/datum/component/stationloving) || thing.GetComponent(/datum/component/uplink))
			return "won't take \the [thing][held_in]"
		if(thing.resistance_flags & INDESTRUCTIBLE)
			return "won't take \the [thing][held_in]"
	return null

/**
 * Exact item types any steal objective can name. Traitor and spy targets are
 * everyday kit (lasers, batons, insulated gloves) and stay storable. Abstract
 * objective types that never pick their own target are skipped, and the
 * functional-AI objective is covered by refusing mobs.
 */
/proc/lockbox_high_risk_paths()
	var/static/list/paths
	if(paths)
		return paths
	paths = list()
	for(var/datum/objective_item/objective as anything in subtypesof(/datum/objective_item))
		if(initial(objective.objective_type) != OBJECTIVE_ITEM_TYPE_NORMAL)
			continue
		if(ispath(objective, /datum/objective_item/steal/functionalai))
			continue
		var/datum/objective_item/parent = type2parent(objective)
		if(initial(objective.targetitem) == initial(parent.targetitem))
			continue
		paths[initial(objective.targetitem)] = TRUE
	return paths

/// Write `item` down and delete it. `user` is whoever is handing it over, if anyone.
/obj/machinery/ship_lockbox/proc/deposit(obj/item/item, mob/user)
	if(length(stored_entries) >= max_entries)
		alert_user(user, "no space!")
		return FALSE
	var/refusal = lockbox_refusal(item)
	if(refusal)
		alert_user(user, refusal)
		return FALSE
	var/list/entry = shipyard_roster_entry(item)
	entry["value"] = shipyard_appraise_item(item)
	if(user && item.loc == user && !user.temporarilyRemoveItemFromInventory(item))
		alert_user(user, "stuck to your hand!")
		return FALSE
	stored_entries += list(entry)
	user?.visible_message(span_notice("[user] puts \the [item] into \the [src]."), span_notice("You put \the [item] into \the [src]."))
	qdel(item)
	playsound(src, 'sound/machines/click.ogg', 30, TRUE)
	SStgui.update_uis(src)
	return TRUE

/// Rows that differ in anything but their appraisal are listed apart.
/obj/machinery/ship_lockbox/proc/entry_key(list/entry)
	var/list/keyed = entry.Copy()
	keyed -= "value"
	return "[entry["name"]]|[md5(json_encode(keyed))]"

/// Build up to `amount` entries listed under `key` and hand them to `user`.
/obj/machinery/ship_lockbox/proc/withdraw(key, amount, mob/user)
	var/released = 0
	for(var/list/entry as anything in stored_entries.Copy())
		if(released >= amount)
			break
		if(entry_key(entry) != key)
			continue
		stored_entries -= list(entry)
		var/obj/item/built = shipyard_restore_roster_entry(entry, drop_location())
		released++
		if(!built)
			continue
		if(!user?.put_in_hands(built))
			adjust_item_drop_location(built)
		use_energy(active_power_usage)
	if(released)
		playsound(src, 'sound/machines/click.ogg', 30, TRUE)
		SStgui.update_uis(src)
	return released

/obj/machinery/ship_lockbox/ui_interact(mob/user, datum/tgui/ui)
	if(!is_accessible())
		return
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "SmartVend", name)
		ui.set_autoupdate(FALSE)
		ui.open()

/obj/machinery/ship_lockbox/ui_status(mob/user, datum/ui_state/state)
	if(!is_accessible())
		return UI_CLOSE
	return ..()

/obj/machinery/ship_lockbox/ui_data(mob/user)
	var/list/rows = list()
	for(var/list/entry as anything in stored_entries)
		var/key = entry_key(entry)
		if(rows[key])
			rows[key]["amount"]++
			continue
		var/obj/item/path = entry["path"]
		if(istext(path))
			path = text2path(path)
		var/row_name = full_capitalize(entry["name"] || "unknown item")
		if(isnum(entry["amount"]))
			row_name += " ([entry["amount"]])"
		rows[key] = list(
			"path" = key,
			"name" = row_name,
			"icon" = ispath(path) ? initial(path.icon) : null,
			"icon_state" = ispath(path) ? (initial(path.post_init_icon_state) || initial(path.icon_state)) : null,
			"amount" = 1,
		)
	return list(
		"contents" = sort_list(rows),
		"name" = name,
		"isdryer" = FALSE,
	)

/obj/machinery/ship_lockbox/ui_act(action, params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(. || !ui.user.can_perform_action(src, FORBID_TELEKINESIS_REACH))
		return
	if(action != "Release")
		return FALSE
	if(isAI(ui.user))
		to_chat(ui.user, span_warning("[src] does not respect your authority!"))
		return TRUE
	if(!is_accessible())
		return TRUE
	var/amount = text2num(params["amount"])
	if(!isnum(amount) || amount <= 0)
		return TRUE
	withdraw(params["path"], amount, ui.user)
	return TRUE

// --- Sprites ----------------------------------------------------------------

/obj/machinery/ship_lockbox/update_icon_state()
	icon_state = "[skin]-base"
	return ..()

/obj/machinery/ship_lockbox/update_overlays()
	. = ..()
	. += body_overlays()

/// Door and screen. A floor vault draws something else while it is down.
/obj/machinery/ship_lockbox/proc/body_overlays()
	. = list(door_overlay())
	var/screen = screen_state()
	if(screen)
		. += mutable_appearance(icon, "[overlay_prefix]-screen-[screen]")
		. += emissive_appearance(icon, "[overlay_prefix]-screen-[screen]", src, alpha = src.alpha)

/obj/machinery/ship_lockbox/proc/door_overlay()
	if(is_broken())
		return "[overlay_prefix]-overlay-door-broken"
	if(door_motion)
		return "[overlay_prefix]-overlay-[door_motion]"
	if(door_open)
		return "[overlay_prefix]-overlay-open"
	return "[overlay_prefix]-overlay-door"

/// The screen state to draw, or null for a dark screen.
/obj/machinery/ship_lockbox/proc/screen_state()
	if(is_broken())
		return "broken"
	if(!is_operational)
		return screen_flash == "off" ? "off" : null
	if(screen_flash)
		return screen_flash
	if(in_lockout())
		return "warning"
	return is_locked() ? "locked" : "unlocked"

// --- Floor vault ------------------------------------------------------------

/**
 * Sits flush with the deck, walkable, until its owner raises it. Closing the
 * door locks it and sends it back down.
 */
/obj/machinery/ship_lockbox/floor
	icon_state = "vault"
	circuit = /obj/item/circuitboard/machine/ship_lockbox
	density = FALSE
	layer = LOW_OBJ_LAYER
	skin = "vault"
	overlay_prefix = "vault"
	var/raised = FALSE
	/// "ascend" or "descend" while it moves.
	var/motion

/obj/machinery/ship_lockbox/floor/Initialize(mapload)
	animation_lengths = animation_lengths.Copy()
	animation_lengths["ascend"] = 0.9 SECONDS
	animation_lengths["descend"] = 0.9 SECONDS
	return ..()

/obj/machinery/ship_lockbox/floor/is_raised()
	return raised && !motion

/obj/machinery/ship_lockbox/floor/interact(mob/user)
	if(motion)
		return
	if(!raised)
		if(is_locked())
			alert_user(user, "locked!")
			return
		rise(user)
		return
	return ..()

/obj/machinery/ship_lockbox/floor/on_unlocked(mob/user)
	rise(user)

/obj/machinery/ship_lockbox/floor/on_door_closed()
	lower()

/// Come up out of the deck, if nothing is standing in the way.
/obj/machinery/ship_lockbox/floor/proc/rise(mob/user)
	if(raised || motion)
		return FALSE
	if(!is_operational && !is_broken())
		alert_user(user, "no power!")
		return FALSE
	for(var/atom/movable/thing in loc)
		if(thing != src && thing.density)
			alert_user(user, "[thing] is in the way!")
			return FALSE
	motion = "ascend"
	set_density(TRUE)
	layer = BELOW_OBJ_LAYER
	update_appearance()
	addtimer(CALLBACK(src, PROC_REF(finish_motion)), animation_lengths["ascend"], TIMER_UNIQUE | TIMER_OVERRIDE)
	return TRUE

/obj/machinery/ship_lockbox/floor/proc/lower()
	if(!raised || motion || door_open || door_motion)
		return FALSE
	motion = "descend"
	update_appearance()
	addtimer(CALLBACK(src, PROC_REF(finish_motion)), animation_lengths["descend"], TIMER_UNIQUE | TIMER_OVERRIDE)
	return TRUE

/obj/machinery/ship_lockbox/floor/proc/finish_motion()
	var/finished = motion
	motion = null
	if(finished == "ascend")
		raised = TRUE
	else if(finished == "descend")
		raised = FALSE
		set_density(FALSE)
		layer = LOW_OBJ_LAYER
	update_appearance()

/obj/machinery/ship_lockbox/floor/update_icon_state()
	. = ..()
	if(motion)
		icon_state = "[skin]-base-[motion]"
	else if(!raised)
		icon_state = ""

/obj/machinery/ship_lockbox/floor/body_overlays()
	if(motion)
		return list("vault-overlay-[motion]", "vault-overlay-floor-[motion]")
	if(!raised)
		return list("vault-overlay-floor-ground")
	. = ..()
	. += "vault-overlay-floor-rised"
	. += "vault-overlay-computer"
	if(panel_open)
		. += "vault-overlay-computer-panel"

/obj/machinery/ship_lockbox/floor/gold
	icon_state = "vault_gold"
	skin = "vault_gold"

/obj/machinery/ship_lockbox/floor/syndicate
	icon_state = "vault_syndicate"
	skin = "vault_syndicate"

/obj/machinery/ship_lockbox/floor/cargo
	icon_state = "vault_cargo"
	skin = "vault_cargo"

/obj/item/circuitboard/machine/ship_lockbox
	name = "Ship Lockbox"
	desc = "A machine board for a deck-mounted ship lockbox."
	greyscale_colors = CIRCUIT_COLOR_SUPPLY
	build_path = /obj/machinery/ship_lockbox/floor
	req_components = list(
		/datum/stock_part/matter_bin = 1,
		/obj/item/stack/sheet/plasteel = 2,
	)

// --- Wall vault -------------------------------------------------------------

/obj/machinery/ship_lockbox/wall
	icon_state = "vault_wall"
	skin = "vault_wall"
	overlay_prefix = "vault_wall"
	/// Whether the panel cover is playing its one-shot.
	var/panel_flash = FALSE

/obj/machinery/ship_lockbox/wall/Initialize(mapload)
	animation_lengths = animation_lengths.Copy()
	animation_lengths["opening"] = 0.79 SECONDS
	animation_lengths["closing"] = 0.79 SECONDS
	animation_lengths["incorrect"] = 0.79 SECONDS
	animation_lengths["panel_cover"] = 0.5 SECONDS
	. = ..()
	if(mapload)
		find_and_mount_on_atom()

/obj/machinery/ship_lockbox/wall/screwdriver_act(mob/living/user, obj/item/tool)
	. = ..()
	if(. != ITEM_INTERACT_SUCCESS || !panel_open)
		return
	panel_flash = TRUE
	update_appearance()
	addtimer(CALLBACK(src, PROC_REF(end_panel_flash)), animation_lengths["panel_cover"], TIMER_UNIQUE | TIMER_OVERRIDE)

/obj/machinery/ship_lockbox/wall/proc/end_panel_flash()
	panel_flash = FALSE
	update_appearance()

/obj/machinery/ship_lockbox/wall/crowbar_act(mob/living/user, obj/item/tool)
	return NONE

/obj/machinery/ship_lockbox/wall/wrench_act(mob/living/user, obj/item/tool)
	if(!is_accessible())
		alert_user(user, "locked!")
		return ITEM_INTERACT_BLOCKING
	if(!panel_open)
		alert_user(user, "open the panel first!")
		return ITEM_INTERACT_BLOCKING
	alert_user(user, "unmounting...")
	if(!tool.use_tool(src, user, 3 SECONDS, volume = 50))
		return ITEM_INTERACT_BLOCKING
	deconstruct(TRUE)
	return ITEM_INTERACT_SUCCESS

/obj/machinery/ship_lockbox/wall/on_deconstruction(disassembled)
	. = ..()
	if(disassembled)
		new /obj/item/wallframe/ship_lockbox(drop_location())

/obj/machinery/ship_lockbox/wall/body_overlays()
	. = ..()
	if(panel_open)
		. += "vault_wall-overlay-door-panel"
	if(panel_flash)
		. += "vault_wall_panel_cover"

/obj/machinery/ship_lockbox/wall/gold
	icon_state = "vault_wall_gold"
	skin = "vault_wall_gold"

/obj/machinery/ship_lockbox/wall/syndicate
	icon_state = "vault_wall_syndicate"
	skin = "vault_wall_syndicate"

/obj/machinery/ship_lockbox/wall/cargo
	icon_state = "vault_wall_cargo"
	skin = "vault_wall_cargo"

MAPPING_DIRECTIONAL_HELPERS(/obj/machinery/ship_lockbox/wall, 32)
MAPPING_DIRECTIONAL_HELPERS(/obj/machinery/ship_lockbox/wall/gold, 32)
MAPPING_DIRECTIONAL_HELPERS(/obj/machinery/ship_lockbox/wall/syndicate, 32)
MAPPING_DIRECTIONAL_HELPERS(/obj/machinery/ship_lockbox/wall/cargo, 32)

/obj/item/wallframe/ship_lockbox
	name = "unmounted ship lockbox"
	desc = "A wall vault for a ship's lockbox, ready to be mounted."
	icon = 'modular_nova/modules/overmap/icons/vaults.dmi'
	icon_state = "vault_wall"
	w_class = WEIGHT_CLASS_BULKY
	result_path = /obj/machinery/ship_lockbox/wall
	pixel_shift = 32
	custom_materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2,
		/datum/material/alloy/plasteel = SHEET_MATERIAL_AMOUNT * 2,
	)

// --- Legacy -----------------------------------------------------------------

/**
 * The lockbox before it was a vault. Saved ship maps still name it, so it
 * stays defined: it puts a floor vault on its tile, hands over anything it
 * holds as entries, and removes itself.
 */
/obj/structure/closet/secure_closet/ship_lockbox
	name = "ship lockbox"
	locked = FALSE

/obj/structure/closet/secure_closet/ship_lockbox/Initialize(mapload)
	. = ..()
	var/obj/machinery/ship_lockbox/floor/vault = new(loc)
	for(var/obj/item/held in src)
		vault.stored_entries += list(shipyard_roster_entry(held))
		qdel(held)
	return INITIALIZE_HINT_QDEL

#undef LOCKBOX_MAX_ATTEMPTS
#undef LOCKBOX_LOCKOUT_TIME
