/datum/job
	/// The job's outfit that will be assigned for Vox
	var/vox_outfit = null
	/// The job's outfit that will be assigned for Akula
	var/akula_outfit = null

/mob/living/carbon/human/on_job_equipping(datum/job/equipping, client/player_client)
	. = ..()
	if(!player_client || !mind)
		return
	SScharacter_ledger.remember_atm_pin(mind, player_client.prefs.read_preference(/datum/preference/numeric/atm_pin))
