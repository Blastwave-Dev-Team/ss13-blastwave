/obj/docking_port/mobile/supply/sell()
	var/datum/bank_account/cargo_budget = SSeconomy.get_dep_account(ACCOUNT_CAR)
	var/presale_points = cargo_budget?.account_balance
	. = ..()
	if(isnull(presale_points))
		return
	var/sale_income = cargo_budget.account_balance - presale_points
	if(sale_income > 0)
		get_back_in_the_black()?.add_income(sale_income, "Cargo Export")
