ADMIN_VERB(back_in_the_black_controls, R_ADMIN, "Back in the Black Controls", "Set the shareholder goal, progress, or overlay text.", ADMIN_CATEGORY_EVENTS)
	var/datum/station_trait/back_in_the_black/trait = get_back_in_the_black()
	if(isnull(trait))
		to_chat(user, span_warning("Back in the Black is not active this round."))
		return
	if(trait.paid_out)
		to_chat(user, span_warning("Back in the Black has already paid out; the ledger is closed."))
		return

	var/goal_desc = isnull(trait.goal_override) ? "automatic, [trait.active_seats] seats" : "admin override"
	var/action = tgui_input_list(user, "\"[trait.goal_label]\": [trait.earned] / [trait.get_goal()] cr ([goal_desc]).", "Back in the Black", list("Set goal", "Reset goal to automatic", "Set progress", "Set goal text"))
	if(isnull(action) || QDELETED(trait))
		return

	var/log_text
	switch(action)
		if("Set goal")
			var/amount = tgui_input_number(user, "New shareholder goal (cr)", "Back in the Black", trait.get_goal(), 100000000, 1)
			if(isnull(amount) || QDELETED(trait) || !trait.admin_set_goal(amount))
				return
			log_text = "set the Back in the Black goal to [trait.get_goal()] cr"
		if("Reset goal to automatic")
			if(!trait.admin_reset_goal())
				return
			log_text = "reset the Back in the Black goal to automatic ([trait.get_goal()] cr)"
		if("Set progress")
			var/amount = tgui_input_number(user, "New earned total (cr)", "Back in the Black", trait.earned, 100000000, 0)
			if(isnull(amount) || QDELETED(trait) || !trait.admin_set_earned(amount))
				return
			log_text = "set Back in the Black progress to [trait.earned] cr"
		if("Set goal text")
			var/new_label = tgui_input_text(user, "Overlay heading, e.g. \"Pay Speeding Ticket\". Leave blank for the default.", "Back in the Black", html_decode(trait.goal_label), BITB_GOAL_LABEL_MAX_LEN, encode = FALSE)
			if(isnull(new_label) || QDELETED(trait) || !trait.admin_set_label(new_label))
				return
			log_text = "set the Back in the Black goal text to \"[trait.goal_label]\""
		else
			return

	log_admin("[key_name(user)] [log_text].")
	message_admins("[key_name_admin(user)] [log_text].")
	BLACKBOX_LOG_ADMIN_VERB("Back in the Black Controls")
