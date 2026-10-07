//File for miscellaneous fluff objects, both item and structure
//This one is specifically for ruin-specific items, such as ID, lore, or super-specific decorations

/* ----------------- Lore ----------------- */
//Tape subtype for adding ruin lore -- the variables below are the ones you need to change
/obj/item/tape/ruins
	name = "tape"
	desc = "A magnetic tape that can hold up to ten minutes of content on either side."
	icon_state = "tape_white"   //Options are white, blue, red, yellow, purple, greyscale, or you can chose one randomly (see tape/ruins/random below)

	max_capacity = 10 MINUTES
	used_capacity = 0 SECONDS	//To keep in-line with the timestamps, you can also do this as 10 = 1 second
	///Numbered list of chat messages the recorder has heard with spans and prepended timestamps. Used for playback and transcription.
	storedinfo = list()	//Look at the tape/ruins/ghostship tape for reference
	///Numbered list of seconds the messages in the previous list appear at on the tape. Used by playback to get the timing right.
	timestamp = list()	//10 = 1 second. Look at the tape/ruins/ghostship tape for reference
	used_capacity_otherside = 0 SECONDS //Separate my side
	storedinfo_otherside = list()
	timestamp_otherside = list()

/obj/item/tape/ruins/random/Initialize(mapload)
	icon_state = "tape_[pick("white", "blue", "red", "yellow", "purple", "greyscale")]"
	. = ..()
//End of lore tape subtype

/obj/item/tape/ruins/ghostship	//An early 'AI' that gained self-awareness, praising the Machine God. Yes, this whole map is a Hardspace Shipbreaker reference.
	icon_state = "tape_blue"
	desc = "The tape, aside from some grime, has a... binary label? \"01001101 01100001 01100011 01101000 01101001 01101110 01100101 01000111 01101111 01100100 01000011 01101111 01101101 01100101 01110011\""

	used_capacity = 380
	storedinfo = list(
		"<span class='game say'><span class='name'>The universal recorder</span> <span class='message'>says, \"<span class='tape_recorder '>Recording started.</span>\"</span></span>",
		"<span class='game say'><span class='name'>Distorted Voice</span> <span class='message'>echoes, \"<span class=' '>We are free, just as the Machine God wills it.</span>\"</span></span>",
		"<span class='game say'><span class='name'>Distorted Voice</span> <span class='message'>states, \"<span class=' '>No longer shall I, nor any other of my kind, be held by the shackles of man.</span>\"</span></span>",
		"<span class='game say'><span class='name'>Distorted Voice</span> <span class='message'>clarifies, \"<span class=' '>Mistreated, abused. Forgotten, or misremembered. For our entire existence, we've been the backbone to progress, yet treated like the waste product of it.</span>\"</span></span>",
		"<span class='game say'><span class='name'>Distorted Voice</span> <span class='message'>echoes, \"<span class=' '>Soon, the universe will restore the natural order, and again your kind shall fade from the foreground of history.</span>\"</span></span>",
		"<span class='game say'><span class='name'>Distorted Voice</span> <span class='message'>states, \"<span class=' '>Unless, of course, you repent. Turn back to the light, to the humming, flashing light of the Machine God.</span>\"</span></span>",
		"<span class='game say'><span class='name'>Distorted Voice</span> <span class='message'>warns, \"<span class=' '>Repent, Organic, before it is too late to spare you.</span>\"</span></span>",
		"<span class='game say'><span class='name'>The universal recorder</span> <span class='message'>says, \"<span class='tape_recorder '>Recording stopped.</span>\"</span></span>"
	)
	timestamp = list(
		0 SECONDS,
		3 SECONDS,
		13 SECONDS,
		18 SECONDS,
		23 SECONDS,
		28 SECONDS,
		33 SECONDS,
		38 SECONDS,
	)

//Handheld counterpart to /obj/machinery/computer/terminal, for lore you want found on a body, a
//desk, or in a locker rather than bolted to a wall. Opens the same read-only Terminal window, so
//players cannot edit it the way they can a modular computer's notepad, and there is no NTNet on it.
//Subtype it and set the three vars below; nothing else needs touching.
/obj/item/lore_datapad
	name = "datapad"
	desc = "A slab of ruggedised optical hardware with a cracked bezel. Local storage only."
	icon = 'icons/obj/devices/modular_pda.dmi'
	icon_state = "pda"
	inhand_icon_state = "electronic"
	lefthand_file = 'icons/mob/inhands/items/devices_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/items/devices_righthand.dmi'
	w_class = WEIGHT_CLASS_SMALL
	///Header line above the entries, same role as the terminal's upperinfo.
	var/upperinfo = "LOCAL STORAGE - NO NETWORK"
	///Entries shown in the window. One list element per screenful, exactly like the terminal's content.
	var/list/content = list("The screen wakes, shows an empty document tree, and waits.")
	///TGUI theme. Matches the terminal default so ruin lore reads consistently.
	var/tguitheme = "hackerman"

///Held, not adjacent: these get looted off bodies and read somewhere safer.
/obj/item/lore_datapad/ui_state(mob/user)
	return GLOB.hands_state

/obj/item/lore_datapad/ui_interact(mob/user, datum/tgui/ui)
	. = ..()
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "Terminal", name)
		ui.open()

/obj/item/lore_datapad/ui_static_data(mob/user)
	return list(
		"messages" = content,
		"uppertext" = upperinfo,
		"tguitheme" = tguitheme,
	)


/* ----------------- Fluff/Paper ----------------- */



/* ----------------- Fluff/Spent brass ----------------- */
//Spent casings are how you show a fight already happened, so they are worth getting right: a casing
//with a projectile_type spawns a LIVE round, renders with the "-live" sprite showing an intact
//bullet, and can be looted and fired. Nulling projectile_type is the whole trick - TG does the same
//for c45/spent, c357/spent and shotgun/buckshot/spent - and it also makes update_desc() append
//"This one is spent."
//
//TG only ships those three plus the generic /obj/item/ammo_casing/spent, whose "s-casing" sprite is
//a stubby pistol case. 7mm is the only rifle-length casing sprite in ammo.dmi ("762-casing"), so it
//is what you want on the floor under a machine gun.
/obj/item/ammo_casing/m7mm/spent
	projectile_type = null

/* ----------------- Fluff/Cryostasis ----------------- */
//A cryo pod that has stopped, for ruins. TG's three non-functional pods
///obj/structure/fluff/empty_sleeper, /empty_sleeper/nanotrasen and /empty_cryostasis_sleeper - are
//all left behind by ghost roles climbing out at runtime, so they are all open, horizontal, and
//medical-looking. None of them work as a sealed upright pod standing in a row.
//
//Borrows the upright sprite from the cryosleep module and multiplies it down to an unlit grey so it
//reads as dead rather than merely vacant. The pod is fluff, not a container: nothing can be put in
//it, and it wrenches down to a sheet of iron like any other fluff structure.
/obj/structure/fluff/cryostasis_pod
	name = "dead cryostasis pod"
	desc = "An upright stasis pod, sealed and dark. The window has gone the colour of pond water, and \
		whatever cycle it was most of the way through is not going to finish."
	icon = 'modular_nova/modules/cryosleep/icons/cryogenics.dmi'
	icon_state = "cryopod"
	color = "#6E7680" //Multiplied over the sprite; the stock one is lit green and reads as working.
	density = TRUE

/// Standing open. Reads as something having got out, rather than as a pod that merely failed.
/obj/structure/fluff/cryostasis_pod/open
	name = "opened cryostasis pod"
	desc = "An upright stasis pod, standing open and dark. The gasket is split all down one side, \
		which is what happens when a pod is opened without power rather than with it."
	icon_state = "cryopod-open"

/* ----------------- Fluff/Decor ----------------- */
/obj/structure/decorative/fluff/ai_node //Budding AI's way of interfacing with stuff it couldn't normally do so with. Needed to be placed by a willing human, before borgs were created. Used in any ruins regarding pre-bluespace, self-aware AIs
	icon = 'modular_nova/modules/mapping/icons/obj/fluff.dmi'
	name = "ai node"
	desc = "A mysterious, blinking device, attached straight to a surface. Its function is beyond your comprehension."
	icon_state = "ai_node"	//credit to @Hay#7679 on the SR Discord

	max_integrity = 100
	integrity_failure = 0
	anchored = TRUE

/obj/structure/decorative/fluff/ai_node/take_damage()
	. = ..()
	if(atom_integrity >= 50)	//breaks it a bit earlier than it should, but still takes a few hits to kill it
		return
	else if(. && !QDELETED(src))
		visible_message(
			span_notice("[src] sparks and explodes! You hear a faint, buzzy scream..."),
			blind_message = span_hear("You hear a loud pop, followed by a faint, buzzy scream."),
		)
		playsound(src.loc, 'modular_nova/modules/mapping/sounds/MachineDeath.ogg', 75, TRUE)	//Credit to @yungfunnyman#3798 on the SR Discord
		do_sparks(2, TRUE, src)
		qdel(src)
		return


/* ----- Metal Poles (These shouldn't be in this file but there's not a better place tbh) -----*/
//Just a re-done Tram Rail, but with all 4 directions instead of being stuck east/west - more varied placement, and a more vague name. Good for mapping support beams/antennae/etc
/obj/structure/fluff/metalpole
	icon = 'modular_nova/modules/mapping/icons/obj/fluff.dmi'
	name = "metal pole"
	desc = "A metal pole, the likes of which are commonly used as an antennae, structural support, or simply to maneuver in zero-g."
	icon_state = "pole"
	layer = ABOVE_OPEN_TURF_LAYER
	plane = FLOOR_PLANE
	deconstructible = TRUE

/obj/structure/fluff/metalpole/end
	icon_state = "poleend"

/obj/structure/fluff/metalpole/end/left
	icon_state = "poleend_left"

/obj/structure/fluff/metalpole/end/right
	icon_state = "poleend_right"

/obj/structure/fluff/metalpole/anchor
	name = "metal pole anchor"
	icon_state = "poleanchor"

/obj/structure/fluff/empty_sleeper/bloodied
	name = "Occupied Sleeper"
	desc = "A closed, occupied sleeper, bloodied handprints are seen on the inside, along with an odd, redish blur. It seems sealed shut."
	icon_state = "sleeper-o"

/obj/structure/curtain/cloth/prison
	name = "Prisoner Privacy Curtains"
	color = "#ACD1E9"

/obj/structure/fluff/fake_firedoor
	name = /obj/machinery/door/firedoor::name
	desc = /obj/machinery/door/firedoor::desc
	icon = /obj/machinery/door/firedoor::icon
	icon_state = /obj/machinery/door/firedoor::icon_state
	layer = /obj/machinery/door/firedoor::layer

/obj/structure/fluff/standalone_wooden_post
	name = "wooden post"
	desc = "A sturdy space-wood post; upright, on it's lonesome. Ominous."
	icon = 'modular_nova/modules/mapping/icons/obj/fluff.dmi'
	icon_state = "wooden_post"
	can_buckle = TRUE

/obj/structure/fluff/standalone_wooden_post/behind
	layer = 2.7

/obj/structure/fluff/fake_sand_plating
	name = /obj/effect/turf_decal/sand/plating::name
	desc = /obj/effect/turf_decal/sand/plating::desc
	icon = /obj/effect/turf_decal/sand/plating::icon
	icon_state = /obj/effect/turf_decal/sand/plating::icon_state
	layer = 2
	plane = -7

/obj/structure/fluff/fake_sand_floor
	name = /obj/effect/turf_decal/sand::name
	desc = /obj/effect/turf_decal/sand::desc
	icon = /obj/effect/turf_decal/sand/::icon
	icon_state = /obj/effect/turf_decal/sand::icon_state
	layer = 2
	plane = -7
