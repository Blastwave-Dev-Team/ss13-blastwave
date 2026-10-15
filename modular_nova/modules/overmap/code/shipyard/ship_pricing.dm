// MODULE ID: OVERMAP
// What persistent ships cost to keep, and the ledger calls that charge for it.
//
// Every fee here is burned rather than paid to anyone. The order a caller runs
// is always quote, debit, act, commit: the ledger is charged before the ship is
// touched, and refunded if touching it fails, so a refusal never costs anything
// and a success is never free.

/datum/config_entry/number/ship_storage_base_fee
	default = 150
	integer = TRUE
	min_val = 0

/datum/config_entry/number/ship_storage_fee_per_tile
	default = 4
	integer = TRUE
	min_val = 0

/datum/config_entry/number/ship_lockbox_appraisal_rate
	default = 0.1
	integer = FALSE
	min_val = 0

/datum/config_entry/number/ship_lockbox_unvalued_floor
	default = 25
	integer = TRUE
	min_val = 0

/datum/config_entry/number/ship_insurance_salvage_multiplier
	default = 1.25
	integer = FALSE
	min_val = 1

/datum/config_entry/number/ship_uninsured_retrieve_fee
	default = 50
	integer = TRUE
	min_val = 0

/datum/config_entry/number/ship_scrap_rate
	default = 0.4
	integer = FALSE
	min_val = 0
	max_val = 1

/datum/config_entry/number/ship_registration_fee
	default = 150
	integer = TRUE
	min_val = 0

// --- Valuation --------------------------------------------------------------

/**
 * Material value of a saved hull, which is what insuring it is priced off.
 *
 * The saved file is parsed back into the same manifest a fabricator would build
 * from, so a ship is valued at what it would cost to print again rather than at
 * whatever happens to be standing on it. Materials are valued at their fixed
 * `value_per_unit` rather than the stock market, so a quote given at filing is
 * the quote the owner pays at the next retrieval.
 */
/proc/shipyard_salvage_estimate(file_path)
	if(!file_path || !fexists(file_path))
		return 0
	var/datum/map_template/shuttle/runtime/template = new(file_path)
	var/datum/ship_plan/template/plan = new(template)
	var/list/materials = plan.get_material_cost()
	var/list/parts = plan.get_required_parts()
	for(var/part_path in parts)
		var/list/part_cost = shipyard_dependency_material_cost(part_path, parts[part_path])
		for(var/material_path in part_cost)
			materials[material_path] = (materials[material_path] || 0) + part_cost[material_path]
	qdel(plan)
	qdel(template)
	return shipyard_material_value(materials)

/// Credits a material dictionary is worth at fixed prices.
/proc/shipyard_material_value(list/materials)
	var/total = 0
	for(var/datum/material/material_path as anything in materials)
		if(!ispath(material_path, /datum/material))
			continue
		total += materials[material_path] * initial(material_path.value_per_unit)
	return round(total)

/**
 * The lockbox roster, appraised item by item and grouped by name.
 *
 * A dry-run export prices each item the way the cargo shuttle would, contents
 * included. Anything export does not recognise still takes up a slot the
 * registry has to hold, so it is appraised at a flat floor rather than for free.
 * Returns `list("lines" = LockboxLine list, "total" = appraised value)`.
 */
/proc/shipyard_appraise_lockbox(list/obj/item/items)
	var/list/lines_by_name = list()
	var/total = 0
	var/floor_value = CONFIG_GET(number/ship_lockbox_unvalued_floor)
	for(var/obj/item/item as anything in items)
		if(QDELETED(item))
			continue
		var/datum/export_report/report = export_item_and_contents(item, apply_elastic = FALSE, delete_unsold = FALSE, dry_run = TRUE)
		var/value = 0
		for(var/export in report.total_value)
			value += report.total_value[export]
		var/floored = value <= 0
		if(floored)
			value = floor_value
		var/list/line = lines_by_name[item.name]
		if(!line)
			line = list("name" = item.name, "count" = 0, "appraisal" = 0, "floored" = FALSE)
			lines_by_name[item.name] = line
		line["count"] += 1
		line["appraisal"] += value
		line["floored"] = line["floored"] || floored
		total += value
	var/list/lines = list()
	for(var/name in lines_by_name)
		lines += list(lines_by_name[name])
	return list("lines" = lines, "total" = round(total))

// --- Quotes -----------------------------------------------------------------

/**
 * What filing a hull costs, itemised the way the registrar shows it.
 *
 * `insurance_refund` is what the checkout it came out on paid for insurance.
 * It offsets storage, and anything left over after that goes back to the owner,
 * so a negative `net` is a credit rather than a charge.
 */
/proc/shipyard_storage_quote(tile_count, lockbox_appraisal, insurance_refund = 0)
	var/base = CONFIG_GET(number/ship_storage_base_fee)
	var/tile_fee = tile_count * CONFIG_GET(number/ship_storage_fee_per_tile)
	var/lockbox_fee = round(lockbox_appraisal * CONFIG_GET(number/ship_lockbox_appraisal_rate))
	var/storage = base + tile_fee + lockbox_fee
	return list(
		"base" = base,
		"tileFee" = tile_fee,
		"lockboxFee" = lockbox_fee,
		"storage" = storage,
		"insuranceRefund" = insurance_refund,
		"net" = storage - insurance_refund,
	)

/// What an insured checkout of a hull worth `salvage_estimate` costs.
/proc/shipyard_insurance_fee(salvage_estimate)
	return round(salvage_estimate * CONFIG_GET(number/ship_insurance_salvage_multiplier))

/// What an uninsured checkout costs, which is a flat token.
/proc/shipyard_uninsured_fee()
	return CONFIG_GET(number/ship_uninsured_retrieve_fee)

/**
 * A stored lockbox roster appraised at today's prices.
 *
 * Priced again on every call rather than remembered from filing, so that an
 * export repricing moves what a stored ship is worth. Each item is stood up in
 * nullspace, contents and stack size included, just long enough to appraise.
 */
/proc/shipyard_appraise_roster(list/stored_contents)
	if(!length(stored_contents))
		return 0
	var/list/obj/item/stand_ins = list()
	for(var/list/entry as anything in stored_contents)
		var/obj/item/stand_in = shipyard_restore_roster_entry(entry, null)
		if(stand_in)
			stand_ins += stand_in
	var/list/appraisal = shipyard_appraise_lockbox(stand_ins)
	QDEL_LIST(stand_ins)
	return appraisal["total"]

/// What decommissioning a stored ship pays its owner.
/proc/shipyard_scrap_value(datum/player_ship_record/record)
	var/worth = record.salvage_estimate + shipyard_appraise_roster(record.stored_contents)
	return round(worth * CONFIG_GET(number/ship_scrap_rate), 10)

/// What printing a lost ship's rebuild blueprint costs: its storage fee, lockbox aside.
/proc/shipyard_blueprint_fee(datum/player_ship_record/record)
	var/list/quote = shipyard_storage_quote(record.tile_count, 0)
	return quote["storage"]

/// The retrieval price either way, for the garage list.
/proc/shipyard_retrieval_quote(datum/player_ship_record/record)
	return list(
		"insured" = shipyard_insurance_fee(record.salvage_estimate),
		"uninsured" = shipyard_uninsured_fee(),
	)

// --- Charging ---------------------------------------------------------------

/// Refunds issued per charge this round, which is what moves the idempotency key
/// on: a charge that was refunded has to be payable again, and a charge that was
/// not must never be paid twice.
GLOBAL_LIST_EMPTY(shipyard_fee_refunds)

/**
 * Idempotency key for one fee on one revision of one ship.
 *
 * Shaped `ship-<id>-r<rev>-<action>-<round>`, with an attempt suffix once a
 * charge under the plain key has been refunded.
 */
/proc/shipyard_fee_key(record_id, revision, action)
	var/base_key = "ship-[record_id]-r[revision]-[action]-[shipyard_current_round_id()]"
	var/attempt = GLOB.shipyard_fee_refunds[base_key] || 0
	return attempt ? "[base_key]-a[attempt + 1]" : base_key

/**
 * Charge a ship fee to its owner's ledger.
 *
 * A zero fee succeeds without touching the ledger, so a free action is not
 * refused by the ledger's own ban on zero deltas.
 */
/proc/shipyard_charge_fee(owner_uuid, amount, channel, reason, record_id, revision, action)
	var/datum/character_ledger_result/result = new
	if(amount <= 0)
		return result.mark(LEDGER_STATUS_OK, "")
	if(!SScharacter_ledger.is_available())
		return result.mark(LEDGER_STATUS_OFFLINE, "Persistent ledger is unavailable.")
	var/key = shipyard_fee_key(record_id, revision, action)
	result = SScharacter_ledger.try_debit(owner_uuid, amount, channel, reason, key, bypass_withdraw_cap = TRUE)
	log_admin("Ship ledger: debit [amount] cr from [owner_uuid] on [channel] ([key]): [reason]. Result: [result.status].")
	return result

/**
 * Hand a charge back after the action it paid for failed, and move the key on
 * so that trying again charges again.
 */
/proc/shipyard_refund_fee(owner_uuid, amount, channel, reason, record_id, revision, action)
	if(amount <= 0)
		return TRUE
	var/charge_key = shipyard_fee_key(record_id, revision, action)
	var/datum/character_ledger_result/result = SScharacter_ledger.try_credit(owner_uuid, amount, channel, reason, "[charge_key]-refund")
	log_admin("Ship ledger: refund [amount] cr to [owner_uuid] on [channel] ([charge_key]-refund): [reason]. Result: [result.status].")
	if(!result.success)
		message_admins("Ship ledger: a [amount] cr refund to [owner_uuid] for [charge_key] failed ([result.reason]) and needs refunding by hand.")
		return FALSE
	var/base_key = "ship-[record_id]-r[revision]-[action]-[shipyard_current_round_id()]"
	GLOB.shipyard_fee_refunds[base_key] = (GLOB.shipyard_fee_refunds[base_key] || 0) + 1
	return TRUE

/// Credit an insurance refund that outgrew the storage fee it was netted against.
/proc/shipyard_credit_fee(owner_uuid, amount, channel, reason, record_id, revision, action)
	var/datum/character_ledger_result/result = new
	if(amount <= 0)
		return result.mark(LEDGER_STATUS_OK, "")
	if(!SScharacter_ledger.is_available())
		return result.mark(LEDGER_STATUS_OFFLINE, "Persistent ledger is unavailable.")
	var/key = shipyard_fee_key(record_id, revision, action)
	result = SScharacter_ledger.try_credit(owner_uuid, amount, channel, reason, key)
	log_admin("Ship ledger: credit [amount] cr to [owner_uuid] on [channel] ([key]): [reason]. Result: [result.status].")
	return result
