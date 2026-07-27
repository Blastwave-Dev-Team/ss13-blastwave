// MODULE ID: OVERMAP

/**
 * The temperature half of the corpse spawner exemption.
 *
 * See `modular_nova/master_files/code/datums/elements/atmos_requirements.dm` - the
 * same live moment between a corpse spawner making its mob and killing it, judged
 * against the ruin's temperature rather than its air.
 */
/datum/element/body_temp_sensitive/check_safe_environment(mob/living/living_mob)
	if(locate(/obj/effect/mob_spawn/corpse) in living_mob.loc)
		return
	return ..()
