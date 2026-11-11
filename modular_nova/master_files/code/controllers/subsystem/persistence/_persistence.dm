/datum/controller/subsystem/persistence/collect_data()
	. = ..()
	get_back_in_the_black()?.pay_out()
	SScharacter_ledger.collect_round_end()
