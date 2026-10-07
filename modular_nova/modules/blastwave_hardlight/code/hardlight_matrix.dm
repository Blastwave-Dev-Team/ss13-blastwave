// MODULE ID: BLASTWAVE_HARDLIGHT
// The prize, and the thing you have to build in order to carry it.

/**
 * Command matrix carrier
 *
 * A command-class matrix does not fit in an intelliCard, which is the entire reason phase two has a
 * fabrication objective in it at all. The carrier is printed at the site's own lathe from the
 * site's own design, so the crew has to find and power a workshop before the last phase is even
 * possible - and the thing they print is useless until the wall in front of the core comes down.
 *
 * Not an /obj/item/aicard subtype. The matrix is an object rather than a `/mob/living/silicon/ai`,
 * so every line of aicard's transfer, wiping and ghosting machinery would be dead weight wrapped
 * around a var that holds an item.
 */
/obj/item/hardlight_carrier
	name = "command matrix carrier"
	desc = "An intelliCard scaled up until it stopped being pocketable. The receiving bay is wider \
		than the whole of a standard card and the shielding around it is absurd."
	icon = 'icons/obj/aicards.dmi'
	icon_state = "aicard"
	inhand_icon_state = "electronic"
	lefthand_file = 'icons/mob/inhands/items/devices_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/items/devices_righthand.dmi'
	// Deliberately not belt-sized. Somebody has to carry this out in their hands.
	w_class = WEIGHT_CLASS_BULKY
	item_flags = NOBLUDGEON
	custom_materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2,
		/datum/material/glass = SHEET_MATERIAL_AMOUNT,
		/datum/material/gold = SMALL_MATERIAL_AMOUNT * 5,
	)
	/// What we are carrying, if anything. Set by the core on extraction.
	var/obj/item/hardlight_matrix/matrix

/obj/item/hardlight_carrier/Initialize(mapload)
	. = ..()
	// A carrier coming into existence mid-round means somebody printed one, which is the first of
	// the phase-two objectives. Mapped-in spares are props and say nothing.
	if(mapload)
		return

	var/turf/our_turf = get_turf(src)
	if(!isnull(our_turf))
		hardlight_core_on_z(our_turf.z)?.note_objective(HARDLIGHT_OBJECTIVE_CARRIER)

/obj/item/hardlight_carrier/Destroy()
	matrix = null
	return ..()

/obj/item/hardlight_carrier/Exited(atom/movable/gone, direction)
	. = ..()
	if(gone == matrix)
		matrix = null
		update_appearance()

/obj/item/hardlight_carrier/examine(mob/user)
	. = ..()
	if(isnull(matrix))
		. += span_notice("The receiving bay is empty, and the status strip is dark.")
		return
	. += span_notice("[matrix] is seated in the bay. The status strip is lit and holding.")
	. += span_notice("[EXAMINE_HINT("Alt-click")] to eject it.")

/obj/item/hardlight_carrier/click_alt(mob/user)
	if(isnull(matrix))
		return CLICK_ACTION_BLOCKING

	var/obj/item/hardlight_matrix/ejected = matrix
	ejected.forceMove(drop_location())
	user.put_in_hands(ejected)
	balloon_alert(user, "matrix ejected")
	return CLICK_ACTION_SUCCESS

/// Seats `new_matrix` in the bay. Returns FALSE if we are already carrying something.
/obj/item/hardlight_carrier/proc/accept_matrix(obj/item/hardlight_matrix/new_matrix)
	if(!isnull(matrix) || QDELETED(new_matrix))
		return FALSE

	new_matrix.forceMove(src)
	matrix = new_matrix
	update_appearance()
	playsound(src, 'sound/machines/terminal/terminal_success.ogg', 50, TRUE)
	return TRUE

/obj/item/hardlight_carrier/update_overlays()
	. = ..()
	if(isnull(matrix))
		return
	// Same two-layer treatment a loaded intelliCard gets: a lit face, plus the charge indicator.
	for(var/overlay_state in list("ai", "aicard-on"))
		. += mutable_appearance(icon, overlay_state)
		. += emissive_appearance(icon, overlay_state, src, alpha = alpha)

/**
 * Command matrix
 *
 * The thing that was walking around. Inert once it is out - there is no way to run it and nothing
 * aboard that would want to - so its only two uses are as a thing to read and a thing to sell,
 * which between them are the entire reward for the encounter.
 */
/obj/item/hardlight_matrix
	name = "command matrix"
	desc = "A slab of optical storage the size of a paving stone, cold and slightly tacky to the \
		touch. Somewhere in the lattice is a decision somebody made about a war, and everything \
		that followed from it."
	icon = 'icons/obj/devices/circuitry_n_data.dmi'
	icon_state = "std_mod"
	w_class = WEIGHT_CLASS_NORMAL
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF | ACID_PROOF | LAVA_PROOF
	light_range = 1
	light_power = 0.5
	light_color = HARDLIGHT_LIGHT_COLOUR

/datum/export/hardlight_matrix
	cost = CARGO_CRATE_VALUE * 60
	unit_name = "salvaged command matrix"
	export_types = list(/obj/item/hardlight_matrix)

/**
 * Carrier design
 *
 * Not on any station techweb. It exists on the site's own lathe and nowhere else, which is what
 * makes a room full of working fabrication hardware an objective rather than set dressing.
 */
/datum/design/hardlight_carrier
	name = "Command Matrix Carrier"
	desc = "An oversized intelliCard, rated for a command-class optical matrix."
	id = "hardlight_carrier"
	build_type = PROTOLATHE | AWAY_LATHE
	materials = list(
		/datum/material/iron = SHEET_MATERIAL_AMOUNT * 2,
		/datum/material/glass = SHEET_MATERIAL_AMOUNT,
		/datum/material/gold = SMALL_MATERIAL_AMOUNT * 5,
	)
	build_path = /obj/item/hardlight_carrier
	category = list(RND_CATEGORY_TOOLS)
	departmental_flags = DEPARTMENT_BITFLAG_SCIENCE

/**
 * Carrier node
 *
 * Hidden, and reachable only by a techweb that asks for it by name - the same arrangement Charlie
 * station's dissection node uses. A design has to live in some node to be a real design rather
 * than an orphan, but the station's research tree must never be able to walk to this one: the
 * carrier is the encounter's key item, and science printing a spare would end the round early.
 */
/datum/techweb_node/hardlight_fabrication
	id = "hardlight_fabrication"
	display_name = "Command Matrix Handling"
	description = "Federation-pattern carrier hardware for command-class optical matrices."
	prereq_ids = list(TECHWEB_NODE_AI)
	design_ids = list("hardlight_carrier")
	research_costs = list(TECHWEB_POINT_TYPE_GENERIC = TECHWEB_TIER_3_POINTS)
	hidden = TRUE
	show_on_wiki = FALSE

/*
 * Extraction
 */

/**
 * Pulling the matrix.
 *
 * Gated on the field being down rather than on the door being open, so there is no version of this
 * where a crew squeezes past the objective. Ends the boss outright: the core drops whatever body
 * it had up and goes quiet, which is also the moment everything that was waiting on it wakes.
 */
/obj/machinery/hardlight_command_core/item_interaction(mob/living/user, obj/item/tool, list/modifiers)
	if(!istype(tool, /obj/item/hardlight_carrier))
		return NONE

	var/obj/item/hardlight_carrier/carrier = tool

	if(phase == HARDLIGHT_PHASE_EXTRACTED)
		balloon_alert(user, "mounts are empty")
		return ITEM_INTERACT_BLOCKING

	if(phase != HARDLIGHT_PHASE_BREACHED)
		balloon_alert(user, "containment still up!")
		return ITEM_INTERACT_BLOCKING

	if(!isnull(carrier.matrix))
		balloon_alert(user, "carrier is full!")
		return ITEM_INTERACT_BLOCKING

	balloon_alert(user, "seating carrier...")
	if(!do_after(user, 6 SECONDS, src))
		return ITEM_INTERACT_BLOCKING

	// Re-checked after the bar: six seconds is long enough for the fight to have moved on.
	if(phase != HARDLIGHT_PHASE_BREACHED || !isnull(carrier.matrix))
		return ITEM_INTERACT_BLOCKING

	carrier.accept_matrix(new /obj/item/hardlight_matrix(carrier))
	visible_message(span_boldwarning("The lattice inside [src] goes dark rank by rank, and then all at once."))
	matrix_extracted(user)
	return ITEM_INTERACT_SUCCESS
