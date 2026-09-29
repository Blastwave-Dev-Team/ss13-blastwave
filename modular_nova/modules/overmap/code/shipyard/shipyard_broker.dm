// MODULE ID: OVERMAP
// The vessel broker: a counter that sells new hulls into the buyer's garage, or
// straight onto the pad it overlooks.
//
// A purchase is a registry row at revision 1 whose map is a copy of the stock
// hull, which is exactly what a first filing would have left behind. A pad
// delivery is then an ordinary retrieval of that row, so a bought ship and a
// stored one come out of the same load path and file back in the same way.

// Where a purchase goes, the TGUI contract.
#define SHIP_BROKER_DELIVERY_PAD "PAD"
#define SHIP_BROKER_DELIVERY_GARAGE "GARAGE"

/obj/machinery/computer/ship_broker
	name = "vessel broker"
	desc = "A vessel sales terminal. Sells registered hulls against the buyer's ledger, delivered to their garage or straight onto the pad."
	icon_screen = "shuttle"
	icon_keyboard = "tech_key"
	circuit = /obj/item/circuitboard/computer/ship_broker
	req_access = list()
	req_one_access = list()
	/// Operator, ledger and pad state, shared with the registrar.
	var/datum/shipyard_session/session
	/// Garage slots for the operator, refreshed with the session.
	var/list/slots

/obj/machinery/computer/ship_broker/Initialize(mapload, obj/item/circuitboard/C)
	. = ..()
	session = new(src)

/obj/machinery/computer/ship_broker/Destroy()
	QDEL_NULL(session)
	return ..()

/obj/machinery/computer/ship_broker/multitool_act(mob/living/user, obj/item/multitool/tool)
	var/result = session.try_link(user, tool)
	return isnull(result) ? ..() : result

/obj/machinery/computer/ship_broker/examine(mob/user)
	. = ..()
	. += session.examine_line()

/obj/machinery/computer/ship_broker/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(ui)
		return
	// The login screen reports registry state too, and a login has not refreshed it yet.
	session.refresh()
	ui = new(user, src, "ShipBroker", name)
	ui.open()

/obj/machinery/computer/ship_broker/ui_close(mob/user)
	. = ..()
	session.on_operator_leave(user)
	if(!authenticated)
		slots = null
		update_static_data_for_all_viewers()

/obj/machinery/computer/ship_broker/proc/refresh_session()
	session.refresh()
	slots = session.registry_online ? session.slot_usage() : null

/// Hulls the operator may buy. Restricted hulls are never sent to the client.
/obj/machinery/computer/ship_broker/proc/visible_listings()
	var/list/visible = list()
	for(var/listing_id in shipyard_ship_listings())
		var/datum/ship_listing/listing = GLOB.ship_listings[listing_id]
		if(listing.available_to(session.affiliation, session.operator_trim))
			visible += listing
	return visible

/// The catalog is static per login: who is logged in decides what is on it.
/obj/machinery/computer/ship_broker/ui_static_data(mob/user)
	var/list/hulls = list()
	if(authenticated)
		for(var/datum/ship_listing/listing as anything in visible_listings())
			var/list/entry = listing.listing_data()
			if(entry)
				hulls += list(entry)
	return list("hulls" = hulls)

/obj/machinery/computer/ship_broker/ui_data(mob/user)
	var/list/data = session.base_ui_data(user)
	var/datum/overmap_faction/faction = get_overmap_faction(session.affiliation)
	data["affiliation"] = faction?.name
	if(!data["authenticated"])
		return data
	data["ledgerBalance"] = session.ledger_balance
	data["garage"] = list(
		"used" = slots?["used"] || 0,
		"total" = slots?["total"] || 0,
	)
	var/obj/effect/landmark/overmap_landing_zone/zone = session.active_zone()
	var/obj/docking_port/mobile/occupant = zone?.get_occupant()
	data["zone"] = list(
		"linked" = !!zone,
		"name" = zone?.zone_name,
		"width" = zone?.zone_width || 0,
		"height" = zone?.zone_height || 0,
		"occupant" = occupant?.name,
	)
	data["statusMessage"] = session.status_message
	return data

/obj/machinery/computer/ship_broker/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/ui_state)
	. = ..()
	if(.)
		return
	var/mob/living/user = usr
	if(session.is_busy())
		return FALSE

	if(session.handle_login_act(action, user))
		if(authenticated)
			refresh_session()
		else
			slots = null
		update_static_data_for_all_viewers()
		return TRUE

	if(!session.has_session(user))
		return FALSE

	switch(action)
		if("refresh")
			refresh_session()
			return TRUE
		if("purchase")
			session.status_message = null
			if(!session.require_pin(user, params["pin"]))
				return TRUE
			purchase(params["id"], params["name"], params["delivery"], !!text2num("[params["insured"]]"), user)
			refresh_session()
			return TRUE

/// Why a hull of this footprint cannot go down on the pad, or null.
/obj/machinery/computer/ship_broker/proc/pad_refusal(datum/hull_profile/profile)
	var/obj/effect/landmark/overmap_landing_zone/zone = session.active_zone()
	if(!zone)
		return "No landing pad is linked. Use a multitool on a landing controller, then on this console."
	if(zone.get_occupant())
		return "[zone.zone_name] is occupied. Clear the pad first."
	if(profile.width > zone.zone_width || profile.height > zone.zone_height)
		return "A [profile.width] x [profile.height] hull does not fit [zone.zone_name] ([zone.zone_width] x [zone.zone_height]). Send it to the garage instead."
	return null

/obj/machinery/computer/ship_broker/proc/purchase(listing_id, ship_name, delivery, insured, mob/user)
	var/datum/ship_listing/listing = shipyard_ship_listing(listing_id)
	var/operation = delivery == SHIP_BROKER_DELIVERY_PAD \
		? "Purchasing [listing?.name || "the vessel"] and setting it down on the pad..." \
		: "Purchasing [listing?.name || "the vessel"] into your garage..."
	if(!session.begin_busy(operation))
		return null
	. = do_purchase(listing_id, ship_name, delivery, insured, user)
	session.end_busy()

/**
 * Sell a hull: charge for it, give it a row and a map, and set it down if asked.
 *
 * Every refusal comes before the charge. A failure between the charge and the
 * row being stored refunds it. A pad delivery that fails after that is not a
 * failed sale: the ship is bought and waiting in the garage, and the message
 * says so.
 */
/obj/machinery/computer/ship_broker/proc/do_purchase(listing_id, ship_name, delivery, insured, mob/user)
	PRIVATE_PROC(TRUE)
	var/operator_uuid = session.operator_uuid
	var/datum/ship_listing/listing = shipyard_ship_listing(listing_id)
	if(!listing || !listing.available_to(session.affiliation, session.operator_trim))
		session.set_status(FALSE, "That hull is not offered to you.")
		return null
	if(!(delivery in list(SHIP_BROKER_DELIVERY_PAD, SHIP_BROKER_DELIVERY_GARAGE)))
		session.set_status(FALSE, "Choose where the hull is delivered.")
		return null
	if(delivery != SHIP_BROKER_DELIVERY_PAD)
		insured = FALSE
	if(!operator_uuid)
		session.set_status(FALSE, "No persistent identity is on record for this operator.")
		return null
	if(!GLOB.ship_registry.is_online())
		session.set_status(FALSE, "The hangar registry is offline. Hulls cannot be registered.")
		return null
	if(!SScharacter_ledger.is_available())
		session.set_status(FALSE, "The ledger is offline. Sales are unavailable.")
		return null
	if(!GLOB.ship_garage_slots.can_add(session.operator_ckey))
		var/list/usage = session.slot_usage()
		session.set_status(FALSE, "Your garage is full ([usage["used"]] / [usage["total"]] slots). Every hull needs a garage slot; clear or decommission a ship at a registrar first.")
		return null
	var/datum/hull_profile/profile = listing.get_profile()
	if(!profile)
		session.set_status(FALSE, "The broker has no plans on file for the [listing.name].")
		return null
	if(delivery == SHIP_BROKER_DELIVERY_PAD)
		var/pad_text = pad_refusal(profile)
		if(pad_text)
			session.set_status(FALSE, pad_text)
			return null
	var/name_text = reject_bad_name(ship_name, allow_numbers = TRUE, max_length = 32, cap_after_symbols = FALSE) || listing.name
	var/price = listing.purchase_price()
	// Insurance is charged by the delivery, after the hull. Checked up front so
	// that a buyer who cannot cover both is refused rather than left with an
	// uninsured sale they did not ask for.
	if(insured)
		var/insurance = shipyard_insurance_fee(listing.get_salvage_estimate())
		if(SScharacter_ledger.get_balance(operator_uuid) < price + insurance)
			session.set_status(FALSE, "Purchase refused: not enough credits in your ledger for the hull and its insurance ([price + insurance] cr).")
			return null

	// One key per sale attempt: a refused or refunded sale must be payable again.
	var/static/sale_serial = 0
	var/charge_key = "ship-purchase-[operator_uuid]-[listing.id]-[shipyard_current_round_id()]-[++sale_serial]"
	var/datum/character_ledger_result/charge = SScharacter_ledger.try_title_purchase(operator_uuid, price, listing.id, charge_key)
	if(!charge.success)
		session.set_status(FALSE, "Purchase refused: [shipyard_ledger_refusal_text(charge)]")
		return null
	var/record_id = listing.register_new_hull(operator_uuid, session.operator_ckey, name_text)
	if(!record_id)
		refund_purchase(operator_uuid, price, charge_key, "Refund: [listing.name] ([name_text]) could not be registered")
		session.set_status(FALSE, "The [listing.name] could not be registered, so the sale was cancelled and your [price] cr refunded.")
		return null
	log_admin("Ship broker: [key_name(user)] bought a [listing.name] named [name_text] as record [record_id] for [price] cr, delivered to [delivery].")

	if(delivery == SHIP_BROKER_DELIVERY_GARAGE)
		session.set_status(TRUE, "[name_text] is registered as #[record_id] and waiting in your garage. Charged [price] cr.")
		playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
		return TRUE

	var/datum/player_ship_record/record = GLOB.ship_registry.get_record(record_id, operator_uuid)
	var/obj/effect/landmark/overmap_landing_zone/zone = session.active_zone()
	var/datum/shipyard_delivery/pad_delivery = shipyard_deliver_record(record, zone, insured, operator_uuid, user, waive_uninsured_fee = TRUE)
	if(!pad_delivery.success)
		session.set_status(FALSE, "[name_text] is bought and registered as #[record_id], but could not be set down: [pad_delivery.message] It is waiting in your garage. Charged [price] cr.")
		return TRUE
	var/total = price + pad_delivery.fee
	session.set_status(TRUE, "[name_text] is landing on [zone.zone_name], [insured ? "insured" : "uninsured"]. Registered as #[record_id]. Charged [total] cr.")
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return pad_delivery.hull

/obj/machinery/computer/ship_broker/proc/refund_purchase(owner_uuid, amount, charge_key, reason)
	var/datum/character_ledger_result/result = SScharacter_ledger.try_credit(owner_uuid, amount, LEDGER_CHANNEL_TITLE_PURCHASE, reason, "[charge_key]-refund")
	log_admin("Ship broker: refund [amount] cr to [owner_uuid] ([charge_key]-refund): [reason]. Result: [result.status].")
	if(!result.success)
		message_admins("Ship broker: a [amount] cr refund to [owner_uuid] for [charge_key] failed ([result.reason]) and needs refunding by hand.")
	return result.success

#undef SHIP_BROKER_DELIVERY_PAD
#undef SHIP_BROKER_DELIVERY_GARAGE
