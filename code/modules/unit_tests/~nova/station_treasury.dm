/// Verifies that the station reserve is isolated from operating and player accounts.
/datum/unit_test/station_treasury_boundaries

/datum/unit_test/station_treasury_boundaries/Run()
	var/datum/bank_account/station_reserve/reserve = SSeconomy.get_station_reserve()
	TEST_ASSERT_NOTNULL(reserve, "Economy subsystem did not create a station reserve.")
	TEST_ASSERT(!(reserve in SSeconomy.departmental_accounts), "Station reserve was registered as a department account.")
	TEST_ASSERT(!(reserve in assoc_to_values(SSeconomy.bank_accounts_by_id)), "Station reserve was registered as a player account.")
	for(var/obj/item/card/id/departmental_budget/budget_card as anything in SSeconomy.dep_cards)
		TEST_ASSERT_NOTEQUAL(budget_card.registered_account, reserve, "A department card was linked to the station reserve.")

	var/obj/machinery/computer/bank_machine/bank_machine = allocate(/obj/machinery/computer/bank_machine)
	TEST_ASSERT_EQUAL(bank_machine.synced_bank_account, reserve, "Bank machine did not bind to the station reserve.")

/// Verifies the 25% station margin and independently sourced non-station funding.
/datum/unit_test/station_treasury_funding

/datum/unit_test/station_treasury_funding/Run()
	var/datum/bank_account/station_reserve/reserve = SSeconomy.get_station_reserve()
	var/datum/bank_account/department/ds2 = SSeconomy.get_dep_account(ACCOUNT_DS2)
	var/datum/bank_account/department/interdyne = SSeconomy.get_dep_account(ACCOUNT_INT)
	var/datum/bank_account/department/tarkon = SSeconomy.get_dep_account(ACCOUNT_TI)
	var/old_reserve_balance = reserve.account_balance
	var/old_ds2_balance = ds2.account_balance
	var/old_interdyne_balance = interdyne.account_balance
	var/old_tarkon_balance = tarkon.account_balance

	SSeconomy.fund_station_treasury(400, "Unit test")
	var/reserve_delta = reserve.account_balance - old_reserve_balance
	SSeconomy.fund_independent_account(ds2, 101, "Unit test")
	SSeconomy.fund_independent_account(interdyne, 202, "Unit test")
	SSeconomy.fund_independent_account(tarkon, 303, "Unit test")
	var/ds2_delta = ds2.account_balance - old_ds2_balance
	var/interdyne_delta = interdyne.account_balance - old_interdyne_balance
	var/tarkon_delta = tarkon.account_balance - old_tarkon_balance

	reserve.account_balance = old_reserve_balance
	ds2.account_balance = old_ds2_balance
	interdyne.account_balance = old_interdyne_balance
	tarkon.account_balance = old_tarkon_balance

	TEST_ASSERT_EQUAL(reserve_delta, 500, "Station remittance did not retain a 25% margin.")
	TEST_ASSERT_EQUAL(ds2_delta, 101, "DS-2 did not receive only its own remittance.")
	TEST_ASSERT_EQUAL(interdyne_delta, 202, "Interdyne did not receive only its own remittance.")
	TEST_ASSERT_EQUAL(tarkon_delta, 303, "Tarkon did not receive only its own remittance.")
	var/list/ds2_source = SSeconomy.independent_funding_sources[ACCOUNT_DS2]
	var/list/interdyne_source = SSeconomy.independent_funding_sources[ACCOUNT_INT]
	var/list/tarkon_source = SSeconomy.independent_funding_sources[ACCOUNT_TI]
	TEST_ASSERT_NOTEQUAL(ds2_source["name"], interdyne_source["name"], "DS-2 and Interdyne shared a funding source.")
	TEST_ASSERT_NOTEQUAL(interdyne_source["name"], tarkon_source["name"], "Interdyne and Tarkon shared a funding source.")

/// Verifies department-funded base pay, reserve uplift, and shortage behavior.
/datum/unit_test/station_treasury_payroll

/datum/unit_test/station_treasury_payroll/Run()
	var/datum/job/test_job = new
	test_job.paycheck = PAYCHECK_CREW
	test_job.paycheck_department = ACCOUNT_CIV
	var/datum/bank_account/test_account = new("Treasury Test", test_job, 1, FALSE)
	test_account.set_recurring_paycheck(75)
	var/datum/bank_account/department/department_account = SSeconomy.get_dep_account(ACCOUNT_CIV)
	var/datum/bank_account/department/independent_account = SSeconomy.get_dep_account(ACCOUNT_DS2)
	var/datum/bank_account/station_reserve/reserve = SSeconomy.get_station_reserve()
	var/old_department_balance = department_account.account_balance
	var/old_independent_balance = independent_account.account_balance
	var/old_reserve_balance = reserve.account_balance

	department_account.account_balance = 1000
	reserve.account_balance = 1000
	var/full_payday_succeeded = test_account.payday(1)
	var/full_payday_balance = test_account.account_balance
	var/full_department_balance = department_account.account_balance
	var/full_reserve_balance = reserve.account_balance

	test_account.account_balance = 0
	department_account.account_balance = 1000
	reserve.account_balance = 0
	var/base_only_succeeded = test_account.payday(1)
	var/base_only_balance = test_account.account_balance
	var/uplift_was_missed = test_account.last_payday_uplift_missed

	test_account.account_balance = 0
	test_account.paydays_to_skip = 0
	department_account.account_balance = 0
	reserve.account_balance = 1000
	var/failed_advance = test_account.issue_paycheck_advance(3)
	var/skips_after_failure = test_account.paydays_to_skip

	department_account.account_balance = 1000
	var/successful_advance = test_account.issue_paycheck_advance(3)
	var/skips_after_success = test_account.paydays_to_skip

	test_account.account_balance = 0
	test_job.paycheck_department = ACCOUNT_DS2
	independent_account.account_balance = 1000
	reserve.account_balance = 1000
	var/independent_payday_succeeded = test_account.payday(1)
	var/independent_payday_balance = test_account.account_balance
	var/independent_balance_after_payday = independent_account.account_balance
	var/reserve_after_independent_payday = reserve.account_balance

	department_account.account_balance = old_department_balance
	independent_account.account_balance = old_independent_balance
	reserve.account_balance = old_reserve_balance
	qdel(test_account)
	qdel(test_job)

	TEST_ASSERT(full_payday_succeeded, "A fully funded split payday failed.")
	TEST_ASSERT_EQUAL(full_payday_balance, 75, "Split payday did not credit the combined amount once.")
	TEST_ASSERT_EQUAL(full_department_balance, 950, "Department did not fund exactly the 50-credit base.")
	TEST_ASSERT_EQUAL(full_reserve_balance, 975, "Reserve did not fund exactly the 25-credit uplift.")
	TEST_ASSERT(base_only_succeeded, "Reserve shortage prevented the department-funded base payday.")
	TEST_ASSERT_EQUAL(base_only_balance, 50, "Reserve shortage did not fall back to base pay.")
	TEST_ASSERT(uplift_was_missed, "Reserve shortage was not recorded on the account.")
	TEST_ASSERT(!failed_advance, "Advance succeeded without department base funds.")
	TEST_ASSERT_EQUAL(skips_after_failure, 0, "Failed advance consumed a future payday.")
	TEST_ASSERT(successful_advance, "Funded advance failed.")
	TEST_ASSERT_EQUAL(skips_after_success, 1, "Successful advance did not consume one future payday.")
	TEST_ASSERT(independent_payday_succeeded, "Independent-source payday failed.")
	TEST_ASSERT_EQUAL(independent_payday_balance, 75, "Independent source did not fund its full salary.")
	TEST_ASSERT_EQUAL(independent_balance_after_payday, 925, "Independent salary crossed into another funding source.")
	TEST_ASSERT_EQUAL(reserve_after_independent_payday, 1000, "Station reserve funded an independent account salary.")
