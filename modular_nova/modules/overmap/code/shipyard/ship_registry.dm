// MODULE ID: OVERMAP
// The registry half of player-owned persistent ships: who owns what, and which
// file on disk holds it.
//
// Deliberately knows nothing about hulls, turfs or docking ports. Filing writes
// a map and then records it here; retrieval reads a record and then loads that
// map. Keeping the two apart is what lets the load and save paths be tested
// without a database, and lets a registry outage refuse a file rather than
// serialize a ship into a void nothing remembers.

#define PLAYER_SHIPS_TABLE_NAME "player_ships"

/// Column order of the SELECT every lookup here shares.
#define SHIP_RECORD_ID 1
#define SHIP_RECORD_CKEY 2
#define SHIP_RECORD_NAME 3
#define SHIP_RECORD_MAP_PATH 4
#define SHIP_RECORD_TILE_COUNT 5
#define SHIP_RECORD_LOCKBOX 6
#define SHIP_RECORD_CHECKED_OUT 7
#define SHIP_RECORD_RETRIEVED_ROUND 8

/// One row of `player_ships`, as the console and the load path read it.
/datum/player_ship_record
	var/id
	var/owner_ckey
	var/ship_name = "Unnamed vessel"
	var/map_path
	var/tile_count = 0
	/// Lockbox manifest, in the shape `/datum/ship_teardown` writes it.
	var/list/stored_contents = list()
	/// Whether this hull is live in the world rather than sitting in its file.
	var/checked_out = FALSE
	/// The round that took it out, which is what makes `checked_out` recoverable.
	var/retrieved_round_id

/// Whether the record can be handed to a retrieval at all. A hull checked out
/// by a round that has since ended is not lost: nothing can still be holding it,
/// so it reverts to whatever state it was last filed in.
/datum/player_ship_record/proc/is_retrievable()
	if(!map_path)
		return FALSE
	return !checked_out || "[retrieved_round_id]" != "[GLOB.round_id]"

/// Human-readable state for the console list.
/datum/player_ship_record/proc/status_label()
	if(!map_path)
		return "incomplete"
	return is_retrievable() ? "filed" : "in service"

/**
 * Whether the registry is reachable.
 *
 * Every proc below guards on this, so a server running without SQL simply has no
 * persistent ships rather than a shipyard that half works.
 */
/proc/shipyard_registry_online()
	return SSdbcore.Connect()

/// The shared projection, so every read builds a record the same way.
#define SHIP_RECORD_COLUMNS "id, ckey, ship_name, map_path, tile_count, lockbox, checked_out, retrieved_round_id"

/// Build a record from the row the cursor is sitting on.
/proc/shipyard_record_from_row(datum/db_query/query)
	var/datum/player_ship_record/record = new()
	record.id = text2num("[query.item[SHIP_RECORD_ID]]")
	record.owner_ckey = query.item[SHIP_RECORD_CKEY]
	record.ship_name = query.item[SHIP_RECORD_NAME]
	record.map_path = query.item[SHIP_RECORD_MAP_PATH]
	record.tile_count = text2num("[query.item[SHIP_RECORD_TILE_COUNT]]") || 0
	record.checked_out = !!text2num("[query.item[SHIP_RECORD_CHECKED_OUT]]")
	record.retrieved_round_id = query.item[SHIP_RECORD_RETRIEVED_ROUND]
	var/lockbox_json = query.item[SHIP_RECORD_LOCKBOX]
	if(lockbox_json)
		var/list/decoded = json_decode(lockbox_json)
		if(islist(decoded))
			record.stored_contents = decoded
	return record

/// Every ship a ckey owns, newest first.
/proc/shipyard_registry_list(owner_ckey)
	var/list/records = list()
	owner_ckey = ckey(owner_ckey)
	if(!owner_ckey || !shipyard_registry_online())
		return records
	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT [SHIP_RECORD_COLUMNS] FROM [format_table_name(PLAYER_SHIPS_TABLE_NAME)] \
		WHERE ckey = :ckey AND deleted = 0 ORDER BY id DESC",
		list("ckey" = owner_ckey),
	)
	if(!query.warn_execute())
		qdel(query)
		return records
	while(query.NextRow())
		records += shipyard_record_from_row(query)
	qdel(query)
	return records

/// One record by id, or null. Owner is checked here so a spoofed console action
/// cannot reach a ship the logged-in operator does not own.
/proc/shipyard_registry_get(record_id, owner_ckey)
	record_id = text2num("[record_id]")
	owner_ckey = ckey(owner_ckey)
	if(!record_id || !owner_ckey || !shipyard_registry_online())
		return null
	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT [SHIP_RECORD_COLUMNS] FROM [format_table_name(PLAYER_SHIPS_TABLE_NAME)] \
		WHERE id = :id AND ckey = :ckey AND deleted = 0",
		list("id" = record_id, "ckey" = owner_ckey),
	)
	if(!query.warn_execute())
		qdel(query)
		return null
	var/datum/player_ship_record/record
	if(query.NextRow())
		record = shipyard_record_from_row(query)
	qdel(query)
	return record

/**
 * Claim a row for a hull about to be written out, and return its id.
 *
 * The row comes first because the file path is derived from the id, so there is
 * a moment where a record exists with no map behind it. `map_path` is empty
 * until the write lands, which is what `status_label()` reads as incomplete and
 * what stops a retrieval trying to load a file that was never written.
 */
/proc/shipyard_registry_insert(owner_ckey, ship_name, tile_count = 0)
	owner_ckey = ckey(owner_ckey)
	if(!owner_ckey || !shipyard_registry_online())
		return null
	var/datum/db_query/query = SSdbcore.NewQuery(
		"INSERT INTO [format_table_name(PLAYER_SHIPS_TABLE_NAME)] (ckey, ship_name, tile_count, filed_round_id) \
		VALUES (:ckey, :ship_name, :tile_count, :round_id)",
		list(
			"ckey" = owner_ckey,
			"ship_name" = copytext(ship_name || "Unnamed vessel", 1, 64),
			"tile_count" = tile_count,
			"round_id" = GLOB.round_id,
		),
	)
	if(!query.warn_execute())
		qdel(query)
		return null
	var/new_id = text2num("[query.last_insert_id]")
	qdel(query)
	return new_id

/// Record where a filed hull ended up, and put it back on the shelf.
/proc/shipyard_registry_store(record_id, map_path, list/stored_contents, tile_count = 0, ship_name)
	record_id = text2num("[record_id]")
	if(!record_id || !shipyard_registry_online())
		return FALSE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"UPDATE [format_table_name(PLAYER_SHIPS_TABLE_NAME)] SET map_path = :map_path, lockbox = :lockbox, \
		tile_count = :tile_count, ship_name = :ship_name, checked_out = 0, filed_round_id = :round_id WHERE id = :id",
		list(
			"id" = record_id,
			"map_path" = map_path || "",
			"lockbox" = json_encode(stored_contents || list()),
			"tile_count" = tile_count,
			"ship_name" = copytext(ship_name || "Unnamed vessel", 1, 64),
			"round_id" = GLOB.round_id,
		),
	)
	. = query.warn_execute()
	qdel(query)

/**
 * Mark a hull as live in the world.
 *
 * Called only once a retrieval has produced a registered port, so a refused or
 * failed load leaves the row filed and the file untouched, and the player can
 * simply try again.
 */
/proc/shipyard_registry_checkout(record_id)
	record_id = text2num("[record_id]")
	if(!record_id || !shipyard_registry_online())
		return FALSE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"UPDATE [format_table_name(PLAYER_SHIPS_TABLE_NAME)] SET checked_out = 1, retrieved_round_id = :round_id WHERE id = :id",
		list("id" = record_id, "round_id" = GLOB.round_id),
	)
	. = query.warn_execute()
	qdel(query)

/// Retire a row whose hull never made it to disk.
/proc/shipyard_registry_discard(record_id)
	record_id = text2num("[record_id]")
	if(!record_id || !shipyard_registry_online())
		return FALSE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"UPDATE [format_table_name(PLAYER_SHIPS_TABLE_NAME)] SET deleted = 1 WHERE id = :id",
		list("id" = record_id),
	)
	. = query.warn_execute()
	qdel(query)

#undef SHIP_RECORD_COLUMNS

#undef SHIP_RECORD_ID
#undef SHIP_RECORD_CKEY
#undef SHIP_RECORD_NAME
#undef SHIP_RECORD_MAP_PATH
#undef SHIP_RECORD_TILE_COUNT
#undef SHIP_RECORD_LOCKBOX
#undef SHIP_RECORD_CHECKED_OUT
#undef SHIP_RECORD_RETRIEVED_ROUND

#undef PLAYER_SHIPS_TABLE_NAME
