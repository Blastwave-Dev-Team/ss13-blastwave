// MODULE ID: OVERMAP
// Runtime state a filed ship keeps: what is written on a paper, how much charge
// a cell holds, what gas is in a canister. `shipyard_describe` records the shape
// a blueprint can express; this records the contents it cannot, and keeps them
// out of the saved map so the printer never sees them.
//
// Not built on upstream get_save_vars()/on_object_saved(): both emit map-file
// vars, so they would leak state into blueprints and through the encoder's
// string stripping.

GLOBAL_LIST_INIT(shipyard_serdes, build_shipyard_serdes_registry())

/proc/build_shipyard_serdes_registry()
	var/list/registry = list()
	for(var/serdes_type in subtypesof(/datum/shipyard_serdes))
		var/datum/shipyard_serdes/serdes = new serdes_type
		if(!serdes.target_type)
			continue
		if(registry[serdes.target_type])
			stack_trace("Duplicate shipyard serdes for [serdes.target_type].")
			continue
		registry[serdes.target_type] = serdes
	return registry

/// Nearest-ancestor serdes lookup, the same way construction routes resolve.
/proc/get_shipyard_serdes(target_type)
	var/list/registry = GLOB.shipyard_serdes
	while(target_type)
		var/datum/shipyard_serdes/serdes = registry[target_type]
		if(serdes)
			return serdes
		target_type = type2parent(target_type)
	return null

/// JSON-safe state for `target`, or null when it has nothing worth keeping.
/proc/shipyard_capture_state(atom/target)
	var/datum/shipyard_serdes/serdes = get_shipyard_serdes(target.type)
	return serdes?.capture(target)

/proc/shipyard_apply_state(atom/target, list/state)
	if(!islist(state))
		return
	var/datum/shipyard_serdes/serdes = get_shipyard_serdes(target.type)
	serdes?.apply(target, state)

/// Whether a loose or locker item stays aboard a filed ship.
/proc/shipyard_keeps_aboard(atom/target)
	var/datum/shipyard_serdes/serdes = get_shipyard_serdes(target.type)
	return serdes?.keeps_aboard

/**
 * How one type's runtime state is written down and read back.
 *
 * State is text, numbers and lists only. Paths go in as text, because that is
 * what they come back out of JSON as.
 */
/datum/shipyard_serdes
	/// Type this handles; subtypes of it use this unless they have their own.
	var/target_type
	/// Vars copied as-is, for types with no other state.
	var/list/saved_vars = list()
	/// Whether a loose or locker item of this type is kept when its ship is filed.
	var/keeps_aboard = FALSE

/datum/shipyard_serdes/proc/capture(atom/target)
	if(!length(saved_vars))
		return null
	var/list/state = list()
	for(var/var_name in saved_vars)
		var/value = target.vars[var_name]
		state[var_name] = shipyard_copy_state(value)
	return state

/datum/shipyard_serdes/proc/apply(atom/target, list/state)
	for(var/var_name in saved_vars)
		if(var_name in state)
			target.vars[var_name] = state[var_name]
	target.update_appearance()

/**
 * Every item: a custom name, the charge of the cell it runs on, and whatever
 * reagents it holds.
 *
 * This is what stops a lockbox being a refill machine for the common cases - a
 * drained energy gun, a half-empty extinguisher, a sprayer - without a saver
 * per type. An item's reagents are kept even when empty, since empty is
 * exactly the state a fresh one would not come back in.
 */
/datum/shipyard_serdes/item
	target_type = /obj/item

/datum/shipyard_serdes/item/capture(obj/item/target)
	var/list/state = ..() || list()
	if(target.name != initial(target.name))
		state["name"] = target.name
	var/obj/item/stock_parts/power_store/cell = target.get_cell()
	if(istype(cell) && cell != target)
		state["cell_charge"] = cell.charge
	if(target.reagents)
		state["reagents"] = shipyard_capture_reagents(target.reagents)
	return length(state) ? state : null

/datum/shipyard_serdes/item/apply(obj/item/target, list/state)
	if(istext(state["name"]))
		target.name = state["name"]
	if(isnum(state["cell_charge"]))
		var/obj/item/stock_parts/power_store/cell = target.get_cell()
		if(istype(cell) && cell != target)
			cell.charge = clamp(state["cell_charge"], 0, cell.maxcharge)
			cell.update_appearance()
	if(islist(state["reagents"]) && target.reagents)
		shipyard_apply_reagents(target.reagents, state["reagents"])
	return ..()

// --- Shared encodings -------------------------------------------------------

/// Reagent type to volume and purity, plus the holder's temperature.
/proc/shipyard_capture_reagents(datum/reagents/holder)
	var/list/volumes = list()
	var/list/purities = list()
	for(var/datum/reagent/reagent as anything in holder.reagent_list)
		volumes["[reagent.type]"] = reagent.volume
		purities["[reagent.type]"] = reagent.purity
	return list("volumes" = volumes, "purities" = purities, "temperature" = holder.chem_temp)

/**
 * Put saved reagents back, replacing whatever the holder started with.
 *
 * Added without reacting and at the saved temperature: this is a mixture that
 * already settled once, and re-adding it a reagent at a time would otherwise
 * set off reactions partway through. Reagent `data`, such as blood DNA, is not
 * kept.
 */
/proc/shipyard_apply_reagents(datum/reagents/holder, list/saved)
	holder.clear_reagents()
	var/temperature = isnum(saved["temperature"]) ? saved["temperature"] : DEFAULT_REAGENT_TEMPERATURE
	var/list/volumes = saved["volumes"]
	var/list/purities = saved["purities"]
	for(var/path_text in volumes)
		var/reagent_path = text2path("[path_text]")
		var/volume = volumes[path_text]
		if(!ispath(reagent_path, /datum/reagent) || !isnum(volume) || volume <= 0)
			continue
		var/purity = islist(purities) && isnum(purities[path_text]) ? purities[path_text] : null
		holder.add_reagent(reagent_path, volume, reagtemp = temperature, added_purity = purity, no_react = TRUE)
	holder.set_temperature(temperature)

/// Gas type to moles, plus temperature.
/proc/shipyard_capture_gas(datum/gas_mixture/air)
	var/list/moles = list()
	for(var/gas_path in air.gases)
		var/amount = air.gases[gas_path][MOLES]
		if(amount > 0)
			moles["[gas_path]"] = amount
	return list("moles" = moles, "temperature" = air.temperature)

/**
 * Replace a mixture's contents with saved ones.
 *
 * Set mole by mole rather than through SSair.parse_gas_string(), which caches
 * every distinct string it is handed for the rest of the round.
 */
/proc/shipyard_apply_gas(datum/gas_mixture/air, list/saved)
	for(var/gas_path in air.gases)
		air.gases[gas_path][MOLES] = 0
	var/list/moles = saved["moles"]
	for(var/path_text in moles)
		var/gas_path = text2path("[path_text]")
		var/amount = moles[path_text]
		if(!ispath(gas_path, /datum/gas) || !isnum(amount) || amount <= 0)
			continue
		ASSERT_GAS(gas_path, air)
		air.gases[gas_path][MOLES] = amount
	if(isnum(saved["temperature"]))
		air.temperature = max(saved["temperature"], TCMB)
	air.garbage_collect()

/**
 * Copy JSON-shaped state: plain lists of entries and assoc lists, nested.
 *
 * deep_copy_list() cannot be used for this. It treats every element of a plain
 * list as an assoc key, so a list of entries comes back with null associations
 * and json_encode() writes it as an object.
 */
/proc/shipyard_copy_state(value)
	if(!islist(value))
		return value
	var/list/source = value
	var/list/copy = list()
	for(var/index in 1 to length(source))
		var/key = source[index]
		if(islist(key))
			copy += list(shipyard_copy_state(key))
			continue
		var/associated = (isnull(key) || isnum(key)) ? null : source[key]
		if(isnull(associated))
			copy.len++
			copy[length(copy)] = key
		else
			copy[key] = shipyard_copy_state(associated)
	return copy

/// A list of roster entries for each item directly inside `holder`.
/proc/shipyard_roster_of(atom/holder, item_type = /obj/item)
	var/list/roster = list()
	for(var/obj/item/held in holder)
		if(istype(held, item_type))
			roster += list(shipyard_roster_entry(held))
	return roster
