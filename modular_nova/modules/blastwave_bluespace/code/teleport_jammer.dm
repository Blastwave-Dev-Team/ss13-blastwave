// MODULE ID: BLASTWAVE_BLUESPACE
// The buildable end of bluespace interdiction. Registry and coverage maths live in teleport_jam.dm.

/**
 * Bluespace interdiction array
 *
 * A compact machine that floods the local bluespace shell with junk harmonics while powered and
 * switched on. Not the encounter's field source; this is the reusable piece for ships and private
 * ruins that should be beacon-dark.
 *
 * How far it reaches comes off its capacitor, so the salvaged tier-four arrays that black out an
 * entire sector are worth stripping for the part rather than the frame.
 */
/obj/machinery/teleport_jammer
	name = "bluespace interdiction array"
	desc = "A squat phase-array that floods the local bluespace shell with junk harmonics. Nothing can open a portal to or \
		from the space it covers, and tracking beacons inside it cannot be locked from outside."
	icon = 'icons/obj/machines/field_generator.dmi'
	icon_state = "Field_Gen"
	density = TRUE
	max_integrity = 250
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION * 0.5
	active_power_usage = BASE_MACHINE_ACTIVE_CONSUMPTION * 2
	power_channel = AREA_USAGE_ENVIRON
	circuit = /obj/item/circuitboard/machine/teleport_jammer
	/// Whether the operator has switched the array on. Independent of whether it has the power to run.
	var/enabled = TRUE
	/// Tile radius we interdict, or JAM_RANGE_WHOLE_Z for the whole level. Set from the capacitor.
	var/jam_range = 20
	/// The Z we currently hold a jam on, if any. Null means we are not jamming.
	var/jammed_z

/obj/machinery/teleport_jammer/Initialize(mapload)
	. = ..()
	set_wires(new /datum/wires/teleport_jammer(src))
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

/obj/machinery/teleport_jammer/RefreshParts()
	. = ..()

	var/tier = 0
	for(var/datum/stock_part/capacitor/capacitor in component_parts)
		tier = max(tier, capacitor.tier)

	switch(tier)
		if(2)
			jam_range = 40
		if(3)
			jam_range = 100
		if(4 to INFINITY)
			jam_range = JAM_RANGE_WHOLE_Z
		else
			// Tier one, and the no-capacitor case a malformed board could hand us.
			jam_range = 20

	// Runs inside /obj/machinery/Initialize() on the way up, before our own body. Harmless there,
	// since update_jam() only reconciles, and our Initialize() gets the last word anyway.
	update_jam()

/// Human-readable coverage, shared by examine and the wire status readout.
/obj/machinery/teleport_jammer/proc/coverage_readout()
	return jam_range == JAM_RANGE_WHOLE_Z ? "the entire sector" : "a [jam_range] metre shell"

/obj/machinery/teleport_jammer/examine(mob/user)
	. = ..()
	. += span_notice("The interdiction switch is set to <b>[enabled ? "ARMED" : "STANDBY"]</b>, rated to saturate [coverage_readout()].")
	if(panel_open)
		. += span_notice("Its maintenance hatch is open, exposing the harmonic drivers' wiring.")
	else
		. += span_notice("Its maintenance hatch is screwed shut.")

	if(wires_severed())
		. += span_warning("A driver lead has been cut. The array cannot saturate anything until it is mended.")
	else if(enabled && !is_jamming())
		. += span_warning("Its status board is dark. It is not drawing enough power to saturate anything.")

/obj/machinery/teleport_jammer/screwdriver_act(mob/living/user, obj/item/tool)
	return default_deconstruction_screwdriver(user, tool)

/obj/machinery/teleport_jammer/crowbar_act(mob/living/user, obj/item/tool)
	return default_deconstruction_crowbar(user, tool)

/obj/machinery/teleport_jammer/interact(mob/user)
	. = ..()
	if(.)
		return

	// An open hatch means whoever is here came for the wiring, not the switch.
	if(panel_open)
		wires.interact(user)
		return TRUE

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

/// TRUE while a live wire is cut, which holds the field down without touching the arming switch.
/obj/machinery/teleport_jammer/proc/wires_severed()
	if(isnull(wires))
		return FALSE
	return wires.is_cut(WIRE_ACTIVATE) || wires.is_cut(WIRE_POWER)

/// Reconciles the jam we hold against the jam we should hold. Safe to call from anywhere, any number of times.
/obj/machinery/teleport_jammer/proc/update_jam()
	var/turf/our_turf = get_turf(src)
	var/target_z = (enabled && is_operational && !wires_severed() && our_turf) ? our_turf.z : null
	var/was_jamming = is_jamming()

	if(isnull(target_z))
		release_jam()
	else
		if(!isnull(jammed_z) && jammed_z != target_z)
			release_jam()
		// Always re-register, even on the Z we already hold: add_teleport_jam() replaces the claim
		// in place, which is how a part swap reports its new range without the field dropping first.
		add_teleport_jam(target_z, src, jam_range)
		jammed_z = target_z

	if(was_jamming != is_jamming())
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

/**
 * Interdiction array wiring
 *
 * Two live wires, either of which holds the field down. Unlike the hangar interlock these are
 * reversible on purpose: cutting one is how you silently switch a running array off without
 * dismantling it, and mending both is how the owner switches it back on.
 */
/datum/wires/teleport_jammer
	holder_type = /obj/machinery/teleport_jammer
	proper_name = "Bluespace Interdiction Array"

/datum/wires/teleport_jammer/New(atom/holder)
	wires = list(
		WIRE_ACTIVATE, // cut: drops the field until mended
		WIRE_POWER, // cut: same, by starving the harmonic drivers
		WIRE_SIGNAL, // pulse: reads back status
	)
	add_duds(2)
	return ..()

/datum/wires/teleport_jammer/interactable(mob/user)
	var/obj/machinery/teleport_jammer/jammer = holder
	return ..() && jammer.panel_open

/datum/wires/teleport_jammer/get_status()
	var/obj/machinery/teleport_jammer/jammer = holder
	var/list/status = list()
	status += "The saturation light is [jammer.is_jamming() ? "lit" : "dark"]."
	status += "The coverage gauge is calibrated for [jammer.coverage_readout()]."
	return status

/datum/wires/teleport_jammer/on_cut(wire, mend, mob/living/source)
	var/obj/machinery/teleport_jammer/jammer = holder
	switch(wire)
		if(WIRE_ACTIVATE, WIRE_POWER)
			// wires_severed() reads both leads, so mending one of two correctly changes nothing.
			jammer.update_jam()

/datum/wires/teleport_jammer/on_pulse(wire, mob/living/user)
	var/obj/machinery/teleport_jammer/jammer = holder
	if(wire != WIRE_SIGNAL)
		return
	to_chat(user, span_notice("[jammer] chirps: interdiction [jammer.is_jamming() ? "nominal across [jammer.coverage_readout()]" : "offline"]."))
