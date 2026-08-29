/datum/map_template/automap_template
	name = "Automap Template"
	should_place_on_top = FALSE
	keep_cached_map = FALSE

	/// Our load turf
	var/turf/load_turf
	/// The map for which we load on
	var/required_map
	/// Touches builtin map. Clears the area manually instead of blacklisting
	var/affects_builtin_map
	/// Higher values load later. Used so 1x1 overlays can stamp onto arrivals.
	var/load_priority = 0

/datum/map_template/automap_template/New(path, rename, incoming_required_map, incoming_load_turf)
	. = ..(path, rename, cache = TRUE)

	if(!incoming_required_map || !incoming_load_turf)
		return

	required_map = incoming_required_map
	load_turf = incoming_load_turf
	affects_builtin_map = incoming_required_map == AUTOMAPPER_MAP_BUILTIN

/proc/cmp_automap_template_priority(datum/map_template/automap_template/left, datum/map_template/automap_template/right)
	return left.load_priority - right.load_priority
