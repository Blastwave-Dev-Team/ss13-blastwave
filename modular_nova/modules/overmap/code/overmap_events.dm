// MODULE ID: OVERMAP
// Overmap event hazards. These are placed on the overmap grid during
// roundstart generation. Ships sharing a tile with an event are affected
// on entry and/or periodically while they remain.

/obj/structure/overmap/event
	name = "unknown spatial anomaly"
	icon_state = "event"
	integrity = 0
	contact_type = "event"
	contact_label = "Hazard"
	/// Should `affect_ship()` fire repeatedly while co-located?
	var/affect_multiple_times = FALSE
	/// Per-tick probability of `affect_ship()` firing (if `affect_multiple_times`).
	var/chance_to_affect = 0
	/// Cardinal spread chance when spawning as a cluster.
	var/spread_chance = 0
	/// Chain length when spawning along an orbital ring (SOLAR mode).
	var/chain_rate = 0

/obj/structure/overmap/event/Initialize(mapload, _id)
	. = ..()
	LAZYADD(SSovermap.events, src)

/obj/structure/overmap/event/Destroy()
	LAZYREMOVE(SSovermap.events, src)
	return ..()

/// Called each SSovermap tick for events with `affect_multiple_times`.
/obj/structure/overmap/event/proc/apply_effect()
	if(!affect_multiple_times)
		return
	for(var/obj/structure/overmap/ship/simulated/S in close_overmap_objects)
		if(prob(chance_to_affect))
			affect_ship(S)

/// The main effect applied to a ship. Override in subtypes.
/obj/structure/overmap/event/proc/affect_ship(obj/structure/overmap/ship/simulated/S)
	return

/// Ships entering the event tile are affected immediately.
/obj/structure/overmap/event/on_overmap_crossed(obj/structure/overmap/other, atom/oldloc)
	. = ..()
	if(istype(other, /obj/structure/overmap/ship/simulated))
		affect_ship(other)

// --- METEOR STORMS ---

/obj/structure/overmap/event/meteor
	name = "asteroid storm (moderate)"
	icon_state = "meteor1"
	contact_type = "meteor"
	contact_label = "Meteor"
	affect_multiple_times = TRUE
	chance_to_affect = 5
	spread_chance = 50
	chain_rate = 4
	var/max_damage = 15
	var/min_damage = 5

/obj/structure/overmap/event/meteor/affect_ship(obj/structure/overmap/ship/simulated/S)
	if(!S.shuttle)
		return
	S.receive_damage(rand(min_damage, max_damage))
	for(var/mob/M in GLOB.player_list)
		if(S.shuttle.is_in_shuttle_bounds(M))
			var/strength = clamp(100 - S.integrity, 10, 50)
			M.playsound_local(S.shuttle, 'sound/effects/explosion/explosionfar.ogg', strength)
			shake_camera(M, 5, strength / 20)

/obj/structure/overmap/event/meteor/minor
	name = "asteroid storm (minor)"
	chain_rate = 3
	max_damage = 10
	min_damage = 3
	spread_chance = 30

/obj/structure/overmap/event/meteor/major
	name = "asteroid storm (major)"
	spread_chance = 25
	chain_rate = 6
	chance_to_affect = 8
	max_damage = 25
	min_damage = 10

// --- ELECTRICAL NEBULA ---

/obj/structure/overmap/event/electric
	name = "charged nebula"
	icon_state = "electrical1"
	contact_type = "electric"
	contact_label = "Nebula"
	affect_multiple_times = TRUE
	chance_to_affect = 10
	spread_chance = 40
	chain_rate = 3
	var/damage = 5

/obj/structure/overmap/event/electric/affect_ship(obj/structure/overmap/ship/simulated/S)
	if(!S.shuttle)
		return
	S.receive_damage(damage)
	for(var/area/shuttle_area in S.shuttle.shuttle_areas)
		for(var/obj/machinery/power/apc/A in shuttle_area)
			if(prob(30))
				A.overload_lighting()

// --- EMP CLOUD ---

/obj/structure/overmap/event/emp
	name = "ion cloud"
	icon_state = "ion1"
	contact_type = "emp"
	contact_label = "Ion"
	spread_chance = 35
	chain_rate = 2
	var/emp_heavy = 3
	var/emp_light = 8

/obj/structure/overmap/event/emp/affect_ship(obj/structure/overmap/ship/simulated/S)
	if(!S.shuttle)
		return
	var/list/areas = S.shuttle.shuttle_areas
	if(!length(areas))
		return
	var/area/target_area = pick(areas)
	var/list/turfs = get_area_turfs(target_area)
	if(!length(turfs))
		return
	var/turf/centre = pick(turfs)
	empulse(centre, emp_heavy, emp_light)

// --- RADIATION BELT ---

/obj/structure/overmap/event/radiation
	name = "radiation belt"
	icon_state = "strange_event"
	contact_type = "radiation"
	contact_label = "Radiation"
	spread_chance = 30
	chain_rate = 3
	affect_multiple_times = TRUE
	chance_to_affect = 3

/obj/structure/overmap/event/radiation/affect_ship(obj/structure/overmap/ship/simulated/S)
	if(!S.shuttle)
		return
	for(var/mob/living/carbon/human/H in GLOB.player_list)
		if(!S.shuttle.is_in_shuttle_bounds(H))
			continue
		if(H.stat == DEAD)
			continue
		H.adjust_tox_loss(rand(1, 3))
