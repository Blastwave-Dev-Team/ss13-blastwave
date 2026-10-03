// MODULE ID: OVERMAP
// What the vessel broker sells.
//
// One listing per hull on the lot, pointing at the shuttle template it is sold
// as. The footprint, fittings and salvage value are read off the template's
// map, so a listing only states what a map cannot: the sales copy, the price,
// and who may buy it.

/// listing id -> /datum/ship_listing, built on first ask.
GLOBAL_LIST_EMPTY(ship_listings)

/// Every listing, keyed by id.
/proc/shipyard_ship_listings()
	if(!length(GLOB.ship_listings))
		for(var/listing_type in subtypesof(/datum/ship_listing))
			var/datum/ship_listing/listing = new listing_type()
			if(listing.id && ispath(listing.template_type, /datum/map_template/shuttle))
				GLOB.ship_listings[listing.id] = listing
	return GLOB.ship_listings

/proc/shipyard_ship_listing(listing_id)
	return shipyard_ship_listings()["[listing_id]"]

/datum/ship_listing
	/// Stable id, the TGUI contract and the purchase action's argument.
	var/id
	var/name
	var/class_name
	var/manufacturer
	var/description
	var/template_type
	/// What the sales sheet lists as aboard, beyond the counts the map gives.
	var/list/fittings = list()
	/// OVERMAP_AFFILIATION_* ids that may buy this hull.
	var/list/affiliations
	/// ID trim types (and their subtypes) that may buy this hull.
	var/list/trims
	/// Price of the hull itself, before registration. Null prices it off its footprint.
	var/hull_price
	var/datum/map_template/shuttle/template
	/// Salvage value of the hull as delivered, which insurance is priced off.
	var/salvage_estimate

/// Open to everyone when it names no one; otherwise to the named affiliations and employers.
/datum/ship_listing/proc/available_to(affiliation, trim_type)
	if(!length(affiliations) && !length(trims))
		return TRUE
	if(affiliation && (affiliation in affiliations))
		return TRUE
	for(var/allowed_trim in trims)
		if(ispath(trim_type, allowed_trim))
			return TRUE
	return FALSE

/datum/ship_listing/proc/get_template()
	RETURN_TYPE(/datum/map_template/shuttle)
	if(template)
		return template
	var/datum/map_template/shuttle/template_defaults = template_type
	template = SSmapping.shuttle_templates["[initial(template_defaults.port_id)]_[initial(template_defaults.suffix)]"]
	if(!template)
		template = new template_type()
	return template

/datum/ship_listing/proc/map_path()
	var/datum/map_template/shuttle/loaded = get_template()
	return loaded?.mappath

/datum/ship_listing/proc/get_profile()
	return shipyard_hull_profile(map_path())

/datum/ship_listing/proc/get_salvage_estimate()
	if(isnull(salvage_estimate))
		salvage_estimate = shipyard_salvage_estimate(map_path())
	return salvage_estimate

/datum/ship_listing/proc/get_hull_price()
	if(!isnull(hull_price))
		return hull_price
	var/datum/hull_profile/profile = get_profile()
	if(!profile)
		return 0
	return round(2500 + profile.tiles * 45 + profile.engines * 600, 50)

/// The price sheet: hull, registration, and insurance for the first trip to the pad.
/datum/ship_listing/proc/price_data()
	return list(
		"hull" = get_hull_price(),
		"registration" = CONFIG_GET(number/ship_registration_fee),
		"insurance" = shipyard_insurance_fee(get_salvage_estimate()),
	)

/// What buying the hull costs before coverage.
/datum/ship_listing/proc/purchase_price()
	return get_hull_price() + CONFIG_GET(number/ship_registration_fee)

/// The listing as the broker's catalog reads it, or null when its map does not parse.
/datum/ship_listing/proc/listing_data()
	var/datum/hull_profile/profile = get_profile()
	if(!profile)
		return null
	var/list/data = profile.listing_data()
	data["id"] = id
	data["name"] = name
	data["className"] = class_name
	data["manufacturer"] = manufacturer
	data["description"] = description
	data["fittings"] = fittings
	data["price"] = price_data()
	return data

/**
 * Give a new hull of this listing a registry row at revision 1, as if it had
 * just been filed: its map is a copy of the stock map, and it is in the garage.
 *
 * Copied rather than pointed at, so that a later edit to the stock map cannot
 * change a ship somebody already owns. Returns the record id, or null having
 * left nothing behind.
 */
/datum/ship_listing/proc/register_new_hull(owner_uuid, owner_ckey, ship_name, grant_id)
	var/datum/hull_profile/profile = get_profile()
	var/source_path = map_path()
	if(!profile || !source_path || !fexists(source_path))
		return null
	var/record_id = GLOB.ship_registry.insert_record(owner_uuid, owner_ckey, ship_name, grant_id)
	if(!record_id)
		return null
	var/file_path = shipyard_ship_file_path(owner_uuid, record_id, 1)
	if(!fcopy(source_path, file_path))
		GLOB.ship_registry.discard(record_id)
		return null
	var/checksum = rustg_hash_file(RUSTG_HASH_SHA256, file_path)
	if(!GLOB.ship_registry.store_revision(record_id, 1, file_path, checksum, list(), profile.tiles, ship_name, get_salvage_estimate()))
		GLOB.ship_registry.discard(record_id)
		fdel(file_path)
		return null
	return record_id

/datum/ship_listing/nt_personal
	id = "nt_personal"
	name = "NT Personal"
	class_name = "Personal transport"
	manufacturer = "Nanotrasen"
	description = "The shipyard's workhorse. A compact twin-nacelle transport with a forward bridge, a central crew deck and an aft airlock ring. Cheap to run and forgiving to fly."
	template_type = /datum/map_template/shuttle/overmap/frigate/nt_personal
	fittings = list("Helm console", "Nav console", "Crew lockers", "Galley")

/datum/ship_listing/ikea_sma
	id = "ikea_sma"
	name = "Space Ikea Sma"
	class_name = "Flat-pack runabout"
	manufacturer = "Space Ikea"
	description = "Shipped flat, assembled on the pad, and somehow always one bolt short. A single open deck with a three-engine stern and wide observation windows."
	template_type = /datum/map_template/shuttle/overmap/frigate/ikea_sma
	fittings = list("Helm console", "Showroom seating")

/datum/ship_listing/interdyne_cargo
	id = "interdyne_cargo"
	name = "Interdyne Cargo"
	class_name = "Cargo tender"
	manufacturer = "Interdyne Pharmaceutics"
	description = "A short-hop hauler built around one big hold. Two engines, one hatch, and nothing that is not strictly load-bearing."
	template_type = /datum/map_template/shuttle/overmap/frigate/interdyne_cargo
	fittings = list("Helm console", "Cargo racks")
	trims = list(/datum/id_trim/syndicom/nova/interdyne)

/datum/ship_listing/solfed_cutter
	id = "solfed_cutter"
	name = "SolFed Cutter"
	class_name = "Customs cutter"
	manufacturer = "SolFed Navy Yards"
	description = "A customs interceptor with a boarding corridor through its spine."
	template_type = /datum/map_template/shuttle/overmap/frigate/solfed_cutter
	fittings = list("Helm console", "Nav console", "Brig cell", "Wall charger")
	trims = list(/datum/id_trim/solfed, /datum/id_trim/job/solfed_representative)

/datum/ship_listing/solfed_patrol
	id = "solfed_patrol"
	name = "SolFed Patrol"
	class_name = "Patrol frigate"
	manufacturer = "SolFed Navy Yards"
	description = "The cutter's bigger sibling, with a third engine and a forward observation bay."
	template_type = /datum/map_template/shuttle/overmap/frigate/solfed_patrol
	fittings = list("Helm console", "Nav console", "Observation bay")
	trims = list(/datum/id_trim/solfed, /datum/id_trim/job/solfed_representative)

/datum/ship_listing/tarkon_driver
	id = "tarkon_driver"
	name = "Tarkon Driver"
	class_name = "Mining barge"
	manufacturer = "Tarkon Industries"
	description = "A long-haul mining barge with twin side bays and a rear processing deck. The largest hull on the lot."
	template_type = /datum/map_template/shuttle/overmap/frigate/tarkon_driver
	fittings = list("Helm console", "Ore processing", "Mining lockers", "Bunks")
	trims = list(/datum/id_trim/away/tarkon)

/datum/ship_listing/blackmarket_burst
	id = "blackmarket_burst"
	name = "Burst"
	class_name = "Smuggler"
	manufacturer = "Unregistered"
	description = "A four-engine smuggler with a hidden hold and no questions asked."
	template_type = /datum/map_template/shuttle/overmap/frigate/blackmarket_burst
	fittings = list("Helm console", "Hidden hold")
	affiliations = list(OVERMAP_AFFILIATION_DS2)
