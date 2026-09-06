// MODULE ID: BLASTWAVE_BLUESPACE
// Z-level bluespace interdiction. A jammed Z refuses every teleport into or out of it.
// Static maps declare ZTRAIT_NO_TELEPORT in their JSON; runtime sources register through add_teleport_jam().

/// Assoc list of "[z]" -> list of datums currently jamming that Z.
GLOBAL_LIST_EMPTY(teleport_jam_sources)

/**
 * Registers source as jamming bluespace on z_level.
 *
 * Sources are refcounted, so two overlapping jammers on the same Z each have to release before teleports work again.
 *
 * Arguments:
 * * z_level - the Z to jam.
 * * source - the datum responsible. Must be passed back to remove_teleport_jam().
 */
/proc/add_teleport_jam(z_level, datum/source)
	if(!isnum(z_level) || z_level < 1 || isnull(source))
		return FALSE

	var/key = "[z_level]"
	var/list/sources = GLOB.teleport_jam_sources[key]
	if(isnull(sources))
		sources = list()
		GLOB.teleport_jam_sources[key] = sources
	if(source in sources)
		return FALSE

	sources += source
	return TRUE

/// Releases source's claim on z_level. See add_teleport_jam().
/proc/remove_teleport_jam(z_level, datum/source)
	if(!isnum(z_level) || z_level < 1 || isnull(source))
		return FALSE

	var/key = "[z_level]"
	var/list/sources = GLOB.teleport_jam_sources[key]
	if(!(source in sources))
		return FALSE

	sources -= source
	if(!length(sources))
		GLOB.teleport_jam_sources -= key
	return TRUE

/// Whether bluespace on z_level is interdicted, either by a runtime source or by the level's own traits.
/proc/is_teleport_jammed(z_level)
	SHOULD_BE_PURE(TRUE)

	if(!isnum(z_level) || z_level < 1)
		return FALSE
	if(length(GLOB.teleport_jam_sources["[z_level]"]))
		return TRUE
	return !!SSmapping.level_trait(z_level, ZTRAIT_NO_TELEPORT)

/**
 * Bluespace interdiction array
 *
 * A compact, mappable machine that jams its own Z while powered and switched on. Not the encounter's field source;
 * this is the reusable piece for ships and private ruins that should be beacon-dark.
 */
/obj/machinery/teleport_jammer
	name = "bluespace interdiction array"
	desc = "A squat phase-array that floods the local bluespace shell with junk harmonics. Nothing can open a portal to or \
		from this sector while it runs, and tracking beacons here cannot be locked from outside."
	icon = 'icons/obj/machines/field_generator.dmi'
	icon_state = "Field_Gen"
	density = TRUE
	max_integrity = 250
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION * 0.5
	active_power_usage = BASE_MACHINE_ACTIVE_CONSUMPTION * 2
	power_channel = AREA_USAGE_ENVIRON
	/// Whether the operator has switched the array on. Independent of whether it has the power to run.
	var/enabled = TRUE
	/// The Z we currently hold a jam on, if any. Null means we are not jamming.
	var/jammed_z

/obj/machinery/teleport_jammer/Initialize(mapload)
	. = ..()
	update_jam()

/obj/machinery/teleport_jammer/Destroy()
	release_jam()
	return ..()

/// Self-powered variant for derelicts and ruins that have no APC behind them.
/obj/machinery/teleport_jammer/self_powered
	use_power = NO_POWER_USE
	idle_power_usage = 0
	active_power_usage = 0

/// Starts switched off, for mappers who want players to be the ones who turn it on.
/obj/machinery/teleport_jammer/off
	enabled = FALSE

/obj/machinery/teleport_jammer/examine(mob/user)
	. = ..()
	. += span_notice("The interdiction switch is set to <b>[enabled ? "ARMED" : "STANDBY"]</b>.")
	if(enabled && !is_jamming())
		. += span_warning("Its status board is dark. It is not drawing enough power to saturate anything.")

/obj/machinery/teleport_jammer/interact(mob/user)
	. = ..()
	if(.)
		return

	enabled = !enabled
	balloon_alert(user, enabled ? "armed" : "standby")
	playsound(src, 'sound/machines/click.ogg', 50, TRUE)
	update_jam()
	return TRUE

/obj/machinery/teleport_jammer/on_set_is_operational(old_value)
	. = ..()
	update_jam()

/obj/machinery/teleport_jammer/Moved(atom/old_loc, movement_dir, forced, list/old_locs, momentum_change = TRUE)
	. = ..()
	update_jam()

/obj/machinery/teleport_jammer/on_changed_z_level(turf/old_turf, turf/new_turf, same_z_layer, notify_contents)
	. = ..()
	update_jam()

/// Whether we are currently holding a jam.
/obj/machinery/teleport_jammer/proc/is_jamming()
	return !isnull(jammed_z)

/// Reconciles the jam we hold against the jam we should hold. Safe to call from anywhere, any number of times.
/obj/machinery/teleport_jammer/proc/update_jam()
	var/turf/our_turf = get_turf(src)
	var/target_z = (enabled && is_operational && our_turf) ? our_turf.z : null

	if(jammed_z == target_z)
		return

	release_jam()
	if(isnull(target_z))
		update_appearance()
		return

	add_teleport_jam(target_z, src)
	jammed_z = target_z
	update_appearance()

/// Drops the jam we hold, if any.
/obj/machinery/teleport_jammer/proc/release_jam()
	if(isnull(jammed_z))
		return
	remove_teleport_jam(jammed_z, src)
	jammed_z = null

/obj/machinery/teleport_jammer/update_overlays()
	. = ..()
	if(!is_jamming())
		return
	. += "+on"
	. += emissive_appearance(icon, "+on", src, alpha = src.alpha)
