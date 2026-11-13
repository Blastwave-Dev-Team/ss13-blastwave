// MODULE ID: OVERMAP
// Garage slots and ships handed out by staff: donator slots, event rewards, and
// admin corrections.

/**
 * Award a stock hull straight into a character's garage, with a slot to hold it.
 *
 * The ship brings its own EVENT grant, so an award never pushes a garage over
 * its limit. The grant is taken first, and withdrawn again if the hull cannot
 * be registered, so a failure leaves nothing behind. Returns the record id.
 */
/proc/shipyard_award_ship(datum/ship_listing/listing, owner_uuid, owner_ckey, ship_name, source, granted_by)
	if(!listing || !owner_uuid || !ckey(owner_ckey))
		return null
	var/grant_id = GLOB.ship_garage_slots.award_slots(owner_ckey, SHIP_SLOT_GRANT_EVENT, source || "Awarded [listing.name]", 1, granted_by)
	if(!grant_id)
		return null
	var/record_id = listing.register_new_hull(owner_uuid, owner_ckey, ship_name || listing.name, grant_id)
	if(!record_id)
		GLOB.ship_garage_slots.revoke_grant(grant_id)
		return null
	return record_id

/// The ckey and character an admin means, picked from who is online or typed in.
/proc/shipyard_admin_pick_owner(client/admin, need_character)
	var/list/choices = list()
	for(var/client/player as anything in GLOB.clients)
		var/label = "[player.ckey][player.mob?.real_name ? " ([player.mob.real_name])" : ""]"
		choices[label] = player
	var/choice = tgui_input_list(admin, "Whose garage? Cancel to type a ckey.", "Ship award", sort_list(choices))
	var/client/picked = choices[choice]
	var/target_ckey = picked ? picked.ckey : ckey(tgui_input_text(admin, "Ckey", "Ship award", max_length = 32))
	if(!target_ckey)
		return null
	var/target_uuid
	if(need_character)
		target_uuid = picked?.mob?.mind?.character_uuid
		if(!target_uuid)
			target_uuid = tgui_input_text(admin, "Character UUID the ship belongs to.", "Ship award", max_length = 36)
		if(!target_uuid)
			return null
	return list("ckey" = target_ckey, "uuid" = target_uuid)

ADMIN_VERB(award_garage_slots, R_ADMIN, "Award Garage Slots", "Give a player extra persistent ship garage slots.", ADMIN_CATEGORY_GAME)
	var/list/owner = shipyard_admin_pick_owner(user, FALSE)
	if(!owner)
		return
	var/kind = tgui_input_list(user, "What kind of award is this?", "Award Garage Slots", list(SHIP_SLOT_GRANT_DONATOR, SHIP_SLOT_GRANT_EVENT, SHIP_SLOT_GRANT_ADMIN))
	if(!kind)
		return
	var/count = tgui_input_number(user, "How many slots?", "Award Garage Slots", 1, 10, 1)
	if(!count)
		return
	var/source = tgui_input_text(user, "What is it for? The player sees this.", "Award Garage Slots", max_length = 128)
	if(!source)
		return
	var/grant_id = GLOB.ship_garage_slots.award_slots(owner["ckey"], kind, source, count, user.ckey)
	if(!grant_id)
		to_chat(user, span_warning("The grant could not be recorded. Is the database online?"))
		return
	log_admin("[key_name(user)] awarded [count] [kind] garage slot(s) to [owner["ckey"]]: [source] (grant [grant_id]).")
	message_admins("[key_name_admin(user)] awarded [count] [kind] garage slot(s) to [owner["ckey"]]: [source].")

ADMIN_VERB(award_ship, R_ADMIN, "Award Ship", "Place a stock hull, with a slot of its own, in a character's garage.", ADMIN_CATEGORY_GAME)
	var/list/owner = shipyard_admin_pick_owner(user, TRUE)
	if(!owner)
		return
	var/list/by_name = list()
	for(var/listing_id in shipyard_ship_listings())
		var/datum/ship_listing/listing = GLOB.ship_listings[listing_id]
		by_name[listing.name] = listing
	var/picked_name = tgui_input_list(user, "Which hull?", "Award Ship", sort_list(by_name))
	var/datum/ship_listing/listing = by_name[picked_name]
	if(!listing)
		return
	var/ship_name = tgui_input_text(user, "Ship name.", "Award Ship", listing.name, max_length = 48)
	if(!ship_name)
		return
	var/source = tgui_input_text(user, "What is it for? The player sees this.", "Award Ship", max_length = 128)
	if(!source)
		return
	var/record_id = shipyard_award_ship(listing, owner["uuid"], owner["ckey"], ship_name, source, user.ckey)
	if(!record_id)
		to_chat(user, span_warning("The ship could not be registered. Is the database online?"))
		return
	log_admin("[key_name(user)] awarded a [listing.name] named [ship_name] to [owner["ckey"]] ([owner["uuid"]]) as record [record_id]: [source].")
	message_admins("[key_name_admin(user)] awarded a [listing.name] named [ship_name] to [owner["ckey"]]: [source].")
