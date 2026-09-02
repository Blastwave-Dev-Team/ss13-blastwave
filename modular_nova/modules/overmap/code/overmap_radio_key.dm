// MODULE ID: OVERMAP
// Blank overmap encryption key, antenna programming, and keyed-intercom craft.

/obj/item/encryptionkey/overmap
	name = "blank deep-space encryption key"
	desc = "An unprogrammed long-range key. Use in-hand to open an unencrypted deep-space channel, or tap it with a multitool buffering a deep-space array to copy that cipher."
	icon = 'modular_nova/modules/overmap/icons/overmap_encryptionkey.dmi'
	icon_state = "overmap"
	post_init_icon_state = null
	greyscale_config = null
	greyscale_colors = null
	channels = list()
	/// Cipher stamped from an antenna. Null means open / unencrypted.
	var/network_cipher
	var/programmed = FALSE

/obj/item/encryptionkey/overmap/examine(mob/user)
	. = ..()
	if(!programmed)
		. += span_notice("Unprogrammed. Use in-hand for an open deep-space channel, or copy a cipher from an array.")
		return
	if(network_cipher)
		. += span_notice("Linked to a private deep-space network.")
	else
		. += span_notice("Open deep-space channel on [FREQ_OVERMAP / 10]. Anyone on this frequency can hear.")

/obj/item/encryptionkey/overmap/attack_self(mob/user)
	if(programmed && !network_cipher)
		balloon_alert(user, "already open")
		return
	if(programmed && network_cipher)
		if(tgui_alert(user, "Clear the linked cipher and open the deep-space channel?", name, list("Clear", "Cancel")) != "Clear")
			return
		network_cipher = null
	channels = list(RADIO_CHANNEL_OVERMAP = 1)
	programmed = TRUE
	name = "deep-space encryption key"
	balloon_alert(user, "open channel set")
	to_chat(user, span_notice("Key tuned to the open deep-space frequency ([FREQ_OVERMAP / 10]). Anyone with a matching key can hear."))

/obj/item/encryptionkey/overmap/proc/stamp_from_antenna(obj/machinery/overmap_radio/antenna/antenna, mob/user)
	if(!antenna?.network_cipher)
		return FALSE
	network_cipher = antenna.network_cipher
	channels = list(RADIO_CHANNEL_OVERMAP = 1)
	programmed = TRUE
	name = "linked deep-space encryption key"
	if(user)
		balloon_alert(user, "cipher stamped")
		to_chat(user, span_notice("Copied [antenna]'s network cipher onto [src]."))
	return TRUE

/obj/item/encryptionkey/overmap/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	if(!istype(tool, /obj/item/multitool))
		return NONE
	var/obj/item/multitool/multitool = tool
	if(!istype(multitool.buffer, /obj/machinery/overmap_radio/antenna))
		balloon_alert(user, "no array buffered")
		return ITEM_INTERACT_BLOCKING
	stamp_from_antenna(multitool.buffer, user)
	return ITEM_INTERACT_SUCCESS

/// Unencrypted traffic is audible to any overmap radio. Ciphered traffic needs a match.
/obj/item/radio/proc/can_hear_overmap_cipher(cipher)
	if(!cipher)
		return TRUE
	return overmap_cipher == cipher

/obj/item/radio/intercom/on_craft_completion(list/components, datum/crafting_recipe/current_recipe, atom/crafter)
	. = ..()
	if(keyslot)
		return
	var/obj/item/encryptionkey/key = locate() in src
	if(!key)
		return
	keyslot = key
	recalculateChannels()

/datum/crafting_recipe/keyed_intercom
	name = "Keyed Intercom"
	desc = "An intercom frame with an encryption key installed."
	result = /obj/item/radio/intercom/unscrewed
	reqs = list(
		/obj/item/wallframe/intercom = 1,
		/obj/item/encryptionkey = 1,
	)
	parts = list(/obj/item/encryptionkey = 1)
	time = 2 SECONDS
	category = CAT_EQUIPMENT
	crafting_flags = CRAFT_CHECK_DENSITY
