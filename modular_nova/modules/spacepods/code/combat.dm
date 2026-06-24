// MODULE ID: SPACEPODS
// Hostile-AI targeting hooks for /obj/spacepod.
//
// Pilots ride inside the pod, so they are invisible to hearers()/view() scans. Mechas solve this
// with an explicit GLOB.mechas_list pass and hostile_machines typecache entries; spacepods need the
// same treatment via GLOB.spacepods_list.

/mob/living/simple_animal/hostile/ListTargets()
	. = ..()
	if(search_objects)
		return
	var/atom/target_from = GET_TARGETS_FROM(src)
	for(var/obj/spacepod/pod as anything in GLOB.spacepods_list)
		if(get_dist(pod, target_from) > vision_range)
			continue
		if(!can_see(target_from, pod, vision_range))
			continue
		. += pod

/mob/living/simple_animal/hostile/ListTargetsLazy(_Z)
	. = ..()
	for(var/I in SSmobs.clients_by_zlevel[_Z])
		var/mob/M = I
		if(get_dist(M, src) >= vision_range)
			continue
		if(!isspacepod(M.loc))
			continue
		if(M.loc in .)
			continue
		. += M.loc

/mob/living/simple_animal/hostile/CanAttack(atom/the_target)
	if(isspacepod(the_target))
		var/obj/spacepod/pod = the_target
		if(pod.pilot && CanAttack(pod.pilot))
			return TRUE
		for(var/mob/living/passenger as anything in pod.passengers)
			if(CanAttack(passenger))
				return TRUE
		return FALSE
	return ..()
