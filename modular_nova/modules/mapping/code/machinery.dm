//For ruin-specific machines --- limitied/unique functions, or functions mimicked from normal machines.
//Think along the lines of a console with lore or a fuse box that needs x fuses to activate --- or, just a retextured GPS Computer, like the first item

/* ----------------- Computers ----------------- */
/obj/item/gps/computer/space //Subtype that runs pod computer code, with a texture to blend better with normal walls
	icon = 'modular_nova/modules/mapping/icons/machinery/gps_computer.dmi'	//needs its own file for pixel size ;-;
	name = "gps computer"
	icon_state = "pod_computer"
	anchored = TRUE
	density = TRUE
	pixel_y = -5    //I dunno why this sprite lines up differently, but this is a better value to line this one up in a way that looks built into a wall
	gpstag = SPACE_SIGNAL_GPSTAG	//really the only non-aesthetic change, gives the space ruin GPS signal

/obj/item/gps/computer/space/wrench_act(mob/living/user, obj/item/I)
	. = ..()
	if(I.use_tool(src, user, 20, volume=50))
		user.visible_message(span_warning("[user] disassembles [src]."),
			span_notice("You start to disassemble [src]..."), span_hear("You hear clanking and banging noises."))
		deconstruct(TRUE)
	return TRUE

/obj/item/gps/computer/space/atom_deconstruct(disassembled)
	. = ..()
	new /obj/item/gps/spaceruin(loc)	//really the only non-aesthetic change, gives the space ruin GPS signal

/obj/item/gps/computer/attack_hand(mob/user, list/modifiers)
	. = ..()
	if(.)
		return
	attack_self(user)

/**
 * Power related machines
 */

/// Primarily a replacement for Bluespace SMES/RTG spam into be something more realistic
/obj/machinery/power/micro_reactor
	icon = 'modular_nova/modules/mapping/icons/machinery/reactor.dmi'
	name = "micro reactor"
	desc = "Designed as a self-containing power source for long-haul vessels, the stamp of <font color='#008080'><b>SOAR Industries</b></font> \
		on the top. A steady output once active with plenty of safety features to ensure a meltdown is not possible, \
		having one installed means a steady clean powersource for between 75-125 years."
	icon_state = "reactor0_0"
	base_icon_state = "reactor0"
	density = TRUE
	anchored = TRUE

	var/power_gen = 200 KILO WATTS
	var/active = FALSE
	var/power_output = 1

	interaction_flags_atom = INTERACT_ATOM_ATTACK_HAND

	light_color = LIGHT_COLOR_ELECTRIC_CYAN
	light_on = FALSE

	var/datum/looping_sound/generator/soundloop

/obj/machinery/power/micro_reactor/Initialize(mapload)
	. = ..()
	soundloop = new(src, active)
	connect_to_network()
	AddElement(/datum/element/tool_blocker, TOOL_SCREWDRIVER)
	AddElement(/datum/element/tool_blocker, TOOL_CROWBAR)

/obj/machinery/power/micro_reactor/Destroy()
	QDEL_NULL(soundloop)
	return ..()

/obj/machinery/power/micro_reactor/update_icon_state()
	icon_state = "[base_icon_state]_[active]"
	return ..()

/obj/machinery/power/micro_reactor/attack_hand(mob/user, list/modifiers)
	. = ..()
	TogglePower()

/obj/machinery/power/micro_reactor/attack_robot(mob/user)
	. = ..()
	TogglePower()

/obj/machinery/power/micro_reactor/proc/handleInactive()
	return

/obj/machinery/power/micro_reactor/update_appearance(updates)
	. = ..()
	if(!active)
		set_light(0)
		return
	set_light(2, 3)

/obj/machinery/power/micro_reactor/proc/TogglePower()
	if(active)
		active = FALSE
		set_light_power(0)
		set_light_on(0)
		update_appearance()
		soundloop.stop()
	else
		active = TRUE
		START_PROCESSING(SSmachines, src)
		set_light_power(3)
		set_light_range(2)
		set_light_on(TRUE)
		update_appearance()
		soundloop.start()

/obj/machinery/power/micro_reactor/process()
	if(active)
		if(!anchored)
			TogglePower()
			return
		if(powernet)
			add_avail(power_to_energy(power_gen * power_output))
	else
		handleInactive()

/obj/machinery/power/micro_reactor/examine(mob/user)
	. = ..()
	if(in_range(user, src) || isobserver(user))
		. += "It is[!active?"n't":""] running."

/obj/machinery/power/micro_reactor/bapgm
	name = "B.A.P.G.M."
	desc = "The Basic Automated Power Generation Machine also known as B.A.P.G.M is a reactor designed as a self-containing \
		power source for long-haul vessels however it was built to be auxillary power generation to assure essential systems \
		are online, the stamp of <font color='#008080'><b>SOAR Industries</b></font> \
		on the top. A steady output once active with plenty of safety features to ensure a meltdown is not possible, \
		having one installed means a steady clean powersource for between 75-125 years."
	icon_state = "bapgm_0"
	base_icon_state = "bapgm"
	density = FALSE

	power_gen = 100 KILO WATTS

	interaction_flags_atom = INTERACT_ATOM_ATTACK_HAND

	light_color = LIGHT_COLOR_ELECTRIC_CYAN

/**
 * Micro reactor activation helper
 *
 * Drop on a reactor's tile and it comes up running. Reactors map in cold, which is correct for a
 * derelict and wrong for anywhere the lights are meant to have been on since before the crew
 * arrived; without this the only way to get one is a parallel `/active` subtype of every reactor
 * variant, kept in step by hand.
 *
 * Applies to any `micro_reactor`, so the B.A.P.G.M. is covered by the same helper.
 *
 * Late because TogglePower() reaches for the soundloop the reactor builds in its own Initialize,
 * and two atoms sharing a tile are initialised in whatever order the loader hands them over in.
 */
/obj/effect/mapping_helpers/micro_reactor_on
	name = "micro reactor activation helper"
	// Borrowed. There is no generator-flavoured helper sprite, and this one at least reads as
	// power that is present rather than power that is wanted.
	icon_state = "apc_full_charge_helper"
	late = TRUE

/obj/effect/mapping_helpers/micro_reactor_on/Initialize(mapload, atom/movable/explicit_target, list/mapped_vars)
	. = ..()
	if(!mapload && !shipyard_target)
		log_mapping("[src] spawned outside of mapload!")
		return INITIALIZE_HINT_QDEL

/obj/effect/mapping_helpers/micro_reactor_on/LateInitialize()
	var/obj/machinery/power/micro_reactor/reactor = shipyard_target
	if(!istype(reactor))
		reactor = locate(/obj/machinery/power/micro_reactor) in loc
	if(isnull(reactor))
		log_mapping("[src] failed to find a micro reactor at [AREACOORD(src)].")
		qdel(src)
		return

	if(!reactor.active)
		reactor.TogglePower()
	qdel(src)
