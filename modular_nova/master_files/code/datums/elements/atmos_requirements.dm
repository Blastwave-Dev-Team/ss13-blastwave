// MODULE ID: OVERMAP

/**
 * Don't call a corpse spawner's mob a mapping error.
 *
 * A corpse spawner builds its mob alive and kills it on the line after the one that
 * made it, so for that one line there is something breathing whatever the ruin has -
 * vacuum, for the airless ones. Loading a template before SSair comes up hides that,
 * because the mob then defers this check until the subsystem is ready and is long
 * dead by the time it runs. Everything loaded afterwards, which is every overmap site
 * and every dynamic encounter, is checked during the live line instead, and reports a
 * stock space ruin as a mob mapped somewhere it cannot survive.
 *
 * The spawner does not leave its tile until the mob it made is dead, so its presence
 * is what tells the two apart.
 */
/datum/element/atmos_requirements/check_safe_environment(mob/living/living_mob)
	if(locate(/obj/effect/mob_spawn/corpse) in living_mob.loc)
		return
	return ..()
