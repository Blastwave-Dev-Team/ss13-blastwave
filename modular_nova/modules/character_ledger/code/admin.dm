ADMIN_VERB(adjust_character_ledger, R_ADMIN, "Adjust Character Ledger", "Credit or debit a character's persistent credit ledger.", ADMIN_CATEGORY_MAIN)
	var/lookup_mode = tgui_alert(user, "Look up by UUID or by ckey and slot?", "Character Ledger", list("UUID", "Ckey + Slot", "Cancel"))
	if(lookup_mode == "Cancel" || isnull(lookup_mode))
		return
	var/uuid
	if(lookup_mode == "UUID")
		uuid = tgui_input_text(user, "Character UUID", "Character Ledger")
	else
		var/ckey_value = tgui_input_text(user, "Ckey", "Character Ledger")
		var/slot = tgui_input_number(user, "Character slot", "Character Ledger", 1, 30, 1)
		if(!ckey_value || isnull(slot))
			return
		uuid = SScharacter_ledger.lookup_uuid(ckey_value, slot)
		if(!uuid)
			to_chat(user, span_warning("No character identity found for [ckey(ckey_value)] slot [slot]."))
			return
	uuid = trim(uuid)
	if(!uuid)
		return

	var/action = tgui_alert(user, "Credit or debit [uuid]? Current balance: [SScharacter_ledger.get_balance(uuid)]", "Character Ledger", list("Credit", "Debit", "Cancel"))
	if(action == "Cancel" || isnull(action))
		return
	var/amount = tgui_input_number(user, "[action] amount", "Character Ledger", 1, 1000000, 1)
	if(!amount)
		return
	var/reason = tgui_input_text(user, "Reason", "Character Ledger", "Admin seed") || "Admin seed"
	var/idempotency_key = "admin:[GLOB.round_id]:[uuid]:[world.time]:[amount]:[action]"
	var/datum/character_ledger_result/result
	if(action == "Credit")
		result = SScharacter_ledger.try_credit(uuid, amount, LEDGER_CHANNEL_ADMIN_SEED, reason, idempotency_key)
	else
		result = SScharacter_ledger.try_debit(uuid, amount, LEDGER_CHANNEL_ADMIN_SEED, reason, idempotency_key)
	if(!result.success)
		to_chat(user, span_warning("Ledger [action] failed: [result.reason] ([result.status])"))
		return
	to_chat(user, span_notice("Ledger [action] of [amount] applied. Balance is now [result.balance_after]."))
<<<<<<< HEAD
	log_admin("[key_name(user)] [LOWER_TEXT(action)]ed [amount] on character ledger [uuid]. Reason: [reason]. Balance: [result.balance_after].")
	message_admins("[key_name_admin(user)] [LOWER_TEXT(action)]ed [amount] on character ledger [uuid]. Balance: [result.balance_after].")
=======
	log_admin("[key_name(user)] [lowertext(action)]ed [amount] on character ledger [uuid]. Reason: [reason]. Balance: [result.balance_after].")
	message_admins("[key_name_admin(user)] [lowertext(action)]ed [amount] on character ledger [uuid]. Balance: [result.balance_after].")
>>>>>>> 6000c5949e9d64b60952f72dae6d90fafa49048d
	BLACKBOX_LOG_ADMIN_VERB("Adjust Character Ledger")
