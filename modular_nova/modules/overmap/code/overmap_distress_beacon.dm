// MODULE ID: OVERMAP
// Wall-mount NT distress beacon — provides an additional evac call path.
// Additive only in v1: Communications Console retains its existing call.

/obj/machinery/distress_beacon
	name = "distress beacon"
	desc = "A wall-mounted emergency distress beacon. Activating this will call the emergency evacuation shuttle."
	icon = 'modular_nova/modules/overmap/icons/stationary_beacons.dmi'
	icon_state = "nt_beacon"
	base_icon_state = "nt_beacon"
	density = FALSE
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION * 0.5
	circuit = null
	/// Whether the beacon is currently transmitting (shuttle called).
	var/transmitting = FALSE

MAPPING_DIRECTIONAL_HELPERS(/obj/machinery/distress_beacon, 28)

/obj/machinery/distress_beacon/update_icon_state()
	. = ..()
	if(transmitting)
		icon_state = "[base_icon_state]_active"
	else
		icon_state = base_icon_state

/obj/machinery/distress_beacon/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "DistressBeacon")
		ui.open()

/obj/machinery/distress_beacon/ui_data(mob/user)
	var/list/data = list()
	data["transmitting"] = transmitting
	data["shuttle_status"] = SSshuttle.emergency?.getStatusText()
	data["shuttle_called"] = (SSshuttle.emergency?.mode == SHUTTLE_CALL)
	data["security_level"] = SSsecurity_level.get_current_level_as_number()
	data["can_call"] = can_call_evac(user)
	return data

/obj/machinery/distress_beacon/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return

	if(action == "call_evac")
		var/mob/user = ui.user
		if(!can_call_evac(user))
			return TRUE
		var/reason = params["reason"]
		if(!reason || length(trim(reason)) < 10)
			to_chat(user, span_warning("You must provide a reason of at least 10 characters."))
			return TRUE
		SSshuttle.requestEvac(user, reason)
		transmitting = TRUE
		update_appearance()
		return TRUE

/obj/machinery/distress_beacon/proc/can_call_evac(mob/user)
	if(transmitting)
		return FALSE
	if(SSshuttle.emergency?.mode != SHUTTLE_IDLE && SSshuttle.emergency?.mode != SHUTTLE_RECALL)
		return FALSE
	if(SSsecurity_level.get_current_level_as_number() <= SEC_LEVEL_GREEN)
		return FALSE
	if(!isliving(user))
		return FALSE
	return TRUE
