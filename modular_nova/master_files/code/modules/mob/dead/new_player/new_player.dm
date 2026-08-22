/mob/dead/new_player/create_character(atom/destination)
	. = ..()
	if(!client)
		return
	var/mob/living/spawning_mob = .
	if(!spawning_mob?.mind || isAI(spawning_mob))
		return
	spawning_mob.mind.character_uuid = client.prefs.character_uuid
	if(!ishuman(spawning_mob))
		return
	SScharacter_ledger.ensure_identity(spawning_mob)
	SScharacter_ledger.remember_atm_pin(spawning_mob.mind, client.prefs.read_preference(/datum/preference/numeric/atm_pin))

/mob/dead/new_player/transfer_character()
	if(iscyborg(new_character))
		var/mutable_appearance/character_appearance = new(new_character.appearance)
		GLOB.name_to_appearance[new_character.real_name] = character_appearance // Cache this for Character Directory
	return ..()
