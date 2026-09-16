// MODULE ID: BLASTWAVE_BLUESPACE
// Building an interdiction array of your own. The machine itself lives in teleport_jammer.dm.

/**
 * Interdiction array board
 *
 * Telecomms internals with a bluespace tap bolted on, which is what the salvaged arrays turn out to
 * be once you get the hatch off them. The capacitor is the interesting slot: it alone decides how
 * far the finished array reaches, so the tier-four units recovered from derelicts stay worth hauling
 * home long after the tech itself is understood.
 */
/obj/item/circuitboard/machine/teleport_jammer
	name = "Bluespace Interdiction Array"
	greyscale_colors = CIRCUIT_COLOR_ENGINEERING
	build_path = /obj/machinery/teleport_jammer
	req_components = list(
		/datum/stock_part/capacitor = 1, // tier sets coverage: 20/40/100 tiles, then the whole level
		/datum/stock_part/filter = 2,
		/datum/stock_part/amplifier = 1,
		/datum/stock_part/treatment = 1,
		/obj/item/stack/ore/bluespace_crystal = 2,
		/obj/item/stack/cable_coil = 5,
	)
	// Mapped arrays black out their whole level, and did so before they had parts to account for.
	// Defaulting the capacitor to tier four is what keeps the derelicts behaving as they always have.
	def_components = list(/datum/stock_part/capacitor = /datum/stock_part/capacitor/tier4)

/datum/design/board/teleport_jammer
	name = "Bluespace Interdiction Array Board"
	desc = "The circuit board for a bluespace interdiction array."
	id = "teleport_jammer"
	build_path = /obj/item/circuitboard/machine/teleport_jammer
	category = list(
		RND_CATEGORY_MACHINE + RND_SUBCATEGORY_MACHINE_ENGINEERING
	)
	departmental_flags = DEPARTMENT_BITFLAG_ENGINEERING | DEPARTMENT_BITFLAG_SCIENCE

/**
 * Hidden until somebody brings one home
 *
 * Denying an entire sector its bluespace shell is not a thing anyone publishes a paper on, so the
 * node cannot be reached down the tree at all. Deconstructing a recovered board reveals it, which
 * means the only route in is salvage: find a derelict array, get it off its mounts, and take the
 * board apart. Revealing is not researching, so the department still pays for it afterwards.
 */
/datum/techweb_node/bluespace_interdiction
	id = TECHWEB_NODE_BLUESPACE_INTERDICTION
	display_name = "Bluespace Interdiction"
	description = "Saturation of a local bluespace shell with junk harmonics, denying portal transit and beacon lock alike. \
		The underlying work is a military stay-behind technology and was never civilian-licensed."
	hidden = TRUE
	prereq_ids = list(TECHWEB_NODE_TELECOMS)
	design_ids = list(
		"teleport_jammer",
	)
	research_costs = list(TECHWEB_POINT_TYPE_GENERIC = TECHWEB_TIER_4_POINTS)
	required_items_to_unlock = list(
		/obj/item/circuitboard/machine/teleport_jammer,
	)
