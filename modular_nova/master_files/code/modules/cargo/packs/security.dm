/datum/supply_pack/security/ammo
	express_lock = TRUE

/datum/supply_pack/security/armor
	express_lock = TRUE

/datum/supply_pack/security/disabler
	cost = CARGO_CRATE_VALUE * 5

/datum/supply_pack/security/helmets
	express_lock = TRUE

/datum/supply_pack/security/securityclothes
	express_lock = TRUE

/datum/supply_pack/security/armory/ballistic
	desc = "For when the enemy absolutely needs to be replaced with lead. \
		Contains three Nanotrasen Peacekeeper combat shotguns, and three bandoliers."
	cost = CARGO_CRATE_VALUE * 12.5 // 2500cr at time of writing
	crate_name = "combat shotguns crate"

/datum/supply_pack/security/armory/thermal
	express_lock = TRUE

/datum/supply_pack/security/armory/voskhod
	name = "Voskhod MODsuit Kit Crate"
	desc = "A bottom-of-the-line Voskhod-pattern MODsuit. Some assembly required, autodoc refills and miscellaneous parts not included!"
	cost = CARGO_CRATE_VALUE * 20
	contains = list(/obj/item/clothing/suit/space/voskhod, /obj/item/clothing/head/helmet/space/voskhod, /obj/item/crafting_conversion_kit/voskhod_refit)
	crate_name = "Voskhod MOD crate"
	console_flag = CARGO_CONSOLE_NT | CARGO_CONSOLE_PDA

/datum/supply_pack/security/armory/voskhod_autodoc_refill
	name = "Voskhod Autodoc Refill"
	desc = "Sweet, sweet autodoc juice. \
		Contains a single 100u bottle of Protozine."
	cost = CARGO_CRATE_VALUE
	contains = list(/obj/item/reagent_containers/cup/glass/waterbottle/large/protozine)
	crate_name = "MOD autodoc refill crate"
	console_flag = CARGO_CONSOLE_NT | CARGO_CONSOLE_PDA

/datum/supply_pack/security/armory/katyusha
	name = "Katyusha Shotgun Crate"
	desc = "Nanotrasen Armories 10-round drum-mag shotgun. If you need to throw a LOT of lead downrange, not much else compares.\
		Contains one loaded Katyusha drum-fed shotgun, plus buckshot drum mags."
	cost = CARGO_CRATE_VALUE * 13
	contains = list(/obj/item/storage/toolbox/guncase/nova/katyusha)
	crate_name = "Katyusha shotgun crate"
	console_flag = CARGO_CONSOLE_NT | CARGO_CONSOLE_PDA
