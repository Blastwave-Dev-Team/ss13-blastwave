// MODULE ID: OVERMAP
// Neurohelm: a head-slot item that grants direct overmap piloting.
// Independent from the NIF path. Activating both simultaneously causes
// feedback shock (conflict penalty).

/obj/item/clothing/head/neurohelm
	name = "neurohelm"
	desc = "A neural interface helmet that translates EEG signals into ship control commands. Grants direct astrogation piloting when worn aboard a ship."
	icon = 'icons/obj/clothing/head/helmet.dmi'
	icon_state = "perceptomatrix_helmet_inactive"
	worn_icon = 'icons/mob/clothing/head/helmet.dmi'
	worn_icon_state = "perceptomatrix_helmet_inactive"
	inhand_icon_state = "helmet"
	armor_type = /datum/armor/none
	slot_flags = ITEM_SLOT_HEAD
	w_class = WEIGHT_CLASS_NORMAL
	/// The active pilot link datum when piloting.
	var/datum/overmap_pilot_link/pilot_link
	/// Whether piloting mode is currently active.
	var/piloting = FALSE

/obj/item/clothing/head/neurohelm/Destroy()
	stop_piloting()
	return ..()

/obj/item/clothing/head/neurohelm/dropped(mob/user, force, silent)
	. = ..()
	stop_piloting()

/obj/item/clothing/head/neurohelm/equipped(mob/user, slot)
	. = ..()
	if(slot != ITEM_SLOT_HEAD)
		stop_piloting()

/// Toggle piloting on action button press or attack_self.
/obj/item/clothing/head/neurohelm/attack_self(mob/user)
	if(piloting)
		stop_piloting()
		to_chat(user, span_notice("You deactivate [src]'s neural interface."))
		return
	start_piloting(user)

/obj/item/clothing/head/neurohelm/proc/start_piloting(mob/living/user)
	if(!istype(user))
		return
	if(!user.get_item_by_slot(ITEM_SLOT_HEAD) == src)
		to_chat(user, span_warning("You must be wearing [src] to activate it."))
		return

	// Conflict check: NIF piloting active?
	if(HAS_TRAIT(user, TRAIT_NIF_PILOTING))
		to_chat(user, span_danger("Conflicting neural signals from your NIF cause searing feedback!"))
		user.apply_damage(15, BURN, BODY_ZONE_HEAD)
		user.Stun(2 SECONDS)
		return

	// Resolve ship from shuttle
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(user)
	if(!port?.current_ship)
		to_chat(user, span_warning("You are not aboard a ship with astrogation presence."))
		return
	var/obj/structure/overmap/ship/ship = port.current_ship
	if(!istype(ship))
		to_chat(user, span_warning("Cannot resolve ship for piloting."))
		return

	pilot_link = new(user, ship)
	if(!pilot_link.establish())
		QDEL_NULL(pilot_link)
		to_chat(user, span_warning("Failed to establish neural link."))
		return

	piloting = TRUE
	ADD_TRAIT(user, TRAIT_NEUROHELM_PILOTING, REF(src))
	to_chat(user, span_notice("Neural link established. Your vision shifts to the starmap. Move to thrust."))

/obj/item/clothing/head/neurohelm/proc/stop_piloting()
	if(!piloting)
		return
	piloting = FALSE
	if(pilot_link?.linked_mob)
		REMOVE_TRAIT(pilot_link.linked_mob, TRAIT_NEUROHELM_PILOTING, REF(src))
	QDEL_NULL(pilot_link)
