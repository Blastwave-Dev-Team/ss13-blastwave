/datum/unit_test/character_uuid_stable

/datum/unit_test/character_uuid_stable/Run()
	var/datum/preferences/prefs = new(new /datum/client_interface)
	var/list/save_data = list()
	prefs.save_character_nova(save_data)
	TEST_ASSERT(prefs.character_uuid, "Character UUID was not generated on first save.")
	TEST_ASSERT_EQUAL(length(prefs.character_uuid), 36, "Character UUID must be CHAR(36).")
	var/first_uuid = prefs.character_uuid

	var/datum/preferences/reloaded = new(new /datum/client_interface)
	reloaded.load_character_nova(save_data)
	TEST_ASSERT_EQUAL(reloaded.character_uuid, first_uuid, "Character UUID changed on load.")

	var/list/second_save = list()
	reloaded.save_character_nova(second_save)
	TEST_ASSERT_EQUAL(second_save["character_uuid"], first_uuid, "Character UUID was regenerated on a later save.")

/datum/unit_test/character_ledger_ops

/datum/unit_test/character_ledger_ops/Run()
	var/uuid = generate_character_uuid()
	SScharacter_ledger.insert_identity(uuid, "ledger_test", 1, "Ledger Test")

	var/datum/character_ledger_result/credit = SScharacter_ledger.try_credit(uuid, 100, LEDGER_CHANNEL_ADMIN_SEED, "unit test credit", "test:credit:[uuid]")
	TEST_ASSERT(credit.success, "Credit failed: [credit.reason]")
	TEST_ASSERT_EQUAL(credit.balance_after, 100, "Credit did not set balance_after to 100.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), 100, "get_balance did not match credit.")

	var/datum/character_ledger_result/debit = SScharacter_ledger.try_debit(uuid, 40, LEDGER_CHANNEL_ADMIN_SEED, "unit test debit", "test:debit:[uuid]")
	TEST_ASSERT(debit.success, "Debit failed: [debit.reason]")
	TEST_ASSERT_EQUAL(debit.balance_after, 60, "Debit did not leave 60.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid), 2, "Credit and debit should append two serial rows, not UPDATE a balance.")

	var/datum/character_ledger_result/broke = SScharacter_ledger.try_debit(uuid, 1000, LEDGER_CHANNEL_ADMIN_SEED, "too much", "test:broke:[uuid]")
	TEST_ASSERT(!broke.success, "Overdraft debit should fail.")
	TEST_ASSERT_EQUAL(broke.status, LEDGER_STATUS_INSUFFICIENT, "Overdraft should report insufficient funds.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), 60, "Failed debit mutated the balance.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid), 2, "Failed debit inserted a row.")

	var/datum/character_ledger_result/replay = SScharacter_ledger.try_credit(uuid, 100, LEDGER_CHANNEL_ADMIN_SEED, "unit test credit", "test:credit:[uuid]")
	TEST_ASSERT(replay.success, "Idempotent replay should succeed.")
	TEST_ASSERT(replay.duplicate, "Idempotent replay should be marked duplicate.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid), 2, "Idempotent replay inserted a second row.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), 60, "Idempotent replay changed the balance.")

	var/datum/character_ledger_result/title = SScharacter_ledger.try_title_purchase(uuid, 10, "listing-1", "test:title:[uuid]")
	TEST_ASSERT(title.success, "Title purchase failed: [title.reason]")
	TEST_ASSERT_EQUAL(title.balance_after, 50, "Title purchase did not debit 10.")
	var/datum/character_ledger_row/title_row = SScharacter_ledger.get_last_row(uuid)
	TEST_ASSERT_EQUAL(title_row.channel, LEDGER_CHANNEL_TITLE_PURCHASE, "Title purchase did not record TITLE_PURCHASE.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.withdrawn_this_round[uuid] || 0, 0, "Title purchase counted against the ATM withdraw cap.")

/datum/unit_test/character_ledger_offline

/datum/unit_test/character_ledger_offline/Run()
	var/was_memory = SScharacter_ledger.use_memory_store
	SScharacter_ledger.use_memory_store = FALSE
	var/datum/character_ledger_result/result = SScharacter_ledger.try_credit(generate_character_uuid(), 10, LEDGER_CHANNEL_ADMIN_SEED, "offline", "test:offline")
	SScharacter_ledger.use_memory_store = was_memory
	TEST_ASSERT(!result.success, "Offline ledger credit should fail closed.")
	TEST_ASSERT_EQUAL(result.status, LEDGER_STATUS_OFFLINE, "Offline ledger should report offline, got [result.status]: [result.reason]")

/datum/unit_test/character_ledger_round_end
	var/list/saved_participants

/datum/unit_test/character_ledger_round_end/Run()
	saved_participants = SScharacter_ledger.participated_uuids.Copy()
	SScharacter_ledger.participated_uuids = list()

	var/mob/living/carbon/human/escaped = allocate(/mob/living/carbon/human/consistent)
	escaped.mind_initialize()
	var/escaped_uuid = generate_character_uuid()
	escaped.mind.character_uuid = escaped_uuid
	escaped.mind.force_escaped = TRUE
	SScharacter_ledger.insert_identity(escaped_uuid, "escaped", 1, escaped.real_name)
	SScharacter_ledger.register_participant(escaped_uuid)
	var/datum/bank_account/escaped_account = new /datum/bank_account("Escaped Ledger", null, 1, TRUE)
	escaped.account_id = escaped_account.account_id
	escaped_account.account_balance = 20000

	var/mob/living/carbon/human/stranded = allocate(/mob/living/carbon/human/consistent)
	stranded.mind_initialize()
	var/stranded_uuid = generate_character_uuid()
	stranded.mind.character_uuid = stranded_uuid
	stranded.mind.force_escaped = FALSE
	SScharacter_ledger.insert_identity(stranded_uuid, "stranded", 1, stranded.real_name)
	SScharacter_ledger.register_participant(stranded_uuid)
	var/datum/bank_account/stranded_account = new /datum/bank_account("Stranded Ledger", null, 1, TRUE)
	stranded.account_id = stranded_account.account_id
	stranded_account.account_balance = 500

	var/expected_evac = min(20000, SScharacter_ledger.get_evac_deposit_cap())
	SScharacter_ledger.collect_round_end()

	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(escaped_uuid, LEDGER_CHANNEL_EVAC_DEPOSIT), 1, "Escaped character did not receive an EVAC_DEPOSIT row.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(escaped_uuid), expected_evac, "Evac deposit did not apply the ATM cap.")
	TEST_ASSERT_EQUAL(escaped_account.account_balance, 20000 - expected_evac, "Round account was not debited for the evac deposit.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(stranded_uuid, LEDGER_CHANNEL_EVAC_DEPOSIT), 0, "Non-escaped character received an EVAC_DEPOSIT.")
	TEST_ASSERT_EQUAL(stranded_account.account_balance, 500, "Non-escaped round account was swept.")

	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(escaped_uuid, LEDGER_CHANNEL_ROUND_CLOSE), 1, "Escaped character missing ROUND_CLOSE.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(stranded_uuid, LEDGER_CHANNEL_ROUND_CLOSE), 1, "Non-escaped character missing ROUND_CLOSE.")
	var/datum/character_ledger_row/escaped_close = SScharacter_ledger.get_last_row(escaped_uuid)
	TEST_ASSERT_EQUAL(escaped_close.channel, LEDGER_CHANNEL_ROUND_CLOSE, "Escaped last row was not ROUND_CLOSE.")
	TEST_ASSERT_EQUAL(escaped_close.delta, 0, "ROUND_CLOSE must be a 0-delta row.")
	TEST_ASSERT_EQUAL(escaped_close.balance_after, expected_evac, "Escaped ROUND_CLOSE did not snapshot post-evac balance.")
	var/datum/character_ledger_row/stranded_close = SScharacter_ledger.get_last_row(stranded_uuid)
	TEST_ASSERT_EQUAL(stranded_close.delta, 0, "Stranded ROUND_CLOSE must be a 0-delta row.")
	TEST_ASSERT_EQUAL(stranded_close.balance_after, 0, "Stranded ROUND_CLOSE should formalize a zero ledger.")

	SScharacter_ledger.collect_round_end()
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(escaped_uuid, LEDGER_CHANNEL_ROUND_CLOSE), 1, "ROUND_CLOSE was not idempotent.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(escaped_uuid, LEDGER_CHANNEL_EVAC_DEPOSIT), 1, "EVAC_DEPOSIT was not idempotent.")

/datum/unit_test/character_ledger_round_end/Destroy()
	if(saved_participants)
		SScharacter_ledger.participated_uuids = saved_participants
	return ..()

/datum/unit_test/character_atm_pin_pref

/datum/unit_test/character_atm_pin_pref/Run()
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human/consistent)
	human.mind_initialize()
	var/datum/preference/numeric/atm_pin/pin_pref = GLOB.preference_entries[/datum/preference/numeric/atm_pin]
	pin_pref.apply_to_human(human, 42)
	TEST_ASSERT_EQUAL(human.mind.atm_pin, 42, "ATM PIN preference did not copy onto the mind.")
	var/datum/memory/key/atm_pin/memory = human.mind.memories[/datum/memory/key/atm_pin]
	TEST_ASSERT(memory, "ATM PIN preference did not add a key memory.")
	TEST_ASSERT_EQUAL(memory.atm_pin, "0042", "ATM PIN memory was not zero-padded.")

/datum/unit_test/character_atm_ops

/datum/unit_test/character_atm_ops/proc/make_customer(pin, account_credits, ledger_credits)
	var/mob/living/carbon/human/human = allocate(/mob/living/carbon/human/consistent)
	human.mind_initialize()
	var/uuid = generate_character_uuid()
	human.mind.character_uuid = uuid
	human.mind.atm_pin = pin
	SScharacter_ledger.insert_identity(uuid, "atm_test", 1, human.real_name)
	SScharacter_ledger.register_participant(uuid)
	if(ledger_credits)
		SScharacter_ledger.try_credit(uuid, ledger_credits, LEDGER_CHANNEL_ADMIN_SEED, "atm test seed", "test:atm:seed:[uuid]")
	var/datum/bank_account/account = new /datum/bank_account(human.real_name, null, 1, TRUE)
	account.account_balance = account_credits
	human.account_id = account.account_id
	var/obj/item/card/id/id_card = allocate(/obj/item/card/id)
	id_card.registered_account = account
	human.equip_to_slot(id_card, ITEM_SLOT_ID)
	return human

/datum/unit_test/character_atm_ops/Run()
	var/obj/machinery/atm/teller = allocate(/obj/machinery/atm)
	var/mob/living/carbon/human/customer = make_customer(1234, 8000, 8000)
	var/uuid = customer.mind.character_uuid
	var/datum/bank_account/account = SScharacter_ledger.get_personal_account(customer)

	TEST_ASSERT(teller.try_deposit(customer, 2000), "PIN-less account deposit should succeed.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid, LEDGER_CHANNEL_ATM_DEPOSIT), 1, "Account deposit did not append ATM_DEPOSIT.")
	TEST_ASSERT_EQUAL(account.account_balance, 6000, "Account deposit did not debit the round account.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), 10000, "Account deposit did not credit the ledger.")

	var/datum/character_ledger_result/over_deposit = SScharacter_ledger.try_credit(uuid, 4000, LEDGER_CHANNEL_ATM_DEPOSIT, "over cap", "test:atm:overdep:[uuid]")
	TEST_ASSERT(!over_deposit.success, "Ledger should reject an ATM deposit that exceeds remaining room.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid, LEDGER_CHANNEL_ATM_DEPOSIT), 1, "Over-cap deposit inserted a row.")

	TEST_ASSERT(!teller.try_withdraw(customer, 100, 9999), "Wrong PIN should refuse withdraw.")
	TEST_ASSERT(!teller.try_withdraw(customer, 100, null), "Missing PIN should refuse withdraw.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid, LEDGER_CHANNEL_ATM_WITHDRAW), 0, "Failed PIN withdraw inserted a row.")
	TEST_ASSERT_EQUAL(account.account_balance, 6000, "Failed PIN withdraw mutated the round account.")

	TEST_ASSERT(teller.try_withdraw(customer, 1500, 1234), "Correct PIN withdraw should succeed.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid, LEDGER_CHANNEL_ATM_WITHDRAW), 1, "Withdraw did not append ATM_WITHDRAW.")
	TEST_ASSERT_EQUAL(account.account_balance, 7500, "Withdraw did not credit the round account.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), 8500, "Withdraw did not debit the ledger.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_deposit(uuid), 4500, "Withdraw should restore deposit room before consuming withdraw cap.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_withdraw(uuid), CONFIG_GET(number/atm_withdraw_limit), "Withdraw that only reverses a deposit should not consume withdraw cap.")

	var/datum/character_ledger_result/over_withdraw = SScharacter_ledger.try_debit(uuid, 6000, LEDGER_CHANNEL_ATM_WITHDRAW, "over cap", "test:atm:overwd:[uuid]")
	TEST_ASSERT(!over_withdraw.success, "Ledger should reject an ATM withdraw that exceeds remaining room.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid, LEDGER_CHANNEL_ATM_WITHDRAW), 1, "Over-cap withdraw inserted a row.")
	TEST_ASSERT_EQUAL(account.account_balance, 7500, "Over-cap withdraw mutated the round account.")

	SScharacter_ledger.withdrawn_this_round[uuid] = CONFIG_GET(number/atm_withdraw_limit)
	var/datum/character_ledger_result/title = SScharacter_ledger.try_title_purchase(uuid, 10, "atm-listing", "test:atm:title:[uuid]")
	TEST_ASSERT(title.success, "Title purchase should still succeed after the withdraw cap: [title.reason]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), 8490, "Title purchase did not debit 10 after the withdraw cap.")

	var/obj/item/holochip/chip = allocate(/obj/item/holochip)
	chip.credits = 250
	TEST_ASSERT(teller.try_insert_cash(customer, chip), "Cash insert should deposit without a PIN.")
	TEST_ASSERT(QDELETED(chip), "Cash insert did not consume the holochip.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.count_rows(uuid, LEDGER_CHANNEL_ATM_DEPOSIT), 2, "Cash insert did not append ATM_DEPOSIT.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), 8740, "Cash insert did not credit the ledger.")

	var/balance_before = account.account_balance
	var/ledger_before = SScharacter_ledger.get_balance(uuid)
	var/was_memory = SScharacter_ledger.use_memory_store
	SScharacter_ledger.use_memory_store = FALSE
	TEST_ASSERT(!teller.try_withdraw(customer, 100, 1234), "Offline withdraw should fail closed.")
	TEST_ASSERT(!teller.try_deposit(customer, 100), "Offline deposit should fail closed.")
	TEST_ASSERT_EQUAL(account.account_balance, balance_before, "Offline ATM mutated the round account.")
	SScharacter_ledger.use_memory_store = was_memory
	TEST_ASSERT_EQUAL(SScharacter_ledger.get_balance(uuid), ledger_before, "Offline ATM mutated the in-memory ledger after restore.")

/datum/unit_test/character_atm_cap_restore

/datum/unit_test/character_atm_cap_restore/Run()
	var/uuid = generate_character_uuid()
	SScharacter_ledger.insert_identity(uuid, "atm_cap", 1, "ATM Cap")
	SScharacter_ledger.register_participant(uuid)
	SScharacter_ledger.try_credit(uuid, 8000, LEDGER_CHANNEL_ADMIN_SEED, "cap seed", "test:atm:cap:seed:[uuid]")

	var/datum/character_ledger_result/withdraw = SScharacter_ledger.try_debit(uuid, 2000, LEDGER_CHANNEL_ATM_WITHDRAW, "cap withdraw", "test:atm:cap:wd:[uuid]")
	TEST_ASSERT(withdraw.success, "Initial withdraw should succeed: [withdraw.reason]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_withdraw(uuid), 3000, "Withdraw should consume withdraw cap.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_deposit(uuid), CONFIG_GET(number/atm_deposit_limit), "Withdraw should not consume deposit cap.")

	var/datum/character_ledger_result/deposit = SScharacter_ledger.try_credit(uuid, 2000, LEDGER_CHANNEL_ATM_DEPOSIT, "cap deposit", "test:atm:cap:dep:[uuid]")
	TEST_ASSERT(deposit.success, "Matching deposit should succeed: [deposit.reason]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_withdraw(uuid), CONFIG_GET(number/atm_withdraw_limit), "Matching deposit should restore withdraw cap.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_deposit(uuid), CONFIG_GET(number/atm_deposit_limit), "Matching deposit should not consume deposit cap.")

	var/datum/character_ledger_result/second_withdraw = SScharacter_ledger.try_debit(uuid, 5000, LEDGER_CHANNEL_ATM_WITHDRAW, "full withdraw", "test:atm:cap:wd2:[uuid]")
	TEST_ASSERT(second_withdraw.success, "Restored withdraw cap should allow a full 5k withdraw: [second_withdraw.reason]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_withdraw(uuid), 0, "Full withdraw should exhaust withdraw cap.")

	var/datum/character_ledger_result/partial = SScharacter_ledger.try_credit(uuid, 1500, LEDGER_CHANNEL_ATM_DEPOSIT, "partial restore", "test:atm:cap:dep2:[uuid]")
	TEST_ASSERT(partial.success, "Partial restore deposit should succeed: [partial.reason]")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_withdraw(uuid), 1500, "Partial deposit should restore that much withdraw room.")
	TEST_ASSERT_EQUAL(SScharacter_ledger.remaining_atm_deposit(uuid), CONFIG_GET(number/atm_deposit_limit), "Partial restore should not consume deposit cap.")
