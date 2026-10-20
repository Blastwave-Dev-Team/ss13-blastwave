// MODULE ID: OVERMAP
// Power, atmospherics, reagents and ammunition: the state that, left behind,
// turns filing a ship or using its lockbox into a free refill.

// --- Power ------------------------------------------------------------------

/datum/shipyard_serdes/item/power_store
	target_type = /obj/item/stock_parts/power_store
	saved_vars = list("charge")

/datum/shipyard_serdes/item/power_store/apply(obj/item/stock_parts/power_store/target, list/state)
	if(isnum(state["charge"]))
		state = state.Copy()
		state["charge"] = clamp(state["charge"], 0, target.maxcharge)
	return ..()

/**
 * An SMES keeps its charge in the cells it was built from, so charge is read as
 * their sum and handed back across them. The machine parts helper has already
 * installed those cells by the time this runs.
 */
/datum/shipyard_serdes/smes
	target_type = /obj/machinery/power/smes

/datum/shipyard_serdes/smes/capture(obj/machinery/power/smes/target)
	var/stored = 0
	for(var/obj/item/stock_parts/power_store/power_cell in target.component_parts)
		stored += power_cell.charge()
	return list(
		"charge" = stored,
		"input_level" = target.input_level,
		"output_level" = target.output_level,
		"input_attempt" = target.input_attempt,
		"output_attempt" = target.output_attempt,
	)

/datum/shipyard_serdes/smes/apply(obj/machinery/power/smes/target, list/state)
	if(isnum(state["charge"]))
		var/remaining = max(state["charge"], 0)
		for(var/obj/item/stock_parts/power_store/power_cell in target.component_parts)
			var/held = min(remaining, power_cell.max_charge())
			power_cell.charge = held
			remaining -= held
	if(isnum(state["input_level"]))
		target.input_level = clamp(state["input_level"], 0, target.input_level_max)
	if(isnum(state["output_level"]))
		target.output_level = clamp(state["output_level"], 0, target.output_level_max)
	if(!isnull(state["input_attempt"]))
		target.input_attempt = !!state["input_attempt"]
	if(!isnull(state["output_attempt"]))
		target.output_attempt = !!state["output_attempt"]
	return ..()

/// An APC rebuilds its cell from `cell_type`; only the charge needs carrying.
/datum/shipyard_serdes/apc
	target_type = /obj/machinery/power/apc

/datum/shipyard_serdes/apc/capture(obj/machinery/power/apc/target)
	if(!target.cell)
		return null
	return list("cell_charge" = target.cell.charge)

/datum/shipyard_serdes/apc/apply(obj/machinery/power/apc/target, list/state)
	if(target.cell && isnum(state["cell_charge"]))
		target.cell.charge = clamp(state["cell_charge"], 0, target.cell.maxcharge)
	return ..()

// --- Atmospherics -----------------------------------------------------------

/datum/shipyard_serdes/portable_atmospherics
	target_type = /obj/machinery/portable_atmospherics

/datum/shipyard_serdes/portable_atmospherics/capture(obj/machinery/portable_atmospherics/target)
	var/list/state = list("gas" = shipyard_capture_gas(target.air_contents))
	if(target.holding)
		state["holding"] = shipyard_roster_entry(target.holding)
	return state

/datum/shipyard_serdes/portable_atmospherics/apply(obj/machinery/portable_atmospherics/target, list/state)
	if(islist(state["gas"]))
		shipyard_apply_gas(target.air_contents, state["gas"])
	var/list/held_entry = state["holding"]
	if(target.holding && (!islist(held_entry) || target.holding.type != text2path("[held_entry["path"]]")))
		qdel(target.holding)
	if(islist(held_entry))
		if(!target.holding)
			var/obj/item/tank/held = shipyard_restore_roster_entry(held_entry, target)
			if(istype(held))
				target.holding = held
				target.RegisterSignal(held, COMSIG_QDELETING, TYPE_PROC_REF(/obj/machinery/portable_atmospherics, unregister_holding))
			else if(held)
				qdel(held)
		else
			shipyard_apply_state(target.holding, held_entry["state"])
	return ..()

/datum/shipyard_serdes/portable_atmospherics/canister
	target_type = /obj/machinery/portable_atmospherics/canister

/datum/shipyard_serdes/portable_atmospherics/canister/capture(obj/machinery/portable_atmospherics/canister/target)
	var/list/state = ..()
	state["release_pressure"] = target.release_pressure
	state["valve_open"] = target.valve_open
	return state

/datum/shipyard_serdes/portable_atmospherics/canister/apply(obj/machinery/portable_atmospherics/canister/target, list/state)
	if(isnum(state["release_pressure"]))
		target.release_pressure = clamp(state["release_pressure"], CAN_MIN_RELEASE_PRESSURE, CAN_MAX_RELEASE_PRESSURE)
	if(!isnull(state["valve_open"]))
		target.valve_open = !!state["valve_open"]
	return ..()

/datum/shipyard_serdes/item/tank
	target_type = /obj/item/tank

/datum/shipyard_serdes/item/tank/capture(obj/item/tank/target)
	var/list/state = ..() || list()
	if(target.air_contents)
		state["gas"] = shipyard_capture_gas(target.air_contents)
	return length(state) ? state : null

/datum/shipyard_serdes/item/tank/apply(obj/item/tank/target, list/state)
	if(islist(state["gas"]) && target.air_contents)
		shipyard_apply_gas(target.air_contents, state["gas"])
	return ..()

// --- Reagents ---------------------------------------------------------------

/datum/shipyard_serdes/reagent_dispenser
	target_type = /obj/structure/reagent_dispensers

/datum/shipyard_serdes/reagent_dispenser/capture(obj/structure/reagent_dispensers/target)
	if(!target.reagents)
		return null
	return list("reagents" = shipyard_capture_reagents(target.reagents))

/datum/shipyard_serdes/reagent_dispenser/apply(obj/structure/reagent_dispensers/target, list/state)
	if(islist(state["reagents"]) && target.reagents)
		shipyard_apply_reagents(target.reagents, state["reagents"])
	return ..()

// --- Ammunition -------------------------------------------------------------

/**
 * A magazine or box keeps its live rounds, in order, by casing type. Spent
 * casings are not kept, and an empty cylinder chamber comes back empty.
 */
/datum/shipyard_serdes/item/ammo_box
	target_type = /obj/item/ammo_box

/datum/shipyard_serdes/item/ammo_box/capture(obj/item/ammo_box/target)
	var/list/state = ..() || list()
	state["rounds"] = shipyard_capture_rounds(target)
	return state

/datum/shipyard_serdes/item/ammo_box/apply(obj/item/ammo_box/target, list/state)
	if(islist(state["rounds"]))
		shipyard_apply_rounds(target, state["rounds"])
	return ..()

/proc/shipyard_capture_rounds(obj/item/ammo_box/box)
	var/list/rounds = list()
	for(var/casing in box.stored_ammo)
		if(ispath(casing, /obj/item/ammo_casing))
			rounds += "[casing]"
			continue
		var/obj/item/ammo_casing/loaded = casing
		if(istype(loaded) && loaded.loaded_projectile)
			rounds += "[loaded.type]"
	return rounds

/// Empty a box and load it with saved rounds. Loading goes through
/// `give_round()`, so its materials follow what is actually in it.
/proc/shipyard_apply_rounds(obj/item/ammo_box/box, list/rounds)
	for(var/obj/item/ammo_casing/casing in box.ammo_list())
		qdel(casing)
	box.stored_ammo.Cut()
	// A cylinder is a fixed ring of chambers, with nulls for the empty ones, and
	// only loads into a chamber that is already there.
	if(istype(box, /obj/item/ammo_box/magazine/internal/cylinder))
		box.stored_ammo.len = box.max_ammo
	for(var/path_text in rounds)
		var/casing_path = text2path("[path_text]")
		if(!ispath(casing_path, /obj/item/ammo_casing))
			continue
		var/obj/item/ammo_casing/casing = new casing_path(box)
		if(!box.give_round(casing))
			qdel(casing)
	box.update_appearance()

/**
 * A ballistic gun keeps its magazine, the round in its chamber and its bolt.
 *
 * Only a round the gun has actually taken in counts as chambered. An open bolt
 * or a revolver leaves its next round in the magazine, which already counts it.
 */
/datum/shipyard_serdes/item/ballistic_gun
	target_type = /obj/item/gun/ballistic

/datum/shipyard_serdes/item/ballistic_gun/capture(obj/item/gun/ballistic/target)
	var/list/state = ..() || list()
	if(target.magazine)
		state["magazine"] = list(
			"path" = "[target.magazine.type]",
			"rounds" = shipyard_capture_rounds(target.magazine),
		)
	var/obj/item/ammo_casing/chambered = target.chambered
	if(istype(chambered) && chambered.loc == target && chambered.loaded_projectile)
		state["chambered"] = "[chambered.type]"
	state["bolt_locked"] = target.bolt_locked
	return state

/datum/shipyard_serdes/item/ballistic_gun/apply(obj/item/gun/ballistic/target, list/state)
	var/obj/item/ammo_casing/old_chambered = target.chambered
	if(istype(old_chambered))
		if(old_chambered.loc == target)
			qdel(old_chambered)
		else
			target.UnregisterSignal(old_chambered, COMSIG_MOVABLE_MOVED)
		target.chambered = null

	var/list/saved_magazine = state["magazine"]
	if(!target.internal_magazine)
		var/magazine_path = islist(saved_magazine) ? text2path("[saved_magazine["path"]]") : null
		if(target.magazine && target.magazine.type != magazine_path)
			var/obj/item/ammo_box/magazine/old_magazine = target.magazine
			target.magazine = null
			qdel(old_magazine)
		if(!target.magazine && ispath(magazine_path, target.accepted_magazine_type))
			target.magazine = new magazine_path(target)
	if(target.magazine && islist(saved_magazine))
		shipyard_apply_rounds(target.magazine, saved_magazine["rounds"])

	if(!isnull(state["bolt_locked"]))
		target.bolt_locked = !!state["bolt_locked"]
	var/chambered_path = text2path("[state["chambered"]]")
	if(ispath(chambered_path, /obj/item/ammo_casing))
		target.chambered = new chambered_path(target)
	else if(target.bolt_type == BOLT_TYPE_NO_BOLT || (target.bolt_type == BOLT_TYPE_OPEN && !target.bolt_locked))
		target.chamber_round()
	return ..()
