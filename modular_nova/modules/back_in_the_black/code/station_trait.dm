/// Returns the running Back in the Black trait, if any.
/proc/get_back_in_the_black() as /datum/station_trait/back_in_the_black
	return locate(/datum/station_trait/back_in_the_black) in SSstation.station_traits

/// Formats a credit amount with thousands separators, e.g. 12340 -> "12,340".
/proc/bitb_credits(amount)
	amount = round(amount)
	var/sign = amount < 0 ? "-" : ""
	var/digits = num2text(abs(amount), 20)
	var/list/groups = list()
	while(length(digits) > 3)
		groups.Insert(1, copytext(digits, -3))
		digits = copytext(digits, 1, -3)
	groups.Insert(1, digits)
	return "[sign][jointext(groups, ",")]"

/datum/station_trait/back_in_the_black
	name = "Back in the Black"
	trait_type = STATION_TRAIT_NEUTRAL
	show_in_report = TRUE
	weight = 3
	trait_processes = TRUE
	trait_to_give = STATION_TRAIT_BACK_IN_THE_BLACK
	report_message = "Nanotrasen is broke and needs YOUR help. Research and exploration are suspended; today is about MONEY. \
		See the Office of Fiscal Recovery memorandum printed at your communications console."

	/// Seats claimed by Neuro Fiscal Trackers and not yet voided.
	var/active_seats = 0
	/// Admin-set goal that replaces the seat formula while set.
	var/goal_override
	/// HTML-encoded heading shown on the overlay.
	var/goal_label = BITB_DEFAULT_GOAL_LABEL
	/// Qualifying external revenue this shift.
	var/earned = 0
	/// source name -> credits contributed
	var/list/income_by_source = list()
	/// Weakrefs to every Neuro Fiscal Tracker that has registered with us.
	var/list/datum/weakref/implants = list()
	/// Sum of venue income already counted.
	var/venue_baseline = 0
	/// Auto-implant roundstart spawns until the round has started.
	var/roundstart_window_open = TRUE
	/// Whether the goal-reached announcement has already played.
	var/goal_announced = FALSE
	/// Set once pay_out() has run; freezes all further changes.
	var/paid_out = FALSE

/datum/station_trait/back_in_the_black/New()
	. = ..()
	venue_baseline = total_venue_income()
	if(SSticker.HasRoundStarted())
		roundstart_window_open = FALSE
		return
	RegisterSignal(SSdcs, COMSIG_GLOB_JOB_AFTER_SPAWN, PROC_REF(on_job_after_spawn))

/datum/station_trait/back_in_the_black/Destroy()
	UnregisterSignal(SSdcs, COMSIG_GLOB_JOB_AFTER_SPAWN)
	STOP_PROCESSING(SSstation, src)
	implants.Cut()
	return ..()

/datum/station_trait/back_in_the_black/proc/on_job_after_spawn(datum/source, datum/job/job, mob/living/spawned, client/player_client)
	SIGNAL_HANDLER
	if(!roundstart_window_open || !iscarbon(spawned))
		return
	var/obj/item/implant/neuro_fiscal_tracker/tracker = new()
	if(!tracker.implant(spawned, null, silent = TRUE, force = TRUE))
		qdel(tracker)

/datum/station_trait/back_in_the_black/on_round_start()
	. = ..()
	close_roundstart_window()
	INVOKE_ASYNC(src, PROC_REF(print_memo))

/// Stops auto-implanting spawns and starts counting venue income from now.
/datum/station_trait/back_in_the_black/proc/close_roundstart_window()
	roundstart_window_open = FALSE
	UnregisterSignal(SSdcs, COMSIG_GLOB_JOB_AFTER_SPAWN)
	venue_baseline = total_venue_income()

/datum/station_trait/back_in_the_black/proc/get_goal()
	if(!isnull(goal_override))
		return goal_override
	return max(BITB_MIN_GOAL, active_seats * BITB_GOAL_PER_CREW)

/datum/station_trait/back_in_the_black/proc/goal_met()
	return earned >= get_goal()

/datum/station_trait/back_in_the_black/proc/register_implant(obj/item/implant/neuro_fiscal_tracker/tracker)
	implants |= WEAKREF(tracker)

/datum/station_trait/back_in_the_black/proc/unregister_implant(obj/item/implant/neuro_fiscal_tracker/tracker)
	implants -= WEAKREF(tracker)

/// Implanted mobs currently carrying an Active tracker.
/datum/station_trait/back_in_the_black/proc/get_holders()
	var/list/holders = list()
	for(var/datum/weakref/tracker_ref as anything in implants)
		var/obj/item/implant/neuro_fiscal_tracker/tracker = tracker_ref.resolve()
		if(isnull(tracker) || tracker.seat_state != BITB_SEAT_ACTIVE || isnull(tracker.imp_in))
			continue
		holders |= tracker.imp_in
	return holders

/datum/station_trait/back_in_the_black/proc/message_holders(message)
	for(var/mob/living/holder as anything in get_holders())
		to_chat(holder, message)

/datum/station_trait/back_in_the_black/proc/redraw(amount, source)
	SEND_SIGNAL(src, COMSIG_BITB_PROGRESS, earned, get_goal(), goal_label, amount, source)
	check_goal_announcement()

/datum/station_trait/back_in_the_black/proc/check_goal_announcement()
	if(goal_announced || !goal_met() || !SSticker.HasRoundStarted())
		return
	goal_announced = TRUE
	priority_announce(
		"Shift revenue target of [bitb_credits(get_goal())] cr reached. The Alive Associate Return Program payout is unlocked. \
			Associates are reminded that membership requires being alive at end of shift.",
		"Office of Fiscal Recovery",
		has_important_message = TRUE,
		color_override = "green",
	)

/datum/station_trait/back_in_the_black/proc/claim_seat(obj/item/implant/neuro_fiscal_tracker/tracker, mob/living/holder)
	if(paid_out)
		return FALSE
	active_seats++
	register_implant(tracker)
	if(!roundstart_window_open)
		message_holders(span_notice("<b>NFT:</b> A new associate has joined. Target raised to [bitb_credits(get_goal())] cr."))
	redraw()
	return TRUE

/datum/station_trait/back_in_the_black/proc/release_seat(obj/item/implant/neuro_fiscal_tracker/tracker, holder_name, mob/living/voided_by)
	if(paid_out || active_seats <= 0)
		return FALSE
	active_seats--
	unregister_implant(tracker)
	message_holders(span_notice("<b>NFT:</b> [holder_name] has been let go. Target lowered to [bitb_credits(get_goal())] cr."))
	log_econ("[key_name(voided_by)] voided the Neuro Fiscal Tracker of [holder_name]. Seats: [active_seats], goal: [get_goal()].")
	redraw()
	return TRUE

/datum/station_trait/back_in_the_black/proc/add_income(amount, source)
	if(paid_out || amount <= 0)
		return
	earned += amount
	income_by_source[source] = (income_by_source[source] || 0) + amount
	log_econ("Back in the Black: +[amount] from [source]. Earned [earned] / [get_goal()].")
	redraw(amount, source)

/datum/station_trait/back_in_the_black/proc/total_venue_income()
	var/total = 0
	for(var/venue_path in SSrestaurant.all_venues)
		var/datum/venue/venue = SSrestaurant.all_venues[venue_path]
		total += venue.total_income
	return total

/datum/station_trait/back_in_the_black/process(seconds_per_tick)
	if(roundstart_window_open || paid_out)
		return
	var/venue_total = total_venue_income()
	var/delta = venue_total - venue_baseline
	if(delta <= 0)
		return
	venue_baseline = venue_total
	add_income(delta, "Service")

/// Credits the AARP payout to every eligible associate. Runs once.
/datum/station_trait/back_in_the_black/proc/pay_out()
	if(paid_out)
		return FALSE
	paid_out = TRUE
	var/goal = get_goal()
	if(!goal_met())
		log_econ("Back in the Black: target missed, [earned] / [goal]. No AARP payout.")
		priority_announce(
			"Shift revenue closed at [bitb_credits(earned)] of [bitb_credits(goal)] cr. The target was not met, and no Alive Associate Return Program payout will be made.",
			"Office of Fiscal Recovery",
		)
		return FALSE

	var/list/eligible_uuids = get_eligible_uuids()
	if(!length(eligible_uuids))
		log_econ("Back in the Black: target met ([earned] / [goal]) but no eligible associates.")
		priority_announce("The AARP regrets that it has no living members to pay.", "Office of Fiscal Recovery")
		return FALSE

	var/share = round(earned * BITB_BONUS_FRACTION / length(eligible_uuids))
	if(share <= 0)
		return FALSE
	var/round_id = SScharacter_ledger.current_round_id()
	var/paid = 0
	for(var/uuid in eligible_uuids)
		var/datum/character_ledger_result/result = SScharacter_ledger.try_credit(
			uuid,
			share,
			LEDGER_CHANNEL_SHAREHOLDER_BONUS,
			"AARP disbursement",
			"bitb:[round_id]:[uuid]",
		)
		if(!result.success)
			log_sql("Back in the Black: AARP credit failed for [uuid]: [result.reason]")
			continue
		paid++
	log_econ("Back in the Black: target met ([earned] / [goal]). Paid [share] to [paid] of [length(eligible_uuids)] associates.")
	priority_announce(
		"Alive Associate Return Program disbursement: [bitb_credits(share)] cr to each of [paid] living members.",
		"Office of Fiscal Recovery",
		color_override = "green",
	)
	return TRUE

/// Character UUIDs of living associates with an Active tracker installed.
/datum/station_trait/back_in_the_black/proc/get_eligible_uuids()
	var/list/uuids = list()
	for(var/mob/living/holder as anything in get_holders())
		if(holder.stat == DEAD || !holder.mind?.character_uuid)
			continue
		uuids |= holder.mind.character_uuid
	return uuids

/datum/station_trait/back_in_the_black/proc/admin_set_goal(amount)
	if(paid_out)
		return FALSE
	goal_override = max(1, round(amount))
	redraw()
	return TRUE

/datum/station_trait/back_in_the_black/proc/admin_reset_goal()
	if(paid_out)
		return FALSE
	goal_override = null
	redraw()
	return TRUE

/// Replaces the overlay heading; blank text restores the default.
/datum/station_trait/back_in_the_black/proc/admin_set_label(raw_label)
	if(paid_out)
		return FALSE
	var/clean_label = trim(raw_label, BITB_GOAL_LABEL_MAX_LEN + 1)
	goal_label = length(clean_label) ? html_encode(clean_label) : BITB_DEFAULT_GOAL_LABEL
	redraw()
	return TRUE

/datum/station_trait/back_in_the_black/proc/admin_set_earned(amount)
	if(paid_out)
		return FALSE
	amount = max(0, round(amount))
	income_by_source["Admin adjustment"] = (income_by_source["Admin adjustment"] || 0) + (amount - earned)
	earned = amount
	redraw()
	return TRUE
