// MODULE ID: OVERMAP
// Reusable hangar lockdown set piece. A mapped controller slams id-matched blast
// doors the moment a ship sets down, and only opens them again when somebody
// unscrews its maintenance panel and cuts the wiring.
//
// Deliberately not a click-to-lift console: the point is that the trap stays shut
// while players deal with whatever is on the other side of it.
//
// The closed doors are the whole lock. There is no software launch interlock,
// because the bay-exit raycast in overmap_bay_exit.dm treats a closed blast door
// as a wall, so a sealed bay physically refuses to let a ship leave.

/**
 * Hangar lockdown controller
 *
 * Mapped alongside `/obj/machinery/door/poddoor` sharing its `id`, the way blast door buttons are.
 * Arms itself when a ship lands on its Z and stays armed; cutting its wiring is the only way out.
 */
/obj/machinery/hangar_lockdown
	name = "hangar containment controller"
	desc = "A door interlock wired into a bay's blast doors. The status plate lists a containment protocol, \
		a revision date, and no override code."
	icon = 'icons/obj/machines/wallmounts.dmi'
	icon_state = "airlock_control_standby"
	density = FALSE
	max_integrity = 300
	// Blast doors are heavy enough that smashing the controller must not be the answer. Cut the wires.
	resistance_flags = FIRE_PROOF | ACID_PROOF
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION * 0.25
	power_channel = AREA_USAGE_ENVIRON
	/// Shared with the blast doors we drive. Mapper-set, and the only thing tying the set piece together.
	var/id
	/// Whether the lockdown has fired and is holding the bay shut.
	var/engaged = FALSE
	/// Set when the wiring is cut. A disabled controller never re-arms, so later landings are free.
	var/disabled = FALSE

/obj/machinery/hangar_lockdown/Initialize(mapload)
	. = ..()
	set_wires(new /datum/wires/hangar_lockdown(src))
	RegisterSignal(SSdcs, COMSIG_GLOB_OVERMAP_SHIP_DOCKED, PROC_REF(on_ship_docked))
	if(mapload && isnull(id))
		log_mapping("[src] at [AREACOORD(src)] has no id and will never find its blast doors.")

/// Pre-armed variant, for bays that should already be sealed when players arrive.
/obj/machinery/hangar_lockdown/engaged
	engaged = TRUE

/// Self-powered variant for derelicts with no working APC.
/obj/machinery/hangar_lockdown/self_powered
	use_power = NO_POWER_USE
	idle_power_usage = 0

/obj/machinery/hangar_lockdown/examine(mob/user)
	. = ..()
	if(disabled)
		. += span_notice("Its interlock light is dead. The bay doors answer to nothing now.")
	else if(engaged)
		. += span_danger("The interlock light is a hard red. CONTAINMENT ENGAGED.")
	else
		. += span_notice("The interlock light idles amber, waiting on a touchdown it has been waiting on for years.")
	. += span_notice("The maintenance panel is [panel_open ? "open" : "screwed shut"].")

/obj/machinery/hangar_lockdown/screwdriver_act(mob/living/user, obj/item/tool)
	toggle_panel_open()
	tool.play_tool_sound(src)
	balloon_alert_to_viewers("panel [panel_open ? "opened" : "closed"]")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/hangar_lockdown/tool_act(mob/living/user, obj/item/tool, list/modifiers)
	. = ..()
	if(. & ITEM_INTERACT_ANY_BLOCKER)
		return .
	if(!is_wire_tool(tool))
		return NONE
	if(!panel_open)
		balloon_alert(user, "panel is screwed shut!")
		return ITEM_INTERACT_BLOCKING
	wires.interact(user)
	return ITEM_INTERACT_SUCCESS

/// Fires when any overmap ship finishes setting down. We only care about our own Z.
/obj/machinery/hangar_lockdown/proc/on_ship_docked(datum/source, obj/structure/overmap/ship/simulated/ship, obj/structure/overmap/site, obj/effect/landmark/overmap_landing_zone/zone)
	SIGNAL_HANDLER

	if(disabled || engaged)
		return
	var/turf/our_turf = get_turf(src)
	if(isnull(our_turf) || ship?.shuttle?.z != our_turf.z)
		return
	engage()

/// Slams the bay shut. Idempotent.
/obj/machinery/hangar_lockdown/proc/engage()
	if(disabled || engaged)
		return
	engaged = TRUE
	for(var/obj/machinery/door/poddoor/door as anything in get_managed_doors())
		INVOKE_ASYNC(door, TYPE_PROC_REF(/obj/machinery/door, close))
	update_appearance()
	playsound(src, 'sound/machines/buzz/buzz-two.ogg', 65, FALSE)
	say("CONTAINMENT PROTOCOL ENGAGED. BAY SEALED PENDING DECONTAMINATION.")

/**
 * Permanently stands the lockdown down. Called when the wiring is cut.
 *
 * Unlike engage() this is sticky: `disabled` gates on_ship_docked(), so a later landing on the same
 * pad will not seal the bay again. Mending the wire is the only way back, which is what makes this
 * reusable on a station without making ruins re-lockable.
 */
/obj/machinery/hangar_lockdown/proc/disengage()
	disabled = TRUE
	engaged = FALSE
	for(var/obj/machinery/door/poddoor/door as anything in get_managed_doors())
		INVOKE_ASYNC(door, TYPE_PROC_REF(/obj/machinery/door, open))
	update_appearance()
	playsound(src, 'sound/machines/click.ogg', 50, TRUE)

/// Restores the controller's ability to arm. Called when the wiring is mended.
/obj/machinery/hangar_lockdown/proc/rearm()
	disabled = FALSE
	update_appearance()

/// Every blast door sharing our id on our Z. Id is the contract; Z is the sanity guard.
/obj/machinery/hangar_lockdown/proc/get_managed_doors()
	var/list/found = list()
	if(isnull(id))
		return found
	var/turf/our_turf = get_turf(src)
	if(isnull(our_turf))
		return found
	for(var/obj/machinery/door/poddoor/door as anything in SSmachines.get_machines_by_type_and_subtypes(/obj/machinery/door/poddoor))
		if(door.id != id || door.z != our_turf.z)
			continue
		found += door
	return found

/obj/machinery/hangar_lockdown/update_icon_state()
	if(disabled || !is_operational)
		icon_state = "airlock_control_off"
	else if(engaged)
		icon_state = "airlock_control_process"
	else
		icon_state = "airlock_control_standby"
	return ..()

/**
 * Hangar lockdown wiring
 *
 * Two live wires, either of which stands the interlock down permanently, plus a status wire and duds.
 * Pulsing is deliberately useless: a multitool must not become a free door toggle.
 */
/datum/wires/hangar_lockdown
	holder_type = /obj/machinery/hangar_lockdown
	proper_name = "Hangar Containment Controller"

/datum/wires/hangar_lockdown/New(atom/holder)
	wires = list(
		WIRE_LOCKDOWN, // cut: permanently stands the interlock down
		WIRE_POWER, // cut: same, by starving the door drivers
		WIRE_SIGNAL, // pulse: reads back status
	)
	add_duds(2)
	return ..()

/datum/wires/hangar_lockdown/interactable(mob/user)
	var/obj/machinery/hangar_lockdown/controller = holder
	return ..() && controller.panel_open

/datum/wires/hangar_lockdown/get_status()
	var/obj/machinery/hangar_lockdown/controller = holder
	var/list/status = list()
	status += "The interlock light is [controller.disabled ? "dark" : (controller.engaged ? "red" : "amber")]."
	status += "The door bus reports [length(controller.get_managed_doors())] blast door(s) on this circuit."
	return status

/datum/wires/hangar_lockdown/on_cut(wire, mend, mob/living/source)
	var/obj/machinery/hangar_lockdown/controller = holder
	switch(wire)
		if(WIRE_LOCKDOWN, WIRE_POWER)
			if(mend)
				// Only re-arm once every live wire is whole again, otherwise mending one of two does nothing.
				if(!is_cut(WIRE_LOCKDOWN) && !is_cut(WIRE_POWER))
					controller.rearm()
			else
				controller.disengage()

/datum/wires/hangar_lockdown/on_pulse(wire, mob/living/user)
	var/obj/machinery/hangar_lockdown/controller = holder
	if(wire != WIRE_SIGNAL)
		return
	to_chat(user, span_notice("[controller] chirps: containment [controller.disabled ? "offline" : (controller.engaged ? "engaged" : "armed")]."))
