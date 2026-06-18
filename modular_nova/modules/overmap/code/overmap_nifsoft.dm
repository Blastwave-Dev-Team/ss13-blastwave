// MODULE ID: OVERMAP
// Pilot NIFSoft: grants direct overmap piloting via the NIF implant.
// Independent from the neurohelm path. Activating both simultaneously
// causes feedback shock (conflict penalty).

/datum/nifsoft/overmap_pilot
	name = "Overmap Pilot Interface"
	program_desc = "Neural ship control software. When active, your perspective shifts to the overmap and movement commands translate to ship thrust."
	active_mode = TRUE
	active_cost = 3
	activation_cost = 5
	purchase_price = 800
	buying_category = NIFSOFT_CATEGORY_GENERAL
	ui_icon = "rocket"

	/// The active pilot link datum.
	var/datum/overmap_pilot_link/pilot_link

/datum/nifsoft/overmap_pilot/Destroy()
	stop_piloting()
	return ..()

/datum/nifsoft/overmap_pilot/activate()
	. = ..()
	if(!.)
		return FALSE
	if(active)
		start_piloting()
	else
		stop_piloting()
	return TRUE

/datum/nifsoft/overmap_pilot/on_emp(emp_severity)
	stop_piloting()
	..()

/datum/nifsoft/overmap_pilot/proc/start_piloting()
	if(!linked_mob)
		return

	// Conflict check: neurohelm piloting active?
	if(HAS_TRAIT(linked_mob, TRAIT_NEUROHELM_PILOTING))
		to_chat(linked_mob, span_danger("Conflicting neural signals from your neurohelm cause searing feedback!"))
		linked_mob.apply_damage(15, BURN, BODY_ZONE_HEAD)
		linked_mob.Stun(2 SECONDS)
		// Force deactivate
		active = FALSE
		var/obj/item/organ/cyberimp/brain/nif/installed_nif = parent_nif?.resolve()
		if(installed_nif)
			installed_nif.power_usage -= active_cost
		return

	// Resolve ship from shuttle
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(linked_mob)
	if(!port?.current_ship)
		to_chat(linked_mob, span_warning("You are not aboard a ship with overmap presence."))
		deactivate_self()
		return
	var/obj/structure/overmap/ship/ship = port.current_ship
	if(!istype(ship))
		to_chat(linked_mob, span_warning("Cannot resolve ship for piloting."))
		deactivate_self()
		return

	pilot_link = new(linked_mob, ship)
	if(!pilot_link.establish())
		QDEL_NULL(pilot_link)
		to_chat(linked_mob, span_warning("Failed to establish neural link."))
		deactivate_self()
		return

	ADD_TRAIT(linked_mob, TRAIT_NIF_PILOTING, REF(src))
	to_chat(linked_mob, span_notice("Neural pilot link established. Your vision shifts to the overmap."))

/datum/nifsoft/overmap_pilot/proc/stop_piloting()
	if(pilot_link?.linked_mob)
		REMOVE_TRAIT(pilot_link.linked_mob, TRAIT_NIF_PILOTING, REF(src))
	QDEL_NULL(pilot_link)

/// Helper to cleanly deactivate without triggering the activate toggle.
/datum/nifsoft/overmap_pilot/proc/deactivate_self()
	if(!active)
		return
	active = FALSE
	var/obj/item/organ/cyberimp/brain/nif/installed_nif = parent_nif?.resolve()
	if(installed_nif)
		installed_nif.power_usage -= active_cost
