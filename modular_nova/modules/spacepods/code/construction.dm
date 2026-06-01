// MODULE ID: SPACEPODS
// The 13-state spacepod build/deconstruct chain and examine hints.
// Ported from Whitesands (whitesands/code/modules/spacepods/construction.dm).

/obj/spacepod/examine(mob/user)
	. = ..()
	switch(construction_state) // more construction states than r-walls!
		if(SPACEPOD_EMPTY)
			. += span_notice("The struts holding it together can be <b>cut</b> and it is missing <i>wires</i>.")
		if(SPACEPOD_WIRES_LOOSE)
			. += span_notice("The <b>wires</b> need to be <i>screwed</i> on.")
		if(SPACEPOD_WIRES_SECURED)
			. += span_notice("The wires are <b>screwed</b> on and need a <i>circuit board</i>.")
		if(SPACEPOD_CIRCUIT_LOOSE)
			. += span_notice("The circuit board is <b>loosely attached</b> and needs to be <i>screwed</i> on.")
		if(SPACEPOD_CIRCUIT_SECURED)
			. += span_notice("The circuit board is <b>screwed</b> on, and there is space for a <i>core</i>.")
		if(SPACEPOD_CORE_LOOSE)
			. += span_notice("The core is <b>loosely attached</b> and needs to be <i>bolted</i> on.")
		if(SPACEPOD_CORE_SECURED)
			. += span_notice("The core is <b>bolted</b> on and the <i>metal</i> bulkhead can be attached.")
		if(SPACEPOD_BULKHEAD_LOOSE)
			. += span_notice("The bulkhead is <b>loosely attached</b> and can be <i>bolted</i> down.")
		if(SPACEPOD_BULKHEAD_SECURED)
			. += span_notice("The bulkhead is <b>bolted</b> on but not <i>welded</i> on.")
		if(SPACEPOD_BULKHEAD_WELDED)
			. += span_notice("The bulkhead is <b>welded</b> on and <i>armor</i> can be attached.")
		if(SPACEPOD_ARMOR_LOOSE)
			. += span_notice("The armor is <b>loosely attached</b> and can be <i>bolted</i> down.")
		if(SPACEPOD_ARMOR_SECURED)
			. += span_notice("The armor is <b>bolted</b> on but not <i>welded</i> on.")
		if(SPACEPOD_ARMOR_WELDED)
			if(hatch_open)
				if(cell || internal_tank || length(equipment))
					. += span_notice("The maintenance hatch is <i>pried</i> open and there are parts inside that can be <b>removed</b>.")
				else
					. += span_notice("The maintenance hatch is <i>pried</i> open and the armor is <b>welded</b> on.")
			else
				if(locked)
					. += span_notice("[src] is <b>locked</b>.")
				else
					. += span_notice("The maintenance hatch is <b>closed</b>.")

/obj/spacepod/proc/handle_spacepod_construction(obj/item/weapon, mob/living/user)
	// time for a construction/deconstruction process to rival r-walls
	var/obj/item/stack/used_stack = weapon
	switch(construction_state)
		if(SPACEPOD_EMPTY)
			if(weapon.tool_behaviour == TOOL_WIRECUTTER)
				. = TRUE
				user.visible_message(span_notice("[user] deconstructs [src]."), span_notice("You deconstruct [src]."))
				weapon.play_tool_sound(src)
				deconstruct(TRUE)
				return // deconstruct() qdels us; bail before touching update_icon().
			else if(istype(weapon, /obj/item/stack/cable_coil))
				. = TRUE
				if(used_stack.use(10))
					user.visible_message(span_notice("[user] wires [src]."), span_notice("You wire [src]."))
					construction_state++
				else
					to_chat(user, span_warning("You need 10 wires for this!"))
		if(SPACEPOD_WIRES_LOOSE)
			if(weapon.tool_behaviour == TOOL_WIRECUTTER)
				. = TRUE
				var/obj/item/stack/cable_coil/coil = new
				coil.amount = 10
				coil.forceMove(loc)
				weapon.play_tool_sound(src)
				construction_state--
				user.visible_message(span_notice("[user] cuts [src]'s wiring."), span_notice("You remove [src]'s wiring."))
			else if(weapon.tool_behaviour == TOOL_SCREWDRIVER)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state++
				user.visible_message(span_notice("[user] screws on [src]'s wiring harnesses."), span_notice("You screw on [src]'s wiring harnesses."))
		if(SPACEPOD_WIRES_SECURED)
			if(weapon.tool_behaviour == TOOL_SCREWDRIVER)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state--
				user.visible_message(span_notice("[user] unclips [src]'s wiring harnesses."), span_notice("You unclip [src]'s wiring harnesses."))
			else if(istype(weapon, /obj/item/circuitboard/mecha/pod))
				. = TRUE
				if(user.temporarilyRemoveItemFromInventory(weapon))
					qdel(weapon)
					construction_state++
					user.visible_message(span_notice("[user] inserts the mainboard into [src]."), span_notice("You insert the mainboard into [src]."))
				else
					to_chat(user, span_warning("[weapon] is stuck to your hand!"))
		if(SPACEPOD_CIRCUIT_LOOSE)
			if(weapon.tool_behaviour == TOOL_CROWBAR)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state--
				var/obj/item/circuitboard/mecha/pod/board = new
				board.forceMove(loc)
				user.visible_message(span_notice("[user] pries out the mainboard from [src]."), span_notice("You pry out the mainboard from [src]."))
			else if(weapon.tool_behaviour == TOOL_SCREWDRIVER)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state++
				user.visible_message(span_notice("[user] secures the mainboard to [src]."), span_notice("You secure the mainboard to [src]."))
		if(SPACEPOD_CIRCUIT_SECURED)
			if(weapon.tool_behaviour == TOOL_SCREWDRIVER)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state--
				user.visible_message(span_notice("[user] unsecures the mainboard."), span_notice("You unscrew the mainboard from [src]."))
			else if(istype(weapon, /obj/item/pod_parts/core))
				. = TRUE
				if(user.temporarilyRemoveItemFromInventory(weapon))
					qdel(weapon)
					construction_state++
					user.visible_message(span_notice("[user] inserts the core into [src]."), span_notice("You carefully insert the core into [src]."))
				else
					to_chat(user, span_warning("[weapon] is stuck to your hand!"))
		if(SPACEPOD_CORE_LOOSE)
			if(weapon.tool_behaviour == TOOL_CROWBAR)
				. = TRUE
				weapon.play_tool_sound(src)
				var/obj/item/pod_parts/core/core = new
				core.forceMove(loc)
				construction_state--
				user.visible_message(span_notice("[user] delicately removes the core from [src]."), span_notice("You delicately remove the core from [src]."))
			else if(weapon.tool_behaviour == TOOL_WRENCH)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state++
				user.visible_message(span_notice("[user] secures [src]'s core bolts."), span_notice("You secure [src]'s core bolts."))
		if(SPACEPOD_CORE_SECURED)
			if(weapon.tool_behaviour == TOOL_WRENCH)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state--
				user.visible_message(span_notice("[user] unsecures [src]'s core."), span_notice("You unsecure [src]'s core."))
			else if(istype(weapon, /obj/item/stack/sheet/iron))
				. = TRUE
				if(used_stack.use(5))
					user.visible_message(span_notice("[user] fabricates a pressure bulkhead for [src]."), span_notice("You fabricate a pressure bulkhead for [src]."))
					construction_state++
				else
					to_chat(user, span_warning("You need 5 iron for this!"))
		if(SPACEPOD_BULKHEAD_LOOSE)
			if(weapon.tool_behaviour == TOOL_CROWBAR)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state--
				var/obj/item/stack/sheet/iron/five/sheets = new
				sheets.forceMove(loc)
				user.visible_message(span_notice("[user] pops [src]'s bulkhead panelling loose."), span_notice("You pop [src]'s bulkhead panelling loose."))
			else if(weapon.tool_behaviour == TOOL_WRENCH)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state++
				user.visible_message(span_notice("[user] secures [src]'s bulkhead panelling."), span_notice("You secure [src]'s bulkhead panelling."))
		if(SPACEPOD_BULKHEAD_SECURED)
			if(weapon.tool_behaviour == TOOL_WRENCH)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state--
				user.visible_message(span_notice("[user] unbolts [src]'s bulkhead panelling."), span_notice("You unbolt [src]'s bulkhead panelling."))
			else if(weapon.tool_behaviour == TOOL_WELDER)
				. = TRUE
				if(weapon.use_tool(src, user, 20, amount = 3, volume = 50))
					construction_state = SPACEPOD_BULKHEAD_WELDED
					user.visible_message(span_notice("[user] seals [src]'s bulkhead panelling."), span_notice("You seal [src]'s bulkhead panelling."))
		if(SPACEPOD_BULKHEAD_WELDED)
			if(weapon.tool_behaviour == TOOL_WELDER)
				. = TRUE
				if(weapon.use_tool(src, user, 20, amount = 3, volume = 50))
					construction_state = SPACEPOD_BULKHEAD_SECURED
					user.visible_message(span_notice("[user] cuts [src]'s bulkhead panelling loose."), span_notice("You cut [src]'s bulkhead panelling loose."))
			if(istype(weapon, /obj/item/pod_parts/armor))
				. = TRUE
				if(user.transferItemToLoc(weapon, src))
					add_armor(weapon)
					construction_state++
					user.visible_message(span_notice("[user] installs [src]'s armor plating."), span_notice("You install [src]'s armor plating."))
				else
					to_chat(user, span_warning("[weapon] is stuck to your hand!"))
		if(SPACEPOD_ARMOR_LOOSE)
			if(weapon.tool_behaviour == TOOL_CROWBAR)
				. = TRUE
				if(pod_armor)
					pod_armor.forceMove(loc)
					remove_armor()
				weapon.play_tool_sound(src)
				construction_state--
				user.visible_message(span_notice("[user] pries off [src]'s armor."), span_notice("You pry off [src]'s armor."))
			if(weapon.tool_behaviour == TOOL_WRENCH)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state++
				user.visible_message(span_notice("[user] bolts down [src]'s armor."), span_notice("You bolt down [src]'s armor."))
		if(SPACEPOD_ARMOR_SECURED)
			if(weapon.tool_behaviour == TOOL_WRENCH)
				. = TRUE
				weapon.play_tool_sound(src)
				construction_state--
				user.visible_message(span_notice("[user] unsecures [src]'s armor."), span_notice("You unsecure [src]'s armor."))
			else if(weapon.tool_behaviour == TOOL_WELDER)
				. = TRUE
				if(weapon.use_tool(src, user, 50, amount = 3, volume = 50))
					construction_state = SPACEPOD_ARMOR_WELDED
					user.visible_message(span_notice("[user] welds [src]'s armor."), span_notice("You weld [src]'s armor."))
	update_icon()
