// MODULE ID: OVERMAP
// The registry half of player-owned persistent ships: who owns what, and which
// file on disk holds it.
//
// Deliberately knows nothing about hulls, turfs or docking ports. Filing writes
// a map and then records it here; retrieval reads a record and then loads that
// map. Keeping the two apart is what lets the load and save paths be tested
// without a database, and lets a registry outage refuse a file rather than
// serialize a ship into a void nothing remembers.
//
// Like the character ledger, the registry keeps an in-memory store for unit
// tests, since CI has no MariaDB. Production never sets it.

#define PLAYER_SHIPS_TABLE_NAME "player_ships"

/// The shared projection, so every read builds a record the same way.
// MariaDB stores JSON as utf8mb4_bin LONGTEXT, which the driver hands back as bytes rather than text.
#define SHIP_RECORD_COLUMNS "id, owner_uuid, ckey, ship_name, revision, map_path, map_checksum, tile_count, salvage_estimate, CAST(lockbox AS CHAR) AS lockbox, status, insured, insurance_fee_paid, filed_round_id, retrieved_round_id, grant_id"

GLOBAL_DATUM_INIT(ship_registry, /datum/ship_registry, new)

/// One row of `player_ships`, as the console and the load path read it.
/datum/player_ship_record
	var/id
	var/owner_uuid
	var/ckey
	var/ship_name = "Unnamed vessel"
	/// Bumped on every filing. The file for each revision stays on disk.
	var/revision = 0
	/// The last revision that was written successfully. Empty until the first
	/// filing lands, which is what keeps a half-made row out of the garage.
	var/map_path = ""
	var/map_checksum
	var/tile_count = 0
	/// Material value of the hull at its last filing, which insurance prices off.
	var/salvage_estimate = 0
	/// Lockbox roster, in the shape `/datum/ship_teardown` writes it.
	var/list/stored_contents = list()
	var/status = SHIP_STATUS_FILED
	/// Whether the current checkout is insured.
	var/insured = FALSE
	/// What the current checkout paid for its insurance, refundable on refiling.
	var/insurance_fee_paid = 0
	var/filed_round_id
	var/retrieved_round_id
	var/deleted = FALSE
	/// The slot grant an awarded ship arrived with, or null for a bought or built one.
	var/grant_id

/datum/player_ship_record/proc/copy()
	var/datum/player_ship_record/duplicate = new()
	for(var/var_name in list("id", "owner_uuid", "ckey", "ship_name", "revision", "map_path", "map_checksum", "tile_count", "salvage_estimate", "status", "insured", "insurance_fee_paid", "filed_round_id", "retrieved_round_id", "deleted", "grant_id"))
		duplicate.vars[var_name] = vars[var_name]
	duplicate.stored_contents = deep_copy_list(stored_contents)
	return duplicate

/// Whether this record can be handed to a retrieval right now.
/datum/player_ship_record/proc/is_retrievable()
	return status == SHIP_STATUS_FILED && length(map_path)

/// Whether the hull is out in the world this round, as opposed to a previous one.
/datum/player_ship_record/proc/retrieved_this_round()
	return status == SHIP_STATUS_CHECKED_OUT && retrieved_round_id == shipyard_current_round_id()

/**
 * Whether this record came back from an insured loss rather than a filing.
 *
 * Derived rather than stored: a revert leaves the row filed without refiling
 * it, so its last filing is older than its last checkout. A normal filing
 * after a checkout always happens in the same round or later.
 */
/datum/player_ship_record/proc/reverted_from_loss()
	return status == SHIP_STATUS_FILED && retrieved_round_id && filed_round_id < retrieved_round_id

/// The round id as a number, or 0 on a server that has none (unit tests).
/proc/shipyard_current_round_id()
	return text2num("[GLOB.round_id]") || 0

/// Owner, storage and lookup for persistent player ships.
/datum/ship_registry
	/// When TRUE, rows live in `memory_rows` instead of SQL. Production stays FALSE.
	var/use_memory_store = FALSE
	/// id -> /datum/player_ship_record
	var/list/memory_rows = list()
	var/next_memory_id = 1
	/// Record ids whose rebuild blueprint has been printed this shift. Round-local
	/// on purpose: the limit is one print per shift, not one ever.
	var/list/blueprints_printed = list()

/datum/ship_registry/New()
	. = ..()
#ifdef UNIT_TESTS
	use_memory_store = TRUE
#endif

/**
 * Whether the registry is reachable.
 *
 * Every proc below guards on this, so a server running without SQL simply has no
 * persistent ships rather than a shipyard that half works.
 */
/datum/ship_registry/proc/is_online()
	return use_memory_store || SSdbcore.Connect()

/// Every ship a character owns, newest first, with stale checkouts resolved.
/datum/ship_registry/proc/list_for_owner(owner_uuid)
	var/list/records = list()
	if(!owner_uuid || !is_online())
		return records
	if(use_memory_store)
		for(var/id in memory_rows)
			var/datum/player_ship_record/row = memory_rows[id]
			if(row.owner_uuid == owner_uuid && !row.deleted && length(row.map_path))
				records.Insert(1, row.copy())
	else
		var/datum/db_query/query = SSdbcore.NewQuery(
			"SELECT [SHIP_RECORD_COLUMNS] FROM [format_table_name(PLAYER_SHIPS_TABLE_NAME)] \
			WHERE owner_uuid = :owner AND deleted = 0 AND map_path <> '' ORDER BY id DESC",
			list("owner" = owner_uuid),
		)
		if(!query.warn_execute())
			qdel(query)
			return records
		while(query.NextRow())
			records += record_from_row(query)
		qdel(query)
	for(var/datum/player_ship_record/record as anything in records)
		resolve_stale_checkout(record)
	return records

/**
 * How many garage slots a player's ships take up, across every character.
 *
 * Slots are a ckey pool, so this counts every row the player holds rather than
 * one character's. Lost rows count: a lost ship keeps its slot until the owner
 * clears it. A row whose first filing never landed has no hull and does not.
 */
/datum/ship_registry/proc/count_for_ckey(owner_ckey)
	owner_ckey = ckey(owner_ckey)
	if(!owner_ckey || !is_online())
		return 0
	if(use_memory_store)
		var/count = 0
		for(var/id in memory_rows)
			var/datum/player_ship_record/row = memory_rows[id]
			if(row.ckey == owner_ckey && !row.deleted && length(row.map_path))
				count++
		return count
	var/datum/db_query/query = SSdbcore.NewQuery(
		"SELECT COUNT(*) FROM [format_table_name(PLAYER_SHIPS_TABLE_NAME)] \
		WHERE ckey = :ckey AND deleted = 0 AND map_path <> ''",
		list("ckey" = owner_ckey),
	)
	var/count = 0
	if(query.warn_execute() && query.NextRow())
		count = text2num("[query.item[1]]") || 0
	qdel(query)
	return count

/// Mark a record's rebuild blueprint as printed for this shift.
/datum/ship_registry/proc/note_blueprint_printed(record_id)
	blueprints_printed["[record_id]"] = TRUE

/datum/ship_registry/proc/blueprint_printed(record_id)
	return !!blueprints_printed["[record_id]"]

/// One record by id, or null. Owner is checked here so a spoofed console action
/// cannot reach a ship the logged-in operator does not own.
/datum/ship_registry/proc/get_record(record_id, owner_uuid)
	record_id = text2num("[record_id]")
	if(!record_id || !owner_uuid || !is_online())
		return null
	var/datum/player_ship_record/record
	if(use_memory_store)
		var/datum/player_ship_record/row = memory_rows["[record_id]"]
		if(row && row.owner_uuid == owner_uuid && !row.deleted)
			record = row.copy()
	else
		var/datum/db_query/query = SSdbcore.NewQuery(
			"SELECT [SHIP_RECORD_COLUMNS] FROM [format_table_name(PLAYER_SHIPS_TABLE_NAME)] \
			WHERE id = :id AND owner_uuid = :owner AND deleted = 0",
			list("id" = record_id, "owner" = owner_uuid),
		)
		if(!query.warn_execute())
			qdel(query)
			return null
		if(query.NextRow())
			record = record_from_row(query)
		qdel(query)
	if(record)
		resolve_stale_checkout(record)
	return record

/**
 * Settle a checkout that an earlier round never filed back.
 *
 * Nothing can still be holding a hull a finished round took out, so its fate is
 * decided on the next read rather than by a round-end hook that a crash would
 * skip. Insurance pays for the last filed snapshot to come back, and is spent
 * doing so; an uninsured hull is simply gone.
 */
/datum/ship_registry/proc/resolve_stale_checkout(datum/player_ship_record/record)
	if(record.status != SHIP_STATUS_CHECKED_OUT)
		return
	if(record.retrieved_round_id == shipyard_current_round_id())
		return
	if(record.insured)
		revert_to_snapshot(record.id)
		log_admin("Ship registry: insured checkout of [record.ship_name] (record [record.id], owner [record.owner_uuid]) was not refiled; reverted to revision [record.revision].")
		record.status = SHIP_STATUS_FILED
		record.insured = FALSE
		record.insurance_fee_paid = 0
		return
	mark_lost(record.id)
	log_admin("Ship registry: uninsured checkout of [record.ship_name] (record [record.id], owner [record.owner_uuid]) was not refiled; marked lost.")
	record.status = SHIP_STATUS_LOST

/**
 * Claim a row for a hull about to be written out for the first time, and
 * return its id.
 *
 * The row comes first because the file path is derived from the id, so there is
 * a moment where a record exists with no map behind it. `map_path` stays empty
 * until the write lands, which is what keeps the row out of every listing.
 */
/datum/ship_registry/proc/insert_record(owner_uuid, owner_ckey, ship_name, grant_id = null)
	if(!owner_uuid || !is_online())
		return null
	ship_name = copytext(ship_name || "Unnamed vessel", 1, 64)
	grant_id = text2num("[grant_id]")
	if(use_memory_store)
		var/datum/player_ship_record/row = new()
		row.id = next_memory_id++
		row.owner_uuid = owner_uuid
		row.ckey = ckey(owner_ckey)
		row.ship_name = ship_name
		row.filed_round_id = shipyard_current_round_id()
		row.grant_id = grant_id
		memory_rows["[row.id]"] = row
		return row.id
	var/datum/db_query/query = SSdbcore.NewQuery(
		"INSERT INTO [format_table_name(PLAYER_SHIPS_TABLE_NAME)] (owner_uuid, ckey, ship_name, filed_round_id, grant_id) \
		VALUES (:owner, :ckey, :ship_name, :round_id, :grant_id)",
		list(
			"owner" = owner_uuid,
			"ckey" = ckey(owner_ckey) || "",
			"ship_name" = ship_name,
			"round_id" = shipyard_current_round_id(),
			"grant_id" = grant_id,
		),
	)
	if(!query.warn_execute())
		qdel(query)
		return null
	var/new_id = text2num("[query.last_insert_id]")
	qdel(query)
	return new_id

/**
 * Point a row at a revision that has just been written, and put it back on the
 * shelf. Only called after the file is safely on disk, which is what keeps the
 * previous revision available to an insured loss until this one exists.
 */
/datum/ship_registry/proc/store_revision(record_id, revision, map_path, map_checksum, list/stored_contents, tile_count, ship_name, salvage_estimate)
	record_id = text2num("[record_id]")
	if(!record_id || !map_path || !is_online())
		return FALSE
	ship_name = copytext(ship_name || "Unnamed vessel", 1, 64)
	if(use_memory_store)
		var/datum/player_ship_record/row = memory_rows["[record_id]"]
		if(!row)
			return FALSE
		row.revision = revision
		row.map_path = map_path
		row.map_checksum = map_checksum
		row.stored_contents = deep_copy_list(stored_contents || list())
		row.tile_count = tile_count
		row.ship_name = ship_name
		row.salvage_estimate = salvage_estimate
		row.status = SHIP_STATUS_FILED
		row.insured = FALSE
		row.insurance_fee_paid = 0
		row.filed_round_id = shipyard_current_round_id()
		return TRUE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"UPDATE [format_table_name(PLAYER_SHIPS_TABLE_NAME)] SET revision = :revision, map_path = :map_path, \
		map_checksum = :checksum, lockbox = :lockbox, tile_count = :tile_count, ship_name = :ship_name, \
		salvage_estimate = :salvage, status = 'FILED', insured = 0, insurance_fee_paid = 0, \
		filed_round_id = :round_id WHERE id = :id",
		list(
			"id" = record_id,
			"revision" = revision,
			"map_path" = map_path,
			"checksum" = map_checksum,
			"lockbox" = json_encode(stored_contents || list()),
			"tile_count" = tile_count,
			"ship_name" = ship_name,
			"salvage" = max(0, round(salvage_estimate)),
			"round_id" = shipyard_current_round_id(),
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
/datum/ship_registry/proc/checkout(record_id, insured, insurance_fee_paid)
	record_id = text2num("[record_id]")
	if(!record_id || !is_online())
		return FALSE
	if(use_memory_store)
		var/datum/player_ship_record/row = memory_rows["[record_id]"]
		if(!row)
			return FALSE
		row.status = SHIP_STATUS_CHECKED_OUT
		row.insured = !!insured
		row.insurance_fee_paid = insurance_fee_paid || 0
		row.retrieved_round_id = shipyard_current_round_id()
		return TRUE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"UPDATE [format_table_name(PLAYER_SHIPS_TABLE_NAME)] SET status = 'CHECKED_OUT', insured = :insured, \
		insurance_fee_paid = :fee, retrieved_round_id = :round_id WHERE id = :id",
		list(
			"id" = record_id,
			"insured" = insured ? 1 : 0,
			"fee" = max(0, round(insurance_fee_paid || 0)),
			"round_id" = shipyard_current_round_id(),
		),
	)
	. = query.warn_execute()
	qdel(query)

/// An uninsured hull that never came back. The row stays for the owner to see.
/datum/ship_registry/proc/mark_lost(record_id)
	return set_status(record_id, SHIP_STATUS_LOST)

/// An insured hull that never came back returns to its last filed snapshot.
/datum/ship_registry/proc/revert_to_snapshot(record_id)
	return set_status(record_id, SHIP_STATUS_FILED)

/datum/ship_registry/proc/set_status(record_id, new_status)
	record_id = text2num("[record_id]")
	if(!record_id || !is_online())
		return FALSE
	if(use_memory_store)
		var/datum/player_ship_record/row = memory_rows["[record_id]"]
		if(!row)
			return FALSE
		row.status = new_status
		row.insured = FALSE
		row.insurance_fee_paid = 0
		return TRUE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"UPDATE [format_table_name(PLAYER_SHIPS_TABLE_NAME)] SET status = :status, insured = 0, \
		insurance_fee_paid = 0 WHERE id = :id",
		list("id" = record_id, "status" = new_status),
	)
	. = query.warn_execute()
	qdel(query)

/// Retire a row whose hull never made it to disk.
/datum/ship_registry/proc/discard(record_id)
	record_id = text2num("[record_id]")
	if(!record_id || !is_online())
		return FALSE
	if(use_memory_store)
		var/datum/player_ship_record/row = memory_rows["[record_id]"]
		if(!row)
			return FALSE
		row.deleted = TRUE
		return TRUE
	var/datum/db_query/query = SSdbcore.NewQuery(
		"UPDATE [format_table_name(PLAYER_SHIPS_TABLE_NAME)] SET deleted = 1 WHERE id = :id",
		list("id" = record_id),
	)
	. = query.warn_execute()
	qdel(query)

/// Build a record from the row the cursor is sitting on, in SHIP_RECORD_COLUMNS order.
/datum/ship_registry/proc/record_from_row(datum/db_query/query)
	var/datum/player_ship_record/record = new()
	record.id = text2num("[query.item[1]]")
	record.owner_uuid = query.item[2]
	record.ckey = query.item[3]
	record.ship_name = query.item[4]
	record.revision = text2num("[query.item[5]]") || 0
	record.map_path = query.item[6] || ""
	record.map_checksum = query.item[7]
	record.tile_count = text2num("[query.item[8]]") || 0
	record.salvage_estimate = text2num("[query.item[9]]") || 0
	var/lockbox_json = query.item[10]
	if(istext(lockbox_json) && rustg_json_is_valid(lockbox_json))
		var/list/decoded = json_decode(lockbox_json)
		if(islist(decoded))
			record.stored_contents = shipyard_decode_roster(decoded)
	else if(!isnull(lockbox_json))
		log_runtime("Ship registry: record [record.id] has an unreadable lockbox ([lockbox_json]); reading it as empty.")
	record.status = query.item[11]
	record.insured = !!text2num("[query.item[12]]")
	record.insurance_fee_paid = text2num("[query.item[13]]") || 0
	record.filed_round_id = text2num("[query.item[14]]")
	record.retrieved_round_id = text2num("[query.item[15]]")
	record.grant_id = text2num("[query.item[16]]")
	return record

/// JSON carries type paths as text; hand them back as paths.
/proc/shipyard_decode_roster(list/decoded)
	var/list/roster = list()
	for(var/list/entry in decoded)
		var/path = text2path("[entry["path"]]")
		if(!ispath(path, /obj/item))
			continue
		var/list/decoded_entry = list("path" = path, "name" = entry["name"])
		if(isnum(entry["amount"]))
			decoded_entry["amount"] = entry["amount"]
		if(islist(entry["contents"]))
			decoded_entry["contents"] = shipyard_decode_roster(entry["contents"])
		roster += list(decoded_entry)
	return roster

#undef PLAYER_SHIPS_TABLE_NAME
#undef SHIP_RECORD_COLUMNS
