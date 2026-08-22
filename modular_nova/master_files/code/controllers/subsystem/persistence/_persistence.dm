/datum/controller/subsystem/persistence/collect_data()
	. = ..()
	SScharacter_ledger.collect_round_end()
