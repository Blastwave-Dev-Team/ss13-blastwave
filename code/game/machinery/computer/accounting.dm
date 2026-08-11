#define MAX_ADVANCES 3
// BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: #define MIN_PAY_MOD 0.5
// BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: #define MAX_PAY_MOD 1.5

/obj/machinery/computer/accounting
	name = "account lookup console"
	desc = "Used to view crew member accounts and purchases."
	icon_screen = "accounts"
	icon_keyboard = "id_key"
	circuit = /obj/item/circuitboard/computer/accounting
	light_color = LIGHT_COLOR_GREEN
	req_access = list(ACCESS_CHANGE_IDS) // BLASTWAVE EDIT ADDITION - STATION_TREASURY

/obj/machinery/computer/accounting/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if (!ui)
		ui = new(user, src, "AccountingConsole", name)
		ui.open()

/obj/machinery/computer/accounting/ui_data(mob/user)
	. = ..()
	var/list/data = list()
	var/list/player_accounts = list()
	// BLASTWAVE EDIT ADDITION START - STATION_TREASURY
	var/list/station_department_accounts = SSeconomy.station_department_accounts
	// BLASTWAVE EDIT ADDITION END

	for(var/id in SSeconomy.bank_accounts_by_id)
		var/datum/bank_account/current_bank_account = SSeconomy.bank_accounts_by_id[id]
		if(!(current_bank_account.account_job?.job_flags & JOB_CREW_MANIFEST))
			continue
		// BLASTWAVE EDIT ADDITION START - STATION_TREASURY
		var/effective_pay = current_bank_account.get_recurring_paycheck()
		var/is_station_payroll = (current_bank_account.account_job.paycheck_department in station_department_accounts)
		// BLASTWAVE EDIT ADDITION END
		player_accounts += list(list(
			"name" = current_bank_account.account_holder,
			"job" = current_bank_account.account_job.title,
			"balance" = round(current_bank_account.account_balance),
			// BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: "modifier" = current_bank_account.payday_modifier,
			// BLASTWAVE EDIT ADDITION START - STATION_TREASURY
			"pay" = effective_pay,
			"default_pay" = current_bank_account.get_default_recurring_paycheck(),
			"min_pay" = current_bank_account.get_minimum_recurring_paycheck(),
			"base_pay" = is_station_payroll ? min(effective_pay, PAYCHECK_CREW) : effective_pay,
			"uplift_pay" = is_station_payroll ? max(effective_pay - PAYCHECK_CREW, 0) : 0,
			"has_pay_override" = !isnull(current_bank_account.recurring_paycheck_override),
			"uplift_missed" = current_bank_account.last_payday_uplift_missed,
			// BLASTWAVE EDIT ADDITION END
			"num_advances" = current_bank_account.paydays_to_skip,
			"id" = id,
		))
	data["accounts"] = player_accounts
	data["audit_log"] = SSeconomy.audit_log
	data["crashing"] = HAS_TRAIT(SSeconomy, TRAIT_MARKET_CRASHING)
	data["station_time"] = round_timestamp("hh:mm")
	// BLASTWAVE EDIT ADDITION START - STATION_TREASURY
	data["can_manage_payroll"] = allowed(user)
	data["station_reserve_balance"] = SSeconomy.get_station_reserve()?.account_balance || 0
	data["station_reserve_margin"] = SSeconomy.station_reserve_margin * 100
	// BLASTWAVE EDIT ADDITION END
	return data

/obj/machinery/computer/accounting/ui_static_data(mob/user)
	var/list/data = list()
	var/static/ian_format = pick("png", "jpg", "jpeg", "webp", "bmp")
	data["pic_file_format"] = ian_format
	data["young_ian"] = check_holidays(IAN_HOLIDAY)
	data["max_advances"] = MAX_ADVANCES
	// BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: data["max_pay_mod"] = MAX_PAY_MOD
	// BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: data["min_pay_mod"] = MIN_PAY_MOD
	// BLASTWAVE EDIT ADDITION START - STATION_TREASURY
	data["max_pay"] = PAYCHECK_MAXIMUM
	// BLASTWAVE EDIT ADDITION END
	return data

/obj/machinery/computer/accounting/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	playsound(src, SFX_TERMINAL_TYPE, 50, FALSE)
	var/datum/bank_account/bank_account = SSeconomy.bank_accounts_by_id[params["account_id"]]
	if(isnull(bank_account) || !(bank_account.account_job?.job_flags & JOB_CREW_MANIFEST))
		return
	// BLASTWAVE EDIT ADDITION START - STATION_TREASURY
	if(!allowed(ui.user))
		balloon_alert(ui.user, "access denied")
		return
	// BLASTWAVE EDIT ADDITION END

	/* // BLASTWAVE EDIT REMOVAL START - STATION_TREASURY
	switch(action)
		if("paycheck_advance")
			if(bank_account.paydays_to_skip < MAX_ADVANCES)
				bank_account.payday(1, event = "Paycheck advance")
				bank_account.paydays_to_skip += 1
			return TRUE
		if("change_pay_mod")
			var/old_modifier = bank_account.payday_modifier
			bank_account.payday_modifier = clamp(round(text2num(params["pay_mod"]), 0.05), MIN_PAY_MOD, MAX_PAY_MOD)
			var/new_check_total = bank_account.payday_modifier * bank_account.account_job.paycheck
			var/raise_or_cut = new_check_total > old_modifier * bank_account.account_job.paycheck ? "raised" : "cut"
			bank_account.bank_card_talk("Paycheck [raise_or_cut] to [new_check_total][MONEY_SYMBOL].", force = TRUE)
			SSeconomy.add_audit_entry(bank_account, new_check_total, "Paycheck [raise_or_cut]")
			return TRUE
	*/ // BLASTWAVE EDIT REMOVAL END
	switch(action)
		// BLASTWAVE EDIT ADDITION START - STATION_TREASURY
		if("paycheck_advance")
			if(bank_account.issue_paycheck_advance(MAX_ADVANCES))
				log_econ("[key_name(ui.user)] authorized a paycheck advance for [bank_account.account_holder].")
			else
				balloon_alert(ui.user, "advance failed")
			return TRUE
		if("change_pay")
			var/old_check_total = bank_account.get_recurring_paycheck()
			var/new_check_total = bank_account.set_recurring_paycheck(text2num(params["pay"]))
			var/raise_or_cut = new_check_total > old_check_total ? "raised" : "cut"
			bank_account.bank_card_talk("Paycheck [raise_or_cut] to [new_check_total][MONEY_SYMBOL].", force = TRUE)
			SSeconomy.add_audit_entry(bank_account, new_check_total, "Paycheck [raise_or_cut]")
			log_econ("[key_name(ui.user)] [raise_or_cut] [bank_account.account_holder]'s recurring paycheck from [old_check_total] to [new_check_total] [MONEY_NAME].")
			return TRUE
		if("reset_pay")
			var/old_check_total = bank_account.get_recurring_paycheck()
			var/new_check_total = bank_account.reset_recurring_paycheck()
			bank_account.bank_card_talk("Paycheck reset to [new_check_total][MONEY_SYMBOL].", force = TRUE)
			SSeconomy.add_audit_entry(bank_account, new_check_total, "Paycheck reset")
			log_econ("[key_name(ui.user)] reset [bank_account.account_holder]'s recurring paycheck from [old_check_total] to [new_check_total] [MONEY_NAME].")
			return TRUE
		// BLASTWAVE EDIT ADDITION END

#undef MAX_ADVANCES
// BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: #undef MIN_PAY_MOD
// BLASTWAVE EDIT REMOVAL - STATION_TREASURY - ORIGINAL: #undef MAX_PAY_MOD
