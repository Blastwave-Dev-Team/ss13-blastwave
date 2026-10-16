/// Zero-pads a 0-9999 PIN to four digits for display and memory.
/proc/format_atm_pin(pin)
	var/num = isnum(pin) ? pin : text2num(pin)
	if(isnull(num))
		num = 0
	return add_leading("[num]", 4, "0")

/// TRUE when `submitted` is the PIN on `user`'s mind. Same check the ATM uses.
/proc/atm_pin_matches(mob/user, submitted)
	if(isnull(user?.mind?.atm_pin))
		return FALSE
	var/entered = isnum(submitted) ? submitted : text2num(submitted)
	if(isnull(entered))
		return FALSE
	return entered == user.mind.atm_pin

/**
 * `human`'s personal account, when `id_card` is registered to it, or null.
 * Without a card, the ID they are wearing or holding is checked.
 */
/proc/personal_id_matches(mob/living/carbon/human/human, obj/item/card/id/id_card)
	var/datum/bank_account/personal = SScharacter_ledger.get_personal_account(human)
	if(!personal)
		return null
	id_card ||= human.get_idcard(TRUE)
	if(!id_card || id_card.registered_account != personal)
		return null
	return personal

/datum/preference/numeric/atm_pin
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_key = "atm_pin"
	savefile_identifier = PREFERENCE_CHARACTER
	can_randomize = FALSE
	should_update_preview = FALSE
	minimum = ATM_PIN_MIN
	maximum = ATM_PIN_MAX

/datum/preference/numeric/atm_pin/create_informed_default_value(datum/preferences/preferences)
	return rand(minimum, maximum)

/datum/preference/numeric/atm_pin/apply_to_human(mob/living/carbon/human/target, value, datum/preferences/preferences)
	if(!target.mind)
		return
	SScharacter_ledger.remember_atm_pin(target.mind, value)
