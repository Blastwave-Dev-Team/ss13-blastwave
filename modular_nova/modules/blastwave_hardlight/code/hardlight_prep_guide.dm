// MODULE ID: BLASTWAVE_HARDLIGHT
// The counter-play, published as a safety manual and delivered as paperwork.
//
// Everything mechanically important about a hard-light projector is stated plainly in a Federation
// engineering standards document that predates the war, because a safety manual has to say what
// damages the equipment and what the equipment does to nearby personnel. It never mentions the
// Sepulchure, command units, or that anybody should be preparing for anything. A crew that reads
// it turns up with disablers and an ion gun; a crew that doesn't finds out in the first room.
//
// Two delivery routes, neither of which explains itself: a routine CentCom circular naming the
// document, and a physical copy already sitting on the library shelf.
//
// The circular is a printed command report rather than a station-wide announcement. Broadcasting
// "read this engineering manual" to the whole crew over the radio would telegraph that it matters;
// a sheet of archival paperwork on the bridge that somebody has to notice, read, and pass on is
// both quieter and a better use of command. It also means the information travels the way
// information actually travels on a shift, which is the interesting version of the ARG.

/// Wiki path the guide lives at. `ugc/` specifically - the library console refuses to print
/// anything outside it without R_ADMIN, and a document nobody can print is not an ARG.
#define HARDLIGHT_GUIDE_SLUG "ugc/hard-light-projection-systems"
#define HARDLIGHT_GUIDE_TITLE "Hard-Light Projection Systems: Installation, Maintenance and Personnel Safety"

/obj/item/book/manual/wiki/hardlight_safety
	name = "Hard-Light Projection Systems"
	desc = "An archival reprint of a Solar Federation engineering standards document, bound badly \
		and at some length. Somebody has dog-eared the section on capacitor recovery."
	icon_state = "bookEngineering2"
	starting_author = "Solar Federation Bureau of Engineering Standards"
	starting_title = HARDLIGHT_GUIDE_TITLE
	page_link = HARDLIGHT_GUIDE_SLUG

/obj/structure/bookcase/manuals/hardlight_safety
	name = "archival standards bookcase"

/obj/structure/bookcase/manuals/hardlight_safety/Initialize(mapload)
	. = ..()
	new /obj/item/book/manual/wiki/hardlight_safety(src)
	update_appearance()

/// Puts the physical copy somewhere a crew that ignored the circular can still walk into it.
/datum/area_spawn/hardlight_safety_manual
	target_areas = list(/area/station/service/library, /area/station/service/library/private, /area/station/service/library/upper)
	desired_atom = /obj/structure/bookcase/manuals/hardlight_safety
	mode = AREA_SPAWN_MODE_HUG_WALL

/**
 * Roundstart circular
 *
 * Fired by the command core, so it only goes out on rounds where the site is actually in the
 * sector - but written as though it is one of a hundred archival notices CentCom pushes out and
 * nobody reads. The joke, and the whole ARG, is that it is the most useful thing said all round.
 *
 * Guarded by a static rather than by the core's own state so two sites cannot double-file it.
 */
/obj/machinery/hardlight_command_core/proc/register_prep_guide_circular()
	var/static/circular_sent = FALSE
	if(circular_sent)
		return
	circular_sent = TRUE

	if(SSticker.HasRoundStarted())
		file_prep_guide_report()
		return
	RegisterSignal(SSticker, COMSIG_TICKER_ROUND_STARTING, PROC_REF(on_round_starting))

/obj/machinery/hardlight_command_core/proc/on_round_starting(datum/source)
	SIGNAL_HANDLER
	UnregisterSignal(SSticker, COMSIG_TICKER_ROUND_STARTING)
	file_prep_guide_report()

/// Prints at the communications consoles and nowhere else. No announcement, no sound, no radio.
/obj/machinery/hardlight_command_core/proc/file_prep_guide_report()
	print_command_report(
		text = "Archival release. A Solar Federation engineering standards document has completed \
			declassification review and is now published to the crew information network.<br><br>\
			<b>[HARDLIGHT_GUIDE_TITLE]</b><br>\
			Filed at <b>[HARDLIGHT_GUIDE_SLUG]</b>.<br><br>\
			Crew whose duties may bring them into contact with legacy Federation hardware are \
			reminded that familiarity with pre-Armistice engineering standards remains a personal \
			responsibility. Physical copies may be printed at any library terminal.<br><br>\
			This notice is filed for departmental distribution at the discretion of command staff. \
			No action is required.",
		title = "Central Command Archival Notice",
		announce = FALSE,
	)

#undef HARDLIGHT_GUIDE_SLUG
#undef HARDLIGHT_GUIDE_TITLE
