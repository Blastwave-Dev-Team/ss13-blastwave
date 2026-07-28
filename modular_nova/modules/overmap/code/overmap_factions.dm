// MODULE ID: OVERMAP
// Data-driven overmap factions and ID-match rules. Wire format remains the
// OVERMAP_AFFILIATION_* string ids (and null for open docking).

/datum/overmap_faction
	/// Stable id matching OVERMAP_AFFILIATION_* (or custom future ids).
	var/id
	/// Human-readable name for UI / examine.
	var/name
	/// Ship home_level_id when this affiliation is applied. Null for neutral.
	var/home_level_id
	/// Landing controller monitor overlay when pad is locked to this faction.
	var/console_icon_screen
	/// Stealth installation level id this faction always sees as home.
	var/stealth_level_id

/datum/overmap_faction/nt
	id = OVERMAP_AFFILIATION_NT
	name = "Nanotrasen"
	home_level_id = MAIN_OVERMAP_OBJECT_ID
	stealth_level_id = MAIN_OVERMAP_OBJECT_ID

/datum/overmap_faction/ds2
	id = OVERMAP_AFFILIATION_DS2
	name = "Syndicate"
	home_level_id = DES_TWO_OVERMAP_OBJECT_ID
	console_icon_screen = "syndie"
	stealth_level_id = DES_TWO_OVERMAP_OBJECT_ID

/datum/overmap_faction/neutral
	id = OVERMAP_AFFILIATION_NEUTRAL
	name = "Neutral"

/// Ordered ID → faction (or open) rules. First match wins.
/datum/overmap_faction_id_rule
	var/priority = 100
	/// Faction id to assign on match. Null means force open (no faction).
	var/result_faction_id

/datum/overmap_faction_id_rule/proc/matches(obj/item/card/id/card)
	return FALSE

/datum/overmap_faction_id_rule/tarkon_open
	priority = 10
	result_faction_id = null

/datum/overmap_faction_id_rule/tarkon_open/matches(obj/item/card/id/card)
	return istype(card?.trim, /datum/id_trim/away/tarkon)

/datum/overmap_faction_id_rule/interdyne_open
	priority = 20
	result_faction_id = null

/datum/overmap_faction_id_rule/interdyne_open/matches(obj/item/card/id/card)
	return istype(card?.trim, /datum/id_trim/syndicom/nova/interdyne)

/datum/overmap_faction_id_rule/syndicate_access
	priority = 30
	result_faction_id = OVERMAP_AFFILIATION_DS2

/datum/overmap_faction_id_rule/syndicate_access/matches(obj/item/card/id/card)
	if(isnull(card))
		return FALSE
	var/list/access = card.GetAccess()
	return (ACCESS_SYNDICATE in access) || (ACCESS_SYNDICATE_LEADER in access)

/datum/overmap_faction_id_rule/station_job_trim
	priority = 40
	result_faction_id = OVERMAP_AFFILIATION_NT

/datum/overmap_faction_id_rule/station_job_trim/matches(obj/item/card/id/card)
	return istype(card?.trim, /datum/id_trim/job)

/datum/overmap_faction_id_rule/station_account_job
	priority = 50
	result_faction_id = OVERMAP_AFFILIATION_NT

/datum/overmap_faction_id_rule/station_account_job/matches(obj/item/card/id/card)
	return card?.registered_account?.account_job?.faction == FACTION_STATION

/datum/overmap_faction_id_rule/default_open
	priority = 1000
	result_faction_id = null

/datum/overmap_faction_id_rule/default_open/matches(obj/item/card/id/card)
	return TRUE

GLOBAL_LIST_INIT(overmap_factions, list(
	new /datum/overmap_faction/nt,
	new /datum/overmap_faction/ds2,
	new /datum/overmap_faction/neutral,
))

GLOBAL_LIST_EMPTY(overmap_factions_by_id)
GLOBAL_LIST_EMPTY(overmap_factions_by_home_level)
GLOBAL_LIST_EMPTY(overmap_faction_id_rules)

/proc/init_overmap_faction_globals()
	GLOB.overmap_factions_by_id = list()
	GLOB.overmap_factions_by_home_level = list()
	for(var/datum/overmap_faction/faction as anything in GLOB.overmap_factions)
		GLOB.overmap_factions_by_id[faction.id] = faction
		if(!isnull(faction.home_level_id))
			GLOB.overmap_factions_by_home_level[faction.home_level_id] = faction

	var/list/rules = list(
		new /datum/overmap_faction_id_rule/tarkon_open,
		new /datum/overmap_faction_id_rule/interdyne_open,
		new /datum/overmap_faction_id_rule/syndicate_access,
		new /datum/overmap_faction_id_rule/station_job_trim,
		new /datum/overmap_faction_id_rule/station_account_job,
		new /datum/overmap_faction_id_rule/default_open,
	)
	sortTim(rules, GLOBAL_PROC_REF(cmp_overmap_faction_id_rule_priority))
	GLOB.overmap_faction_id_rules = rules

/proc/cmp_overmap_faction_id_rule_priority(datum/overmap_faction_id_rule/a, datum/overmap_faction_id_rule/b)
	return a.priority - b.priority

/// Lookup helper; null id returns null.
/proc/get_overmap_faction(faction_id)
	if(isnull(faction_id))
		return null
	if(!length(GLOB.overmap_factions_by_id))
		init_overmap_faction_globals()
	return GLOB.overmap_factions_by_id[faction_id]

/// Infer overmap affiliation id from an ID card via ordered rules. Null = open.
/proc/get_id_overmap_faction(obj/item/card/id/card)
	if(isnull(card))
		return null
	if(!length(GLOB.overmap_faction_id_rules))
		init_overmap_faction_globals()
	for(var/datum/overmap_faction_id_rule/rule as anything in GLOB.overmap_faction_id_rules)
		if(!rule.matches(card))
			continue
		return rule.result_faction_id
	return null

/// UI helper: list of {id, name} for every registered overmap faction.
/proc/get_overmap_faction_ui_options()
	if(!length(GLOB.overmap_factions_by_id))
		init_overmap_faction_globals()
	var/list/options = list()
	for(var/datum/overmap_faction/faction as anything in GLOB.overmap_factions)
		options += list(list(
			"id" = faction.id,
			"name" = faction.name,
		))
	return options
