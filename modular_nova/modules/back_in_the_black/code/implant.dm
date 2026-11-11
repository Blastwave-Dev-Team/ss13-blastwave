/obj/item/implant/neuro_fiscal_tracker
	name = "Interdyne Neuro Fiscal Tracker"
	desc = "A cranial implant that projects a live fundraising overlay into the wearer's field of vision. \
		Leased to Nanotrasen by Interdyne Pharmaceutics under a fiscal recovery agreement."
	actions_types = null
	allow_multiple = FALSE
	implant_color = "r"
	implant_info = "Interdyne Neuro Fiscal Tracker (NFT). Enrolls the wearer in the shift revenue drive and the Alive Associate Return Program. \
		A removed unit stays enrolled until voided with Captain-level authorization."
	implant_lore = "Seated against the frontal lobe, the NFT reads nothing and reports nothing, according to Interdyne. \
		Full instructions are in the NFT Associate Handbook, printable at any library console."
	/// One of BITB_SEAT_PENDING, BITB_SEAT_ACTIVE, BITB_SEAT_VOIDED.
	var/seat_state = BITB_SEAT_PENDING
	/// Real name of whoever claimed this unit's seat.
	var/seat_holder_name
	/// Overlay shown to the current wearer.
	var/atom/movable/screen/bitb_goal_bar/bar

/obj/item/implant/neuro_fiscal_tracker/examine(mob/user)
	. = ..()
	switch(seat_state)
		if(BITB_SEAT_ACTIVE)
			. += span_notice("It is enrolled to [seat_holder_name]. A Captain-access ID can void a removed unit.")
		if(BITB_SEAT_VOIDED)
			. += span_warning("It has been voided and will not enroll anyone again.")
	. += span_notice("See the NFT Associate Handbook (ugc/interdyne-neuro-fiscal-tracker) at any library console.")

/obj/item/implant/neuro_fiscal_tracker/implant(mob/living/target, mob/user, silent = FALSE, force = FALSE)
	if(seat_state == BITB_SEAT_VOIDED)
		if(user)
			balloon_alert(user, "unit voided!")
		return FALSE
	. = ..()
	if(!. || QDELETED(src) || imp_in != target)
		return
	var/datum/station_trait/back_in_the_black/trait = get_back_in_the_black()
	if(isnull(trait))
		return
	if(seat_state == BITB_SEAT_PENDING && target.stat != DEAD && trait.claim_seat(src, target))
		seat_state = BITB_SEAT_ACTIVE
		seat_holder_name = target.real_name
	if(seat_state != BITB_SEAT_ACTIVE)
		return
	trait.register_implant(src)
	RegisterSignal(trait, COMSIG_BITB_PROGRESS, PROC_REF(on_progress))
	RegisterSignal(target, COMSIG_MOB_HUD_CREATED, PROC_REF(on_hud_created))
	attach_bar(target)

/obj/item/implant/neuro_fiscal_tracker/removed(mob/living/source, silent = FALSE, special = FALSE)
	detach_bar(source)
	UnregisterSignal(source, COMSIG_MOB_HUD_CREATED)
	var/datum/station_trait/back_in_the_black/trait = get_back_in_the_black()
	if(trait)
		UnregisterSignal(trait, COMSIG_BITB_PROGRESS)
	return ..()

/obj/item/implant/neuro_fiscal_tracker/Destroy(force)
	get_back_in_the_black()?.unregister_implant(src)
	. = ..()
	QDEL_NULL(bar)

/obj/item/implant/neuro_fiscal_tracker/proc/attach_bar(mob/living/target)
	var/datum/hud/hud = target.hud_used
	if(isnull(hud) || !isnull(bar))
		return
	var/datum/station_trait/back_in_the_black/trait = get_back_in_the_black()
	if(isnull(trait))
		return
	bar = new(null, hud)
	hud.add_screen_object(bar, group_key = HUD_GROUP_INFO)
	target.client?.screen += bar
	bar.update_progress(trait.earned, trait.get_goal(), trait.goal_label)

/obj/item/implant/neuro_fiscal_tracker/proc/detach_bar(mob/living/target)
	if(isnull(bar))
		return
	target?.client?.screen -= bar
	QDEL_NULL(bar)

/obj/item/implant/neuro_fiscal_tracker/proc/on_hud_created(mob/living/source)
	SIGNAL_HANDLER
	QDEL_NULL(bar)
	attach_bar(source)

/obj/item/implant/neuro_fiscal_tracker/proc/on_progress(datum/source, earned, goal, goal_label, amount, income_source)
	SIGNAL_HANDLER
	bar?.update_progress(earned, goal, goal_label, amount, income_source)

/// Returns null if `id` may void this unit, otherwise a short reason it can't.
/obj/item/implant/neuro_fiscal_tracker/proc/void_refusal(obj/item/card/id/id)
	if(seat_state == BITB_SEAT_VOIDED)
		return "already voided"
	if(seat_state != BITB_SEAT_ACTIVE)
		return "not enrolled"
	if(imp_in)
		return "remove it first"
	if(!(ACCESS_CAPTAIN in id?.GetAccess()))
		return "insufficient authority"
	return null

/obj/item/implant/neuro_fiscal_tracker/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	var/obj/item/card/id/id = tool.GetID()
	if(isnull(id))
		return ..()
	var/refusal = void_refusal(id)
	if(refusal == "insufficient authority")
		to_chat(user, span_warning("Insufficient authority to terminate associates."))
		return ITEM_INTERACT_BLOCKING
	if(refusal)
		balloon_alert(user, refusal)
		return ITEM_INTERACT_BLOCKING
	INVOKE_ASYNC(src, PROC_REF(prompt_void), user, tool)
	return ITEM_INTERACT_SUCCESS

/obj/item/implant/neuro_fiscal_tracker/proc/prompt_void(mob/living/user, obj/item/tool)
	var/answer = tgui_alert(user, "Void [seat_holder_name]'s contract? The target will drop by one associate's share, and this unit can never be enrolled again.", "Neuro Fiscal Tracker", list("Void", "Cancel"))
	if(answer != "Void" || QDELETED(src) || QDELETED(user) || QDELETED(tool))
		return
	if(!user.is_holding(tool) || void_refusal(tool.GetID()))
		return
	var/atom/reach_target = istype(loc, /obj/item/implantcase) ? loc : src
	if(!user.can_perform_action(reach_target, NEED_DEXTERITY))
		return
	if(void_contract(user))
		to_chat(user, span_notice("You void [seat_holder_name]'s Neuro Fiscal Tracker."))

/// Releases this unit's seat and bricks it. Returns TRUE on success.
/obj/item/implant/neuro_fiscal_tracker/proc/void_contract(mob/living/user)
	if(seat_state != BITB_SEAT_ACTIVE || imp_in)
		return FALSE
	var/datum/station_trait/back_in_the_black/trait = get_back_in_the_black()
	if(isnull(trait) || !trait.release_seat(src, seat_holder_name, user))
		return FALSE
	seat_state = BITB_SEAT_VOIDED
	name = "voided Interdyne Neuro Fiscal Tracker"
	if(istype(loc, /obj/item/implantcase))
		var/obj/item/implantcase/case = loc
		case.name = "implant case - 'VOIDED'"
	return TRUE
