/// Station departments funded through the Nanotrasen station reserve.
/datum/controller/subsystem/economy/var/list/station_department_accounts = list(
	ACCOUNT_CIV,
	ACCOUNT_ENG,
	ACCOUNT_SCI,
	ACCOUNT_MED,
	ACCOUNT_SRV,
	ACCOUNT_CAR,
	ACCOUNT_CMD,
	ACCOUNT_SEC,
)

/// Non-station accounts and their independent funding authorities.
/datum/controller/subsystem/economy/var/list/independent_funding_sources = list(
	ACCOUNT_DS2 = list(
		"name" = FUNDING_SOURCE_DS2,
		"periodic_grant" = MAX_GRANT_DPT,
	),
	ACCOUNT_INT = list(
		"name" = FUNDING_SOURCE_INT,
		"periodic_grant" = MAX_GRANT_DPT,
	),
	ACCOUNT_TI = list(
		"name" = FUNDING_SOURCE_TI,
		"periodic_grant" = MAX_GRANT_DPT,
	),
)

/// Nanotrasen-funded station reserve. This is not a department or player account.
/datum/controller/subsystem/economy/var/datum/bank_account/station_reserve/station_reserve_account

/// Additional fraction retained above each station allocation.
/datum/controller/subsystem/economy/var/station_reserve_margin = STATION_RESERVE_MARGIN

/// Returns the station reserve without exposing it as a department account.
/datum/controller/subsystem/economy/proc/get_station_reserve() as /datum/bank_account/station_reserve
	return station_reserve_account

/// Mints a Nanotrasen remittance containing an allocation and the retained reserve margin.
/datum/controller/subsystem/economy/proc/fund_station_treasury(allocation, reason)
	if(!station_reserve_account || allocation <= 0)
		return FALSE
	var/remittance = round(allocation * (1 + station_reserve_margin))
	station_reserve_account.adjust_money(remittance, reason)
	SSblackbox.record_feedback("amount", "nt_station_remittance", remittance)
	log_econ("Nanotrasen remitted [remittance] [MONEY_NAME] to the station reserve for [allocation] [MONEY_NAME] in allocations.")
	return TRUE

/// Transfers an allocation from the station reserve to one station department.
/datum/controller/subsystem/economy/proc/disburse_station_funds(datum/bank_account/department/department_account, amount, reason)
	if(!department_account || !(department_account.department_id in station_department_accounts))
		return FALSE
	if(!department_account.transfer_money(station_reserve_account, amount, reason))
		log_econ("Station reserve could not disburse [amount] [MONEY_NAME] to [department_account.account_holder].")
		return FALSE
	SSblackbox.record_feedback("amount", "station_department_disbursement", amount)
	return TRUE

/// Mints funding from the authority dedicated to one non-station account.
/datum/controller/subsystem/economy/proc/fund_independent_account(datum/bank_account/department/department_account, amount, reason)
	if(!department_account || amount <= 0)
		return FALSE
	var/list/funding_source = independent_funding_sources[department_account.department_id]
	if(!length(funding_source))
		stack_trace("Attempted to fund [department_account.department_id] without an independent funding source.")
		return FALSE
	var/funding_source_name = funding_source["name"]
	department_account.adjust_money(amount, "[funding_source_name]: [reason]")
	SSblackbox.record_feedback("amount", "[department_account.department_id]_independent_funding", amount)
	log_econ("[funding_source_name] remitted [amount] [MONEY_NAME] to [department_account.account_holder].")
	return TRUE
