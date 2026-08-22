/// Result of a ledger credit, debit, or close.
/datum/character_ledger_result
	var/success = FALSE
	var/status = LEDGER_STATUS_FAILED
	var/reason = ""
	var/balance_after = 0
	var/duplicate = FALSE

/datum/character_ledger_result/proc/mark(new_status, new_reason, new_balance = 0, is_duplicate = FALSE)
	status = new_status
	reason = new_reason
	balance_after = new_balance
	duplicate = is_duplicate
	success = (new_status == LEDGER_STATUS_OK || new_status == LEDGER_STATUS_DUPLICATE)
	return src

/// In-memory transaction row used by unit tests (CI has no MariaDB).
/datum/character_ledger_row
	var/id
	var/character_uuid
	var/currency_code
	var/delta
	var/balance_after
	var/channel
	var/reason
	var/idempotency_key
	var/round_id

SUBSYSTEM_DEF(character_ledger)
	name = "Character Ledger"
	dependencies = list(
		/datum/controller/subsystem/dbcore,
	)
	ss_flags = SS_NO_FIRE

	/// UUIDs that spawned as a character this round.
	var/list/participated_uuids
	/// uuid -> net ATM withdraws this round after opposite-side restores.
	var/list/withdrawn_this_round
	/// uuid -> net ATM deposits this round after opposite-side restores.
	var/list/deposited_this_round
	/// uuid -> credits reserved for loadout (ATM stub).
	var/list/loadout_reserved
	/// When TRUE, ledger ops use the in-memory log instead of SQL. Production stays FALSE.
	var/use_memory_store = FALSE
	/// Serial id for memory-store rows.
	var/next_memory_id = 1
	/// uuid -> list(/datum/character_ledger_row)
	var/list/memory_rows
	/// idempotency_key -> /datum/character_ledger_row
	var/list/memory_by_key
	/// uuid -> list(ckey, slot, display_name)
	var/list/memory_identities
	/// Inserted epoch currency codes in memory.
	var/list/memory_epochs

/datum/controller/subsystem/character_ledger/Initialize()
	participated_uuids = list()
	withdrawn_this_round = list()
	deposited_this_round = list()
	loadout_reserved = list()
	memory_rows = list()
	memory_by_key = list()
	memory_identities = list()
	memory_epochs = list()
#ifdef UNIT_TESTS
	use_memory_store = TRUE
	memory_epochs[LEDGER_CURRENCY_NTCR] = TRUE
	return SS_INIT_SUCCESS
#endif
	if(!SSdbcore.Connect())
		log_sql("SScharacter_ledger: database unavailable, ledger ops will fail closed.")
		return SS_INIT_SUCCESS
	seed_epoch()
	return SS_INIT_SUCCESS

/datum/controller/subsystem/character_ledger/Recover()
	participated_uuids = SScharacter_ledger.participated_uuids
	withdrawn_this_round = SScharacter_ledger.withdrawn_this_round
	deposited_this_round = SScharacter_ledger.deposited_this_round
	loadout_reserved = SScharacter_ledger.loadout_reserved
	use_memory_store = SScharacter_ledger.use_memory_store
	next_memory_id = SScharacter_ledger.next_memory_id
	memory_rows = SScharacter_ledger.memory_rows
	memory_by_key = SScharacter_ledger.memory_by_key
	memory_identities = SScharacter_ledger.memory_identities
	memory_epochs = SScharacter_ledger.memory_epochs

/datum/controller/subsystem/character_ledger/proc/seed_epoch()
	var/datum/db_query/query = SSdbcore.NewQuery(
		"INSERT IGNORE INTO [format_table_name("currency_epoch")] (currency_code) VALUES (:currency)",
		list("currency" = LEDGER_CURRENCY_NTCR)
	)
	if(!query.Execute(async = FALSE))
		log_sql("SScharacter_ledger: failed to seed NTCR epoch: [query.ErrorMsg()]")
	qdel(query)

/// 8-4-4-4-12 identifier derived from GUID() entropy so it fits CHAR(36).
/proc/generate_character_uuid()
	var/raw = md5("[GUID()][rand(1, 99999999)][world.time][world.realtime][world.tick_usage]")
	return "[copytext(raw, 1, 9)]-[copytext(raw, 9, 13)]-[copytext(raw, 13, 17)]-[copytext(raw, 17, 21)]-[copytext(raw, 21, 33)]"

/datum/controller/subsystem/character_ledger/proc/register_participant(character_uuid)
	if(!character_uuid)
		return
	participated_uuids[character_uuid] = TRUE

/// Copies the character PIN onto the mind and adds the key memory. Prefs apply before mind transfer, so spawn hooks must call this.
/datum/controller/subsystem/character_ledger/proc/remember_atm_pin(datum/mind/mind, pin)
	if(!mind || isnull(pin))
		return
	mind.atm_pin = pin
	mind.add_memory(/datum/memory/key/atm_pin, atm_pin = format_atm_pin(pin))


/datum/controller/subsystem/character_ledger/proc/get_evac_deposit_cap()
	return CONFIG_GET(number/atm_deposit_limit) * CONFIG_GET(number/evac_deposit_multiplier)

/datum/controller/subsystem/character_ledger/proc/is_available()
	return use_memory_store || SSdbcore.Connect()

/datum/controller/subsystem/character_ledger/proc/remaining_atm_deposit(character_uuid)
	return max(0, CONFIG_GET(number/atm_deposit_limit) - (deposited_this_round[character_uuid] || 0))

/datum/controller/subsystem/character_ledger/proc/remaining_atm_withdraw(character_uuid)
	return max(0, CONFIG_GET(number/atm_withdraw_limit) - (withdrawn_this_round[character_uuid] || 0))

/// ATM deposit restores outstanding withdraws first, then counts leftover against the deposit cap.
/datum/controller/subsystem/character_ledger/proc/apply_atm_deposit(character_uuid, amount)
	var/outstanding_withdraw = withdrawn_this_round[character_uuid] || 0
	var/restored = min(amount, outstanding_withdraw)
	if(restored)
		withdrawn_this_round[character_uuid] = outstanding_withdraw - restored
	var/remainder = amount - restored
	if(remainder)
		deposited_this_round[character_uuid] = (deposited_this_round[character_uuid] || 0) + remainder

/// ATM withdraw restores outstanding deposits first, then counts leftover against the withdraw cap.
/datum/controller/subsystem/character_ledger/proc/apply_atm_withdraw(character_uuid, amount)
	var/outstanding_deposit = deposited_this_round[character_uuid] || 0
	var/restored = min(amount, outstanding_deposit)
	if(restored)
		deposited_this_round[character_uuid] = outstanding_deposit - restored
	var/remainder = amount - restored
	if(remainder)
		withdrawn_this_round[character_uuid] = (withdrawn_this_round[character_uuid] || 0) + remainder

/datum/controller/subsystem/character_ledger/proc/current_round_id()
	if(!GLOB.round_id)
		return 0
	return text2num(GLOB.round_id) || 0

/datum/controller/subsystem/character_ledger/proc/active_currency()
	return LEDGER_CURRENCY_NTCR

/datum/controller/subsystem/character_ledger/proc/ensure_identity(mob/living/carbon/human/human)
	if(!istype(human) || !human.mind)
		return FALSE
	var/uuid = human.mind.character_uuid
	if(!uuid)
		uuid = human.client?.prefs?.character_uuid
	if(!uuid)
		uuid = generate_character_uuid()
		if(human.client?.prefs)
			human.client.prefs.character_uuid = uuid
	human.mind.character_uuid = uuid
	register_participant(uuid)

	var/ckey_value = ckey(human.ckey || human.mind.key)
	var/slot = human.mind.original_character_slot_index || 0
	var/display_name = human.real_name || human.name
	return insert_identity(uuid, ckey_value, slot, display_name)

/datum/controller/subsystem/character_ledger/proc/insert_identity(character_uuid, ckey_value, slot, display_name)
	if(use_memory_store)
		if(!memory_identities[character_uuid])
			memory_identities[character_uuid] = list("ckey" = ckey_value, "slot" = slot, "display_name" = display_name)
		return TRUE
	if(!SSdbcore.Connect())
		return FALSE
	var/datum/db_query/query = SSdbcore.NewQuery({"
		INSERT IGNORE INTO [format_table_name("character_identity")]
			(character_uuid, ckey, slot, display_name)
		VALUES (:uuid, :ckey, :slot, :display_name)
	"}, list(
		"uuid" = character_uuid,
		"ckey" = ckey_value,
		"slot" = slot,
		"display_name" = display_name,
	))
	var/success = query.Execute(async = FALSE)
	if(!success)
		log_sql("SScharacter_ledger: identity insert failed for [character_uuid]: [query.ErrorMsg()]")
	qdel(query)
	return success

/datum/controller/subsystem/character_ledger/proc/lookup_uuid(ckey_value, slot)
	ckey_value = ckey(ckey_value)
	if(use_memory_store)
		for(var/uuid in memory_identities)
			var/list/identity = memory_identities[uuid]
			if(identity["ckey"] == ckey_value && identity["slot"] == slot)
				return uuid
		return null
	if(!SSdbcore.Connect())
		return null
	var/datum/db_query/query = SSdbcore.NewQuery({"
		SELECT character_uuid FROM [format_table_name("character_identity")]
		WHERE ckey = :ckey AND slot = :slot
		LIMIT 1
	"}, list("ckey" = ckey_value, "slot" = slot))
	if(!query.Execute(async = FALSE) || !query.NextRow())
		qdel(query)
		return null
	var/uuid = query.item[1]
	qdel(query)
	return uuid

/datum/controller/subsystem/character_ledger/proc/get_balance(character_uuid, currency = LEDGER_CURRENCY_NTCR)
	if(!character_uuid)
		return 0
	if(use_memory_store)
		return memory_latest_balance(character_uuid, currency)
	if(!SSdbcore.Connect())
		return 0
	var/datum/db_query/query = SSdbcore.NewQuery({"
		SELECT balance_after FROM [format_table_name("character_ledger_transaction")]
		WHERE character_uuid = :uuid AND currency_code = :currency
		ORDER BY id DESC LIMIT 1
	"}, list("uuid" = character_uuid, "currency" = currency))
	if(!query.Execute(async = FALSE) || !query.NextRow())
		qdel(query)
		return 0
	var/balance = text2num(query.item[1]) || 0
	qdel(query)
	return balance

/datum/controller/subsystem/character_ledger/proc/memory_latest_balance(character_uuid, currency)
	var/list/rows = memory_rows[character_uuid]
	if(!rows)
		return 0
	for(var/i in rows.len to 1 step -1)
		var/datum/character_ledger_row/row = rows[i]
		if(row.currency_code == currency)
			return row.balance_after
	return 0

/datum/controller/subsystem/character_ledger/proc/try_credit(character_uuid, amount, channel, reason, idempotency_key, currency = LEDGER_CURRENCY_NTCR)
	if(channel == LEDGER_CHANNEL_ATM_DEPOSIT && amount > remaining_atm_deposit(character_uuid))
		var/datum/character_ledger_result/capped = new
		return capped.mark(LEDGER_STATUS_INVALID, "ATM deposit limit reached.")
	var/datum/character_ledger_result/result = append_transaction(character_uuid, amount, channel, reason, idempotency_key, currency, allow_zero = FALSE)
	if(result.success && !result.duplicate && channel == LEDGER_CHANNEL_ATM_DEPOSIT)
		apply_atm_deposit(character_uuid, amount)
	return result

/datum/controller/subsystem/character_ledger/proc/try_debit(character_uuid, amount, channel, reason, idempotency_key, currency = LEDGER_CURRENCY_NTCR, bypass_withdraw_cap = FALSE)
	if(!bypass_withdraw_cap && channel == LEDGER_CHANNEL_ATM_WITHDRAW && amount > remaining_atm_withdraw(character_uuid))
		var/datum/character_ledger_result/capped = new
		return capped.mark(LEDGER_STATUS_INVALID, "ATM withdraw limit reached.")
	var/datum/character_ledger_result/result = append_transaction(character_uuid, -amount, channel, reason, idempotency_key, currency, allow_zero = FALSE)
	if(result.success && !result.duplicate && !bypass_withdraw_cap && channel == LEDGER_CHANNEL_ATM_WITHDRAW)
		apply_atm_withdraw(character_uuid, amount)
	return result

/datum/controller/subsystem/character_ledger/proc/try_title_purchase(character_uuid, amount, listing_or_ship_id, idempotency_key, currency = LEDGER_CURRENCY_NTCR)
	return try_debit(
		character_uuid,
		amount,
		LEDGER_CHANNEL_TITLE_PURCHASE,
		"Title purchase [listing_or_ship_id]",
		idempotency_key,
		currency,
		bypass_withdraw_cap = TRUE,
	)

/datum/controller/subsystem/character_ledger/proc/append_transaction(character_uuid, delta, channel, reason, idempotency_key, currency, allow_zero)
	var/datum/character_ledger_result/result = new
	if(!character_uuid || !idempotency_key || !channel)
		return result.mark(LEDGER_STATUS_INVALID, "Missing uuid, channel, or idempotency key.")
	if(!allow_zero && delta == 0)
		return result.mark(LEDGER_STATUS_INVALID, "Zero delta is not allowed for this channel.")
	if(use_memory_store)
		return append_memory(result, character_uuid, delta, channel, reason, idempotency_key, currency, allow_zero)
	if(!SSdbcore.Connect())
		return result.mark(LEDGER_STATUS_OFFLINE, "Persistent ledger is unavailable.")
	return append_sql(result, character_uuid, delta, channel, reason, idempotency_key, currency, allow_zero)

/datum/controller/subsystem/character_ledger/proc/append_memory(datum/character_ledger_result/result, character_uuid, delta, channel, reason, idempotency_key, currency, allow_zero)
	var/datum/character_ledger_row/existing = memory_by_key[idempotency_key]
	if(existing)
		return result.mark(LEDGER_STATUS_DUPLICATE, "Idempotent replay.", existing.balance_after, TRUE)
	var/prev = memory_latest_balance(character_uuid, currency)
	var/new_balance = prev + delta
	if(new_balance < 0)
		return result.mark(LEDGER_STATUS_INSUFFICIENT, "Insufficient ledger balance.", prev)
	var/datum/character_ledger_row/row = new
	row.id = next_memory_id++
	row.character_uuid = character_uuid
	row.currency_code = currency
	row.delta = delta
	row.balance_after = new_balance
	row.channel = channel
	row.reason = reason
	row.idempotency_key = idempotency_key
	row.round_id = current_round_id()
	if(!memory_rows[character_uuid])
		memory_rows[character_uuid] = list()
	memory_rows[character_uuid] += row
	memory_by_key[idempotency_key] = row
	return result.mark(LEDGER_STATUS_OK, "", new_balance)

/datum/controller/subsystem/character_ledger/proc/append_sql(datum/character_ledger_result/result, character_uuid, delta, channel, reason, idempotency_key, currency, allow_zero)
	var/datum/db_query/query = SSdbcore.NewQuery({"
		CALL [format_table_name("character_ledger_append")](
			:uuid, :currency, :delta, :channel, :reason, :idempotency_key, :round_id, :allow_zero
		)
	"}, list(
		"uuid" = character_uuid,
		"currency" = currency,
		"delta" = delta,
		"channel" = channel,
		"reason" = copytext("[reason]", 1, 256),
		"idempotency_key" = idempotency_key,
		"round_id" = current_round_id(),
		"allow_zero" = allow_zero ? 1 : 0,
	))
	if(!query.Execute(async = FALSE) || !query.NextRow())
		var/error = query.ErrorMsg() || "No result from character_ledger_append."
		log_sql("SScharacter_ledger: append failed for [character_uuid]: [error]")
		qdel(query)
		return result.mark(LEDGER_STATUS_FAILED, error)
	var/status = query.item[1]
	var/balance = text2num(query.item[2]) || 0
	qdel(query)
	switch(status)
		if(LEDGER_STATUS_OK)
			return result.mark(LEDGER_STATUS_OK, "", balance)
		if(LEDGER_STATUS_DUPLICATE)
			return result.mark(LEDGER_STATUS_DUPLICATE, "Idempotent replay.", balance, TRUE)
		if(LEDGER_STATUS_INSUFFICIENT)
			return result.mark(LEDGER_STATUS_INSUFFICIENT, "Insufficient ledger balance.", balance)
		if(LEDGER_STATUS_NO_IDENTITY)
			return result.mark(LEDGER_STATUS_NO_IDENTITY, "Character identity is not registered.")
		if(LEDGER_STATUS_INVALID)
			return result.mark(LEDGER_STATUS_INVALID, "Invalid ledger delta.")
		else
			return result.mark(LEDGER_STATUS_FAILED, "Ledger append returned [status].", balance)

/datum/controller/subsystem/character_ledger/proc/get_personal_account(mob/living/carbon/human/human)
	if(!human?.account_id)
		return null
	var/datum/bank_account/account = SSeconomy.bank_accounts_by_id["[human.account_id]"]
	if(!istype(account) || istype(account, /datum/bank_account/department) || istype(account, /datum/bank_account/remote) || istype(account, /datum/bank_account/station_reserve))
		return null
	return account

/datum/controller/subsystem/character_ledger/proc/collect_round_end()
	sweep_escaped_balances()
	finalize_round_balances()

/datum/controller/subsystem/character_ledger/proc/sweep_escaped_balances()
	var/cap = get_evac_deposit_cap()
	var/round_id = current_round_id()
	for(var/mob/living/carbon/human/human as anything in GLOB.human_list)
		if(QDELETED(human) || !human.mind?.character_uuid)
			continue
		if(!considered_escaped(human.mind))
			continue
		var/datum/bank_account/account = get_personal_account(human)
		if(!account)
			continue
		var/amount = min(account.account_balance, cap)
		if(amount <= 0)
			continue
		var/uuid = human.mind.character_uuid
		var/datum/character_ledger_result/result = try_credit(
			uuid,
			amount,
			LEDGER_CHANNEL_EVAC_DEPOSIT,
			"Evacuation deposit",
			"evac:[round_id]:[uuid]",
		)
		if(!result.success)
			log_sql("SScharacter_ledger: evac deposit failed for [uuid]: [result.reason]")
			continue
		if(!result.duplicate)
			account.adjust_money(-amount, "Persistent ledger evacuation deposit")

/datum/controller/subsystem/character_ledger/proc/finalize_round_balances()
	var/round_id = current_round_id()
	var/currency = active_currency()
	for(var/uuid in participated_uuids)
		var/datum/character_ledger_result/result = append_transaction(
			uuid,
			0,
			LEDGER_CHANNEL_ROUND_CLOSE,
			"Round close",
			"round_close:[round_id]:[uuid]",
			currency,
			allow_zero = TRUE,
		)
		if(!result.success)
			log_sql("SScharacter_ledger: round close failed for [uuid]: [result.reason]")

/datum/controller/subsystem/character_ledger/proc/count_rows(character_uuid, channel)
	if(use_memory_store)
		var/count = 0
		for(var/datum/character_ledger_row/row as anything in memory_rows[character_uuid])
			if(!channel || row.channel == channel)
				count++
		return count
	if(!SSdbcore.Connect())
		return 0
	var/sql
	var/list/arguments = list("uuid" = character_uuid)
	if(channel)
		sql = "SELECT COUNT(*) FROM [format_table_name("character_ledger_transaction")] WHERE character_uuid = :uuid AND channel = :channel"
		arguments["channel"] = channel
	else
		sql = "SELECT COUNT(*) FROM [format_table_name("character_ledger_transaction")] WHERE character_uuid = :uuid"
	var/datum/db_query/query = SSdbcore.NewQuery(sql, arguments)
	if(!query.Execute(async = FALSE) || !query.NextRow())
		qdel(query)
		return 0
	var/count = text2num(query.item[1]) || 0
	qdel(query)
	return count

/datum/controller/subsystem/character_ledger/proc/get_last_row(character_uuid)
	var/list/rows = memory_rows[character_uuid]
	if(!rows?.len)
		return null
	return rows[rows.len]
