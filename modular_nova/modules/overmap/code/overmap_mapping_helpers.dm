// MODULE ID: OVERMAP
// Mapload helpers: helm faction pins and landing-zone beacon↔controller links.
// Vars live on the helper, not the machines. Late-init so helm bind and APCs exist.

GLOBAL_LIST_EMPTY(overmap_lz_link_helpers)

/obj/effect/mapping_helpers/helm
	late = TRUE

/obj/effect/mapping_helpers/helm/affiliation
	name = "helm affiliation helper"
	icon_state = "airalarm_syndicate_access_helper"
	/// `OVERMAP_AFFILIATION_*` applied to the bound simulated ship.
	var/affiliation

/obj/effect/mapping_helpers/helm/affiliation/nt
	name = "helm NT affiliation helper"
	affiliation = OVERMAP_AFFILIATION_NT

/obj/effect/mapping_helpers/helm/affiliation/ds2
	name = "helm DS2 affiliation helper"
	affiliation = OVERMAP_AFFILIATION_DS2

/obj/effect/mapping_helpers/helm/affiliation/Initialize(mapload, atom/movable/explicit_target, list/mapped_vars)
	. = ..()
	if(!mapload && !shipyard_target)
		log_mapping("[src] spawned outside of mapload!")
		return INITIALIZE_HINT_QDEL

/obj/effect/mapping_helpers/helm/affiliation/LateInitialize()
	var/obj/machinery/computer/helm/helm = shipyard_target
	if(!istype(helm))
		helm = locate(/obj/machinery/computer/helm) in loc
	if(isnull(helm) || helm.viewer)
		log_mapping("[src] failed to find an astrogation helm at [AREACOORD(src)].")
		qdel(src)
		return
	if(!helm.current_ship)
		helm.set_ship()
	if(!istype(helm.current_ship, /obj/structure/overmap/ship/simulated))
		SSovermap.pending_helm_affiliations[helm] = affiliation
		qdel(src)
		return
	if(!SSovermap.apply_ship_affiliation(helm.current_ship, affiliation))
		log_mapping("[src] could not apply affiliation [affiliation] at [AREACOORD(src)].")
	qdel(src)

/obj/effect/mapping_helpers/landing_zone
	late = TRUE

/obj/effect/mapping_helpers/landing_zone/affiliation
	name = "landing zone affiliation helper"
	icon_state = "airalarm_syndicate_access_helper"
	/// `OVERMAP_AFFILIATION_*` stamped onto the controller and its managed landmark.
	var/affiliation

/obj/effect/mapping_helpers/landing_zone/affiliation/nt
	name = "landing zone NT affiliation helper"
	affiliation = OVERMAP_AFFILIATION_NT

/obj/effect/mapping_helpers/landing_zone/affiliation/ds2
	name = "landing zone DS2 affiliation helper"
	affiliation = OVERMAP_AFFILIATION_DS2

/obj/effect/mapping_helpers/landing_zone/affiliation/Initialize(mapload, atom/movable/explicit_target, list/mapped_vars)
	. = ..()
	if(!mapload && !shipyard_target)
		log_mapping("[src] spawned outside of mapload!")
		return INITIALIZE_HINT_QDEL

/obj/effect/mapping_helpers/landing_zone/affiliation/LateInitialize()
	var/obj/machinery/computer/landing_controller/console = shipyard_target
	if(!istype(console))
		console = locate(/obj/machinery/computer/landing_controller) in loc
	if(isnull(console))
		log_mapping("[src] failed to find a landing zone controller at [AREACOORD(src)].")
		qdel(src)
		return
	console.set_dock_affiliation(affiliation)
	qdel(src)

/obj/effect/mapping_helpers/landing_zone/link
	name = "landing zone link helper"
	icon_state = "airalarm_link_helper"
	/// Shared id across the controller helper and the four corner helpers.
	var/link_id

/obj/effect/mapping_helpers/landing_zone/link/Initialize(mapload, atom/movable/explicit_target, list/mapped_vars)
	. = ..()
	if(!link_id)
		if(mapload)
			log_mapping("[src] at [AREACOORD(src)] is missing link_id.")
		return INITIALIZE_HINT_QDEL
	if(!mapload && !shipyard_target)
		log_mapping("[src] spawned outside of mapload!")
		return INITIALIZE_HINT_QDEL
	var/list/group = GLOB.overmap_lz_link_helpers[link_id]
	if(!islist(group))
		group = list()
		GLOB.overmap_lz_link_helpers[link_id] = group
	group += src

/obj/effect/mapping_helpers/landing_zone/link/LateInitialize()
	if(!(link_id in GLOB.overmap_lz_link_helpers))
		qdel(src)
		return
	if(!mapped_landing_zone_link_ready(link_id))
		return
	resolve_mapped_landing_zone_link(link_id)

/// TRUE when a `link_id` group has one controller and four distinct corners.
/proc/mapped_landing_zone_link_ready(link_id)
	var/list/collected = collect_mapped_landing_zone_link(link_id)
	return !isnull(collected["console"]) && length(collected["corners"]) == 4

/proc/collect_mapped_landing_zone_link(link_id)
	var/list/group = GLOB.overmap_lz_link_helpers[link_id]
	var/obj/machinery/computer/landing_controller/console
	var/list/obj/machinery/landing_corner/found_corners = list()
	for(var/obj/effect/mapping_helpers/landing_zone/link/helper as anything in group)
		if(QDELETED(helper))
			continue
		var/turf/helper_turf = get_turf(helper)
		if(isnull(helper_turf))
			continue
		var/obj/machinery/computer/landing_controller/found_console = locate() in helper_turf
		if(found_console)
			if(!isnull(console) && console != found_console)
				log_mapping("Landing zone link [link_id] found multiple controllers.")
			console = found_console
		var/obj/machinery/landing_corner/found_corner = locate() in helper_turf
		if(found_corner && !(found_corner in found_corners))
			found_corners += found_corner
	return list("console" = console, "corners" = found_corners, "group" = group)

/// Links the controller to its four corners once a `link_id` group is complete.
/proc/resolve_mapped_landing_zone_link(link_id)
	var/list/collected = collect_mapped_landing_zone_link(link_id)
	var/list/group = collected["group"]
	GLOB.overmap_lz_link_helpers -= link_id
	if(!length(group))
		return
	var/obj/machinery/computer/landing_controller/console = collected["console"]
	var/list/obj/machinery/landing_corner/found_corners = collected["corners"]
	if(isnull(console))
		log_mapping("Landing zone link [link_id] found no landing zone controller.")
	else if(length(found_corners) != 4)
		log_mapping("Landing zone link [link_id] expected 4 corners, found [length(found_corners)].")
	else
		for(var/obj/machinery/landing_corner/corner as anything in found_corners)
			console.toggle_corner(corner)
	QDEL_LIST(group)
