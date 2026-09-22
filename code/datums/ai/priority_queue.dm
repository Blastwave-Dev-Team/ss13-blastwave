/**
 * Identity-keyed priority queue for AI targeting.
 *
 * `/datum/heap` is a cmp-sorted pop pile. This is add/remove by the thing itself, then peek the
 * highest rank that still exists. Encounters and other world-side owners hold one of these and
 * hand the datum to a pawn via [BB_PRIORITY_TARGET_QUEUE]; the pawn does not own the entries.
 *
 * Same target enqueued again updates its rank instead of duplicating.
 */
/datum/priority_queue_entry
	var/datum/weakref/item_ref
	var/rank = 0

/datum/priority_queue_entry/New(datum/item, entry_rank)
	item_ref = WEAKREF(item)
	rank = entry_rank

/datum/priority_queue_entry/proc/resolve()
	return item_ref?.resolve()

/datum/priority_queue
	var/list/datum/priority_queue_entry/entries = list()

/datum/priority_queue/Destroy(force)
	QDEL_LIST(entries)
	return ..()

/datum/priority_queue/proc/enqueue(datum/item, rank)
	if(QDELETED(item))
		return
	var/datum/priority_queue_entry/existing = entry_for(item)
	if(isnull(existing))
		entries += new /datum/priority_queue_entry(item, rank)
		return
	existing.rank = rank

/datum/priority_queue/proc/dequeue(datum/item)
	var/datum/priority_queue_entry/existing = entry_for(item)
	if(isnull(existing))
		return FALSE
	entries -= existing
	qdel(existing)
	return TRUE

/// Drops the entry for `item_ref` even when that weakref no longer resolves.
/datum/priority_queue/proc/dequeue_ref(datum/weakref/item_ref)
	if(isnull(item_ref))
		return FALSE
	for(var/datum/priority_queue_entry/entry as anything in entries)
		if(entry.item_ref != item_ref && entry.item_ref?.reference != item_ref.reference)
			continue
		entries -= entry
		qdel(entry)
		return TRUE
	return FALSE

/datum/priority_queue/proc/dequeue_rank(rank)
	var/removed = FALSE
	for(var/datum/priority_queue_entry/entry as anything in entries.Copy())
		if(entry.rank != rank)
			continue
		entries -= entry
		qdel(entry)
		removed = TRUE
	return removed

/datum/priority_queue/proc/entry_for(datum/item)
	for(var/datum/priority_queue_entry/entry as anything in entries)
		if(entry.resolve() == item)
			return entry
	return null

/**
 * Highest-rank item that still exists. `accept` can skip entries the caller cannot act on.
 * Among equal ranks, nearest to `origin` wins; without an origin the first at that rank wins.
 */
/datum/priority_queue/proc/peek(datum/callback/accept, atom/origin) as /datum
	var/datum/best
	var/best_rank = -1
	var/best_dist = INFINITY
	for(var/datum/priority_queue_entry/entry as anything in entries)
		var/datum/item = entry.resolve()
		if(QDELETED(item))
			continue
		if(!isnull(accept) && !accept.Invoke(item))
			continue
		if(entry.rank < best_rank)
			continue
		var/dist = 0
		if(!isnull(origin) && isatom(item))
			dist = get_dist(get_turf(origin), get_turf(item))
		if(entry.rank == best_rank && dist >= best_dist)
			continue
		best = item
		best_rank = entry.rank
		best_dist = dist
	return best
