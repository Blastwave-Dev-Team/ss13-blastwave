// MODULE ID: OVERMAP
// How many ships a player may keep in the garage.
//
// Slots are one pool per ckey, shared by every character the player has: a
// configured base plus whatever has been awarded on top of it. The registry
// counts what is taken; this counts what is owned and decides what may go in.
//
// Two rules follow from the pool being able to shrink below what it holds (a
// revoked grant, a lowered base):
// - a ship already in the garage can always be taken out, and
// - a ship that is out cannot go back in while the garage is over its limit.

#define PLAYER_SHIP_SLOT_GRANTS_TABLE_NAME "player_ship_slot_grants"

/datum/config_entry/number/ship_garage_base_slots
	default = 3
	integer = TRUE
	min_val = 0

GLOBAL_DATUM_INIT(ship_garage_slots, /datum/ship_garage_slots, new)

/// One award of extra slots.
/datum/ship_slot_grant
	var/id
	var/ckey
	/// SHIP_SLOT_GRANT_DONATOR, _EVENT or _ADMIN.
	var/kind
	/// What the award was for, in the words of whoever gave it.
	var/source = ""
	var/count = 1
	var/granted_by = ""
	var/revoked = FALSE

/datum/ship_garage_slots
	/// When TRUE, grants live in `memory_grants` instead of SQL. Production stays FALSE.
	var/use_memory_store = FALSE
	/// id -> /datum/ship_slot_grant
	var/list/memory_grants = list()
	var/next_memory_id = 1
	/// ckey -> list of /datum/ship_slot_grant. Only this datum writes grants, so
	/// the cache is dropped on every award and is otherwise good for the round.
	var/list/grant_cache = list()

/datum/ship_garage_slots/New()
	. = ..()
#ifdef UNIT_TESTS
	use_memory_store = TRUE
#endif

/datum/ship_garage_slots/proc/is_online()
	return use_memory_store || SSdbcore.Connect()

/// Every active grant a ckey holds.
/datum/ship_garage_slots/proc/list_grants(owner_ckey)
	owner_ckey = ckey(owner_ckey)
	var/list/grants = list()
	if(!owner_ckey || !is_online())
		return grants
	var/list/cached = grant_cache[owner_ckey]
	if(cached)
		return cached.Copy()
	if(use_memory_store)
		for(var/id in memory_grants)
			var/datum/ship_slot_grant/grant = memory_grants[id]
			if(grant.ckey == owner_ckey && !grant.revoked)
				grants += grant
	else
		var/datum/db_query/query = SSdbcore.NewQuery(
			"SELECT id, kind, source, count, granted_by FROM [format_table_name(PLAYER_SHIP_SLOT_GRANTS_TABLE_NAME)] \
			WHERE ckey = :ckey AND revoked = 0 ORDER BY id",
			list("ckey" = owner_ckey),
		)
		if(!query.warn_execute())
			qdel(query)
			return grants
		while(query.NextRow())
			var/datum/ship_slot_grant/grant = new()
			grant.id = text2num("[query.item[1]]")
			grant.ckey = owner_ckey
			grant.kind = query.item[2]
			grant.source = query.item[3] || ""
			grant.count = text2num("[query.item[4]]") || 0
			grant.granted_by = query.item[5] || ""
			grants += grant
		qdel(query)
	grant_cache[owner_ckey] = grants
	return grants.Copy()

/**
 * The slot picture for a ckey, in the shape the consoles send to the UI:
 * `list("base", "grants", "total", "used")`.
 */
/datum/ship_garage_slots/proc/usage(owner_ckey)
	var/base = CONFIG_GET(number/ship_garage_base_slots)
	var/granted = 0
	for(var/datum/ship_slot_grant/grant as anything in list_grants(owner_ckey))
		granted += grant.count
	return list(
		"base" = base,
		"grants" = granted,
		"total" = base + granted,
		"used" = GLOB.ship_registry.count_for_ckey(owner_ckey),
	)

/// Whether a new ship, bought or filed for the first time, fits.
/datum/ship_garage_slots/proc/can_add(owner_ckey)
	var/list/slots = usage(owner_ckey)
	return slots["used"] < slots["total"]

/**
 * Whether a ship that already holds a row may be filed back into it.
 *
 * Its row already counts, so this is not a "one more" check: it only refuses
 * when the garage is over its limit, which is how a player who has more ships
 * than slots is made to let one go.
 */
/datum/ship_garage_slots/proc/can_refile(owner_ckey, datum/player_ship_record/record)
	if(record?.status == SHIP_STATUS_FILED)
		return TRUE
	var/list/slots = usage(owner_ckey)
	return slots["used"] <= slots["total"]

/// Award `count` slots to a ckey. Returns the new grant's id, or null.
/datum/ship_garage_slots/proc/award_slots(owner_ckey, kind, source, count = 1, granted_by)
	owner_ckey = ckey(owner_ckey)
	count = round(text2num("[count]"))
	if(!owner_ckey || count < 1 || !(kind in list(SHIP_SLOT_GRANT_DONATOR, SHIP_SLOT_GRANT_EVENT, SHIP_SLOT_GRANT_ADMIN)) || !is_online())
		return null
	source = copytext(source || "", 1, 128)
	granted_by = ckey(granted_by) || ""
	grant_cache -= owner_ckey
	if(use_memory_store)
		var/datum/ship_slot_grant/grant = new()
		grant.id = next_memory_id++
		grant.ckey = owner_ckey
		grant.kind = kind
		grant.source = source
		grant.count = count
		grant.granted_by = granted_by
		memory_grants["[grant.id]"] = grant
		return grant.id
	var/datum/db_query/query = SSdbcore.NewQuery(
		"INSERT INTO [format_table_name(PLAYER_SHIP_SLOT_GRANTS_TABLE_NAME)] (ckey, kind, source, count, granted_by) \
		VALUES (:ckey, :kind, :source, :count, :granted_by)",
		list(
			"ckey" = owner_ckey,
			"kind" = kind,
			"source" = source,
			"count" = count,
			"granted_by" = granted_by,
		),
	)
	if(!query.warn_execute())
		qdel(query)
		return null
	var/new_id = text2num("[query.last_insert_id]")
	qdel(query)
	return new_id

/// Withdraw a grant. The ships it made room for stay; the garage just goes over its limit.
/datum/ship_garage_slots/proc/revoke_grant(grant_id)
	grant_id = text2num("[grant_id]")
	if(!grant_id || !is_online())
		return FALSE
	grant_cache.Cut()
	if(use_memory_store)
		var/datum/ship_slot_grant/grant = memory_grants["[grant_id]"]
		if(!grant)
			return FALSE
		grant.revoked = TRUE
		return TRUE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"UPDATE [format_table_name(PLAYER_SHIP_SLOT_GRANTS_TABLE_NAME)] SET revoked = 1 WHERE id = :id",
		list("id" = grant_id),
	)
	. = query.warn_execute()
	qdel(query)

/// A grant by id, for labelling the ship it came with.
/datum/ship_garage_slots/proc/get_grant(owner_ckey, grant_id)
	grant_id = text2num("[grant_id]")
	if(!grant_id)
		return null
	for(var/datum/ship_slot_grant/grant as anything in list_grants(owner_ckey))
		if(grant.id == grant_id)
			return grant
	return null

#undef PLAYER_SHIP_SLOT_GRANTS_TABLE_NAME
