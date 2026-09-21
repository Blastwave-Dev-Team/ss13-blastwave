/**
 * Chase the head of a [BB_PRIORITY_TARGET_QUEUE] ahead of ordinary living-target find.
 *
 * Does not finish planning: locking a priority target should suppress retargeting, not skip melee.
 * Pair with a find-target subtree that calls [select_target] and returns early when it is set.
 *
 * Subtypes override [resolve_target] when the queued atom is a proxy for the thing to hit, and
 * [valid_target] when the pawn cannot currently act on the head (out of reach, wrong room, etc).
 * The head stays the head even then; we wait rather than falling through to a lower rank.
 */
/datum/ai_planning_subtree/target_from_priority_queue
	var/queue_key = BB_PRIORITY_TARGET_QUEUE
	var/target_key = BB_BASIC_MOB_CURRENT_TARGET

/datum/ai_planning_subtree/target_from_priority_queue/SelectBehaviors(datum/ai_controller/controller, seconds_per_tick)
	var/atom/target = select_target(controller)
	if(QDELETED(target))
		return
	controller.set_blackboard_key(target_key, target)

/// The resolved, currently-actionable head, or null. Find-target subtrees use this to stand down.
/datum/ai_planning_subtree/target_from_priority_queue/proc/select_target(datum/ai_controller/controller)
	var/datum/priority_queue/queue = controller.blackboard[queue_key]
	if(isnull(queue))
		return null
	var/atom/head = queue.peek(CALLBACK(src, PROC_REF(accept_entry), controller), controller.pawn)
	if(QDELETED(head))
		return null
	var/atom/resolved = resolve_target(controller, head)
	if(QDELETED(resolved) || !valid_target(controller, resolved))
		return null
	return resolved

/// Whether a queued item is eligible to be the head. Default is "still exists".
/datum/ai_planning_subtree/target_from_priority_queue/proc/accept_entry(datum/ai_controller/controller, datum/item)
	return TRUE

/datum/ai_planning_subtree/target_from_priority_queue/proc/resolve_target(datum/ai_controller/controller, atom/queued)
	return queued

/datum/ai_planning_subtree/target_from_priority_queue/proc/valid_target(datum/ai_controller/controller, atom/target)
	return !QDELETED(target)
