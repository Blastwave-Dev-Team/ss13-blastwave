/obj/machinery/atm
	name = "automated teller machine"
	desc = "A terminal for withdrawing credits from your personal bank account into your station account.\n\
A large warning reads: \"NT Corporate Regulations restrict withdrawals and deposits to a maximum of 5,000 credits per shift.\""
	icon = 'modular_nova/modules/character_ledger/icons/atm.dmi'
	icon_state = "atm"
	base_icon_state = "atm"
	density = TRUE
	anchored = TRUE
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION
	/// Prevents overlapping deposit/withdraw/cash insert from double-applying.
	var/busy = FALSE
	/// Per-machine sequence used in ATM idempotency keys.
	var/operation_seq = 0
	/// Random `atm-screen_symbol-*` state chosen at spawn.
	var/currency_symbol
	/// Holochip-palette tint applied to [currency_symbol].
	var/currency_color
	/// Cached icon states that start with `atm-screen_symbol-`.
	var/static/list/currency_symbols
	/// Holochip value colors used to mask the currency glyph.
	var/static/list/currency_colors = list(
		"#8E2E38",
		"#914792",
		"#BF5E0A",
		"#358F34",
		COLOR_SLIME_METAL,
		"#009D9B",
		"#0153C1",
		"#2C2C2C",
	)

/obj/machinery/atm/Initialize(mapload)
	pick_currency_overlay()
	return ..()

/obj/machinery/atm/proc/pick_currency_overlay()
	if(isnull(currency_symbols))
		currency_symbols = list()
		for(var/state in icon_states(icon))
			if(findtext(state, "atm-screen_symbol-") == 1)
				currency_symbols += state
	if(length(currency_symbols))
		currency_symbol = pick(currency_symbols)
	currency_color = pick(currency_colors)

/obj/machinery/atm/update_icon_state()
	icon_state = (machine_stat & BROKEN) ? "[base_icon_state]-broken" : base_icon_state
	return ..()

/obj/machinery/atm/update_overlays()
	. = ..()
	if((machine_stat & BROKEN) || !is_operational)
		return
	. += mutable_appearance(icon, "atm-screen_login")
	if(currency_symbol)
		var/mutable_appearance/symbol = mutable_appearance(icon, currency_symbol)
		symbol.color = currency_color
		. += symbol

/obj/machinery/atm/on_set_is_operational(old_value)
	. = ..()
	update_appearance()

/obj/machinery/atm/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "CharacterATM", name)
		ui.open()

/obj/machinery/atm/ui_data(mob/user)
	var/list/data = list()
	var/mob/living/carbon/human/human = resolve_user(user, announce = FALSE)
	var/datum/bank_account/account = human ? get_authorized_account(human) : null
	var/uuid = human?.mind?.character_uuid
	data["operational"] = is_operational
	data["offline"] = !SScharacter_ledger.is_available()
	data["has_uuid"] = !!uuid
	data["has_id"] = !!account
	data["ledger_balance"] = uuid ? SScharacter_ledger.get_balance(uuid) : 0
	data["account_balance"] = account?.account_balance || 0
	data["remaining_deposit"] = uuid ? SScharacter_ledger.remaining_atm_deposit(uuid) : 0
	data["remaining_withdraw"] = uuid ? SScharacter_ledger.remaining_atm_withdraw(uuid) : 0
	return data

/obj/machinery/atm/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	var/mob/living/carbon/human/human = resolve_user(ui.user)
	if(!human)
		return TRUE
	var/amount = text2num(params["amount"])
	switch(action)
		if("deposit")
			try_deposit(human, amount)
			return TRUE
		if("withdraw")
			try_withdraw(human, amount, params["pin"])
			return TRUE

/obj/machinery/atm/attackby(obj/item/weapon, mob/user, list/modifiers, list/attack_modifiers)
	if(iscash(weapon))
		var/mob/living/carbon/human/human = resolve_user(user)
		if(human)
			try_insert_cash(human, weapon)
		return TRUE
	if(istype(weapon, /obj/item/card/id))
		ui_interact(user)
		return TRUE
	return ..()

/obj/machinery/atm/proc/next_idempotency(kind, uuid)
	operation_seq++
	return "[kind]:[SScharacter_ledger.current_round_id()]:[uuid]:[operation_seq]"

/obj/machinery/atm/proc/resolve_user(mob/user, announce = TRUE)
	if(!is_operational)
		if(announce)
			say("Out of order.")
		return null
	if(!ishuman(user) || issilicon(user))
		if(announce)
			balloon_alert(user, "unusable!")
		return null
	if(!SScharacter_ledger.is_available())
		if(announce)
			say("Persistent ledger is offline.")
		return null
	var/mob/living/carbon/human/human = user
	if(!SScharacter_ledger.ensure_identity(human) || !human.mind?.character_uuid)
		if(announce)
			say("No character identity on file.")
		return null
	return human

/obj/machinery/atm/proc/get_authorized_account(mob/living/carbon/human/human)
	var/datum/bank_account/personal = SScharacter_ledger.get_personal_account(human)
	if(!personal)
		return null
	var/obj/item/card/id/id_card = human.get_idcard(TRUE)
	if(!id_card || id_card.registered_account != personal)
		return null
	return personal

/obj/machinery/atm/proc/pin_matches(mob/living/carbon/human/human, submitted)
	if(isnull(human.mind?.atm_pin))
		return FALSE
	var/entered = isnum(submitted) ? submitted : text2num(submitted)
	if(isnull(entered))
		return FALSE
	return entered == human.mind.atm_pin

/obj/machinery/atm/proc/try_deposit(mob/living/carbon/human/human, amount)
	if(busy)
		return FALSE
	var/datum/bank_account/account = get_authorized_account(human)
	if(!account)
		say("Present a matching personal ID.")
		return FALSE
	var/uuid = human.mind.character_uuid
	amount = round(amount)
	if(amount <= 0)
		say("Invalid amount.")
		return FALSE
	amount = min(amount, account.account_balance, SScharacter_ledger.remaining_atm_deposit(uuid))
	if(amount <= 0)
		say("Nothing to deposit.")
		return FALSE
	busy = TRUE
	var/datum/character_ledger_result/result = SScharacter_ledger.try_credit(
		uuid,
		amount,
		LEDGER_CHANNEL_ATM_DEPOSIT,
		"ATM deposit",
		next_idempotency("atm_deposit", uuid),
	)
	if(!result.success)
		busy = FALSE
		say(result.reason || "Deposit refused.")
		return FALSE
	if(!result.duplicate)
		account.adjust_money(-amount, "ATM deposit to persistent ledger")
	busy = FALSE
	say("Deposited [amount] [MONEY_NAME_AUTOPURAL(amount)]. Ledger balance: [result.balance_after].")
	log_econ("[key_name(human)] deposited [amount] into character ledger [uuid] via ATM.")
	return TRUE

/obj/machinery/atm/proc/try_withdraw(mob/living/carbon/human/human, amount, submitted_pin)
	if(busy)
		return FALSE
	if(!pin_matches(human, submitted_pin))
		say("Incorrect PIN.")
		return FALSE
	var/datum/bank_account/account = get_authorized_account(human)
	if(!account)
		say("Present a matching personal ID.")
		return FALSE
	var/uuid = human.mind.character_uuid
	amount = round(amount)
	if(amount <= 0)
		say("Invalid amount.")
		return FALSE
	amount = min(amount, SScharacter_ledger.get_balance(uuid), SScharacter_ledger.remaining_atm_withdraw(uuid))
	if(amount <= 0)
		say("Nothing to withdraw.")
		return FALSE
	busy = TRUE
	var/datum/character_ledger_result/result = SScharacter_ledger.try_debit(
		uuid,
		amount,
		LEDGER_CHANNEL_ATM_WITHDRAW,
		"ATM withdraw",
		next_idempotency("atm_withdraw", uuid),
	)
	if(!result.success)
		busy = FALSE
		say(result.reason || "Withdrawal refused.")
		return FALSE
	if(!result.duplicate)
		account.adjust_money(amount, "ATM withdraw from persistent ledger")
	busy = FALSE
	say("Withdrew [amount] [MONEY_NAME_AUTOPURAL(amount)]. Ledger balance: [result.balance_after].")
	log_econ("[key_name(human)] withdrew [amount] from character ledger [uuid] via ATM.")
	return TRUE

/obj/machinery/atm/proc/try_insert_cash(mob/living/carbon/human/human, obj/item/cash)
	if(busy)
		return FALSE
	if(!get_authorized_account(human))
		say("Present a matching personal ID.")
		return FALSE
	var/value = cash.get_item_credit_value()
	if(value <= 0)
		say("Unrecognized cash value.")
		return FALSE
	var/uuid = human.mind.character_uuid
	var/amount = min(value, SScharacter_ledger.remaining_atm_deposit(uuid))
	if(amount <= 0)
		say("Deposit limit reached.")
		return FALSE
	busy = TRUE
	var/datum/character_ledger_result/result = SScharacter_ledger.try_credit(
		uuid,
		amount,
		LEDGER_CHANNEL_ATM_DEPOSIT,
		"ATM cash deposit",
		next_idempotency("atm_deposit", uuid),
	)
	if(!result.success)
		busy = FALSE
		say(result.reason || "Deposit refused.")
		return FALSE
	qdel(cash)
	busy = FALSE
	say("Deposited [amount] [MONEY_NAME_AUTOPURAL(amount)]. Ledger balance: [result.balance_after].")
	log_econ("[key_name(human)] deposited [amount] cash into character ledger [uuid] via ATM.")
	return TRUE
