/// Zero-pads a 0-9999 PIN to four digits for display and memory.
/proc/format_atm_pin(pin)
	var/num = isnum(pin) ? pin : text2num(pin)
	if(isnull(num))
		num = 0
	return add_leading("[num]", 4, "0")

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
