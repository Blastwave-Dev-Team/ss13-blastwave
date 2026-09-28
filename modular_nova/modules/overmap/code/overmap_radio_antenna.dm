// MODULE ID: OVERMAP
// Long-range overmap radio antenna. Holds a network cipher that multitool
// copies onto other antennas and blank overmap encryption keys.

/obj/machinery/overmap_radio
	name = "deep-space radio machine"
	desc = "A long-range radio machine."
	abstract_type = /obj/machinery/overmap_radio
	density = TRUE
	anchored = TRUE
	use_power = IDLE_POWER_USE

/obj/machinery/overmap_radio/antenna
	name = "deep-space radio array"
	desc = "A deployable long-range radio array. Multitool it to buffer the cipher, then tap another array or a blank deep-space key."
	icon = 'modular_nova/modules/overmap/icons/long_range_array.dmi'
	icon_state = "long_range_array"
	base_icon_state = "long_range_array"
	density = TRUE
	anchored = TRUE
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION
	circuit = /obj/item/circuitboard/machine/overmap_radio_antenna
	/// Shared cipher for this antenna's overmap network. Generated on first power.
	var/network_cipher
	var/toggled = TRUE
	var/on = FALSE
	var/deployed = FALSE

/obj/machinery/overmap_radio/antenna/Initialize(mapload)
	. = ..()
	register_context()
	if(!network_cipher)
		network_cipher = generate_overmap_radio_cipher()
	update_deploy_state()

/obj/machinery/overmap_radio/antenna/process()
	update_deploy_state()

/obj/machinery/overmap_radio/antenna/proc/update_deploy_state()
	var/was_on = on
	if(toggled)
		on = !(machine_stat & (BROKEN | NOPOWER | EMPED)) && !panel_open
	else
		on = FALSE
	if(was_on == on)
		return
	if(on)
		flick("[base_icon_state]-open", src)
		deployed = TRUE
		addtimer(CALLBACK(src, PROC_REF(finish_deploy)), 1.5 SECONDS)
	else
		flick("[base_icon_state]-close", src)
		deployed = FALSE
		addtimer(CALLBACK(src, PROC_REF(finish_stow)), 1.5 SECONDS)

/obj/machinery/overmap_radio/antenna/proc/finish_deploy()
	if(on && !(machine_stat & BROKEN))
		update_appearance()

/obj/machinery/overmap_radio/antenna/proc/finish_stow()
	if(!on)
		update_appearance()

/obj/machinery/overmap_radio/antenna/update_icon_state()
	if(machine_stat & BROKEN)
		icon_state = deployed ? "[base_icon_state]-deployed-broken" : "[base_icon_state]-broken"
	else if(panel_open)
		icon_state = "[base_icon_state]-maintenance_hatch"
	else if(!on)
		icon_state = base_icon_state
	else
		icon_state = "[base_icon_state]-deployed_active"
	return ..()

/obj/machinery/overmap_radio/antenna/on_set_panel_open(old_value)
	. = ..()
	update_deploy_state()

/obj/machinery/overmap_radio/antenna/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	. = ..()
	if(isnull(held_item))
		return
	if(held_item.tool_behaviour == TOOL_SCREWDRIVER)
		context[SCREENTIP_CONTEXT_LMB] = "[panel_open ? "Close" : "Open"] maintenance hatch"
		return CONTEXTUAL_SCREENTIP_SET
	if(held_item.tool_behaviour == TOOL_CROWBAR && panel_open)
		context[SCREENTIP_CONTEXT_LMB] = "Deconstruct"
		return CONTEXTUAL_SCREENTIP_SET
	if(held_item.tool_behaviour == TOOL_MULTITOOL)
		context[SCREENTIP_CONTEXT_LMB] = "Buffer / copy cipher"
		return CONTEXTUAL_SCREENTIP_SET

/obj/machinery/overmap_radio/antenna/examine(mob/user)
	. = ..()
	if(on)
		. += span_notice("The array is deployed. Use a multitool to buffer its network cipher.")
	else
		. += span_warning("The array is stowed.")
	. += span_notice("A <i>screwdriver</i> [panel_open ? "closes" : "opens"] the maintenance hatch[panel_open ? ", and a <i>crowbar</i> deconstructs it" : ""].")

/obj/machinery/overmap_radio/antenna/multitool_act(mob/living/user, obj/item/tool)
	if(!istype(tool, /obj/item/multitool))
		return NONE
	var/obj/item/multitool/multitool = tool
	if(istype(multitool.buffer, /obj/machinery/overmap_radio/antenna))
		var/obj/machinery/overmap_radio/antenna/other = multitool.buffer
		if(other == src)
			multitool.set_buffer(null)
			balloon_alert(user, "buffer cleared")
			return ITEM_INTERACT_SUCCESS
		if(!other.network_cipher)
			balloon_alert(user, "source has no cipher")
			return ITEM_INTERACT_BLOCKING
		network_cipher = other.network_cipher
		balloon_alert(user, "cipher copied")
		to_chat(user, span_notice("Copied the network cipher from [other] onto [src]."))
		return ITEM_INTERACT_SUCCESS
	multitool.set_buffer(src)
	balloon_alert(user, "cipher buffered")
	return ITEM_INTERACT_SUCCESS

/obj/machinery/overmap_radio/antenna/screwdriver_act(mob/living/user, obj/item/tool)
	return default_deconstruction_screwdriver(user, tool)

/obj/machinery/overmap_radio/antenna/crowbar_act(mob/living/user, obj/item/tool)
	return default_deconstruction_crowbar(user, tool)

/proc/generate_overmap_radio_cipher()
	return copytext_char(md5("[world.timeofday][rand(1, 999999)][GLOB.round_id]"), 1, 13)
