/datum/bank_account
	/// HoP-authorized absolute recurring salary. Null preserves the legacy calculated paycheck.
	var/recurring_paycheck_override
	/// Whether the most recent payday omitted an authorized reserve-funded uplift.
	var/last_payday_uplift_missed = FALSE

/// Returns the legacy single-paycheck amount before an HoP override.
/datum/bank_account/proc/get_default_recurring_paycheck()
	if(!account_job)
		return 0
	return clamp(round(account_job.paycheck * payday_modifier), 0, PAYCHECK_CREW)

/// Returns the current effective recurring paycheck.
/datum/bank_account/proc/get_recurring_paycheck()
	if(isnull(recurring_paycheck_override))
		return get_default_recurring_paycheck()
	return clamp(recurring_paycheck_override, get_minimum_recurring_paycheck(), PAYCHECK_MAXIMUM)

/// Returns the existing job-relative floor for accounting-console pay cuts.
/datum/bank_account/proc/get_minimum_recurring_paycheck()
	if(!account_job)
		return 0
	return clamp(round(account_job.paycheck * PAYCHECK_MINIMUM_MODIFIER), 0, PAYCHECK_CREW)

/// Sets an explicit recurring salary and returns the sanitized amount.
/datum/bank_account/proc/set_recurring_paycheck(amount)
	recurring_paycheck_override = clamp(round(amount), get_minimum_recurring_paycheck(), PAYCHECK_MAXIMUM)
	return recurring_paycheck_override

/// Restores the salary calculated from job and inherent payday modifier.
/datum/bank_account/proc/reset_recurring_paycheck()
	recurring_paycheck_override = null
	return get_default_recurring_paycheck()

/// Pays one paycheck early and skips the next scheduled payday on success.
/datum/bank_account/proc/issue_paycheck_advance(max_advances, event = "Paycheck advance")
	if(paydays_to_skip >= max_advances)
		return FALSE
	if(!payday(1, event = event))
		return FALSE
	paydays_to_skip += 1
	return TRUE

/// The station's non-cardable reserve account, funded by Nanotrasen.
/datum/bank_account/station_reserve
	account_holder = ACCOUNT_STA_NAME
	add_to_accounts = FALSE

/datum/bank_account/station_reserve/New(initial_balance = 0)
	account_balance = initial_balance
	return ..(ACCOUNT_STA_NAME, null, 1, FALSE)

/datum/bank_account/station_reserve/adjust_money(amount, reason)
	. = ..()
	if(!.)
		return
	SSblackbox.record_feedback("amount", "station_reserve_balance", account_balance, world.time)
