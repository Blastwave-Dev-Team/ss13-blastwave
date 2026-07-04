/// How objective-specific equipment (nuke core kit, supermatter kit, etc.) should be delivered to an antag.
/datum/preference/choiced/objective_equipment_delivery
	category = PREFERENCE_CATEGORY_NON_CONTEXTUAL
	savefile_identifier = PREFERENCE_CHARACTER
	savefile_key = "objective_equipment_delivery"
	can_randomize = FALSE
	should_update_preview = FALSE

/datum/preference/choiced/objective_equipment_delivery/init_possible_values()
	return list(OBJECTIVE_EQUIPMENT_BACKPACK, OBJECTIVE_EQUIPMENT_POD)

/datum/preference/choiced/objective_equipment_delivery/compile_constant_data()
	var/list/data = ..()

	data[CHOICED_PREFERENCE_DISPLAY_NAMES] = list(
		OBJECTIVE_EQUIPMENT_BACKPACK = "Backpack (fallback to pod)",
		OBJECTIVE_EQUIPMENT_POD = "Uplink Supply Pod",
	)

	return data

/datum/preference/choiced/objective_equipment_delivery/create_default_value()
	return OBJECTIVE_EQUIPMENT_BACKPACK

/datum/preference/choiced/objective_equipment_delivery/apply_to_human(mob/living/carbon/human/target, value)
	return
