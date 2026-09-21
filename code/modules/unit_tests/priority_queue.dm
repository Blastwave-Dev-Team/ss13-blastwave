/// Identity-keyed priority queue: rank, dequeue, and nearest-among-equals.
/datum/unit_test/priority_queue

/datum/unit_test/priority_queue/Run()
	var/datum/priority_queue/queue = allocate(/datum/priority_queue)
	var/obj/item/low = allocate(/obj/item, run_loc_floor_bottom_left)
	var/obj/item/high = allocate(/obj/item, run_loc_floor_bottom_left)

	queue.enqueue(low, 10)
	queue.enqueue(high, 20)
	TEST_ASSERT_EQUAL(queue.peek(), high, "Peek should return the highest rank.")

	queue.dequeue(high)
	TEST_ASSERT_EQUAL(queue.peek(), low, "Dequeuing the head should expose the next rank.")

	queue.enqueue(high, 10)
	TEST_ASSERT_EQUAL(queue.peek(null, low), low, "Equal ranks should prefer the first nearest to origin.")

	queue.enqueue(high, 30)
	TEST_ASSERT_EQUAL(queue.peek(), high, "Re-enqueueing should update rank instead of duplicating.")

	queue.dequeue_rank(30)
	TEST_ASSERT_EQUAL(queue.peek(), low, "dequeue_rank should drop every entry at that rank.")
	TEST_ASSERT(isnull(queue.peek(CALLBACK(src, PROC_REF(reject_all)))), "An accept callback should be able to skip every entry.")

	var/obj/item/doomed = allocate(/obj/item, run_loc_floor_bottom_left)
	queue.enqueue(doomed, 40)
	var/datum/weakref/held = WEAKREF(doomed)
	qdel(doomed)
	TEST_ASSERT(isnull(queue.peek()), "A deleted item should not peek.")
	TEST_ASSERT(queue.dequeue_ref(held), "dequeue_ref should drop an entry whose weakref no longer resolves.")
	TEST_ASSERT_EQUAL(length(queue.entries), 1, "dequeue_ref should only drop the dead entry.")

/datum/unit_test/priority_queue/proc/reject_all(datum/item)
	return FALSE
