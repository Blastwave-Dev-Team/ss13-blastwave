// MODULE ID: OVERMAP
// Radar packet used by the station dish / processor / console path.
// Parallel to tcomms subspace signals; never enters the radio network.

/datum/signal/overmap_radar
	/// Dish that emitted this sweep.
	var/obj/machinery/overmap_radar/dish/origin_dish
	/// Overmap object the sweep was taken from (usually SSovermap.main).
	var/obj/structure/overmap/origin
	/// Compression remaining. Processor zeroes this; console garbles if > 0.
	var/compression = 0
	/// Sweep cone center, degrees (0 = north, clockwise).
	var/bearing = 0
	/// Sweep cone width in degrees.
	var/arc_width = 360
	/// Computed max range in overmap tiles for this sweep.
	var/range = OVERMAP_RADAR_WIDE_RANGE
	/// Assoc contact lists: ref, name, type, x, y, bearing, distance, affiliation.
	var/list/contacts = list()
	/// Console that requested this sweep. Null broadcasts to every linked console.
	var/obj/machinery/computer/overmap_radar/dest_console

/datum/signal/overmap_radar/New(obj/machinery/overmap_radar/dish/dish, obj/structure/overmap/sweep_origin)
	origin_dish = dish
	origin = sweep_origin
	source = dish

/// Tile range for a given cone width. Narrower arc → longer reach.
/proc/overmap_radar_range_for_arc(arc_width)
	var/width = clamp(arc_width, OVERMAP_RADAR_MIN_ARC, 360)
	var/t = (width - OVERMAP_RADAR_MIN_ARC) / (360 - OVERMAP_RADAR_MIN_ARC)
	return round(OVERMAP_RADAR_NARROW_RANGE + (OVERMAP_RADAR_WIDE_RANGE - OVERMAP_RADAR_NARROW_RANGE) * t)

/// Apply display-time garble to a contact list. Does not mutate the packet.
/proc/overmap_radar_garble_contacts(list/contacts, compression)
	var/list/result = list()
	for(var/list/contact as anything in contacts)
		var/list/entry = contact.Copy()
		if(compression > 0)
			entry["name"] = Gibberish(entry["name"], compression >= 30)
			entry["x"] += rand(-2, 2)
			entry["y"] += rand(-2, 2)
			if(prob(compression))
				entry["type"] = pick("ship", "level", "dynamic", "event", "unknown")
				entry["type_label"] = "Unknown"
			if(prob(compression))
				entry["affiliation"] = Gibberish("[entry["affiliation"]]", TRUE)
		result += list(entry)
	return result

/// Gather overmap objects visible from `origin` inside range and optional cone.
/obj/structure/overmap/proc/gather_radar_contacts(range_tiles, bearing = 0, arc_width = 360)
	var/list/found = list()
	if(QDELETED(src) || range_tiles <= 0)
		return found
	var/scan_px = range_tiles * ICON_SIZE_ALL
	var/scan_sq = scan_px * scan_px
	var/my_px = get_overmap_abs_px()
	var/my_py = get_overmap_abs_py()
	var/full_sweep = arc_width >= 360
	for(var/obj/structure/overmap/other as anything in SSovermap.overmap_objects)
		if(other == src || QDELETED(other))
			continue
		if(other.z != z)
			continue
		var/dx = other.get_overmap_abs_px() - my_px
		var/dy = other.get_overmap_abs_py() - my_py
		if(dx * dx + dy * dy > scan_sq)
			continue
		if(!SSovermap.can_view_installation(src, other))
			continue
		if(!full_sweep)
			var/contact_bearing = overmap_nav_bearing(dx, dy)
			if(abs(closer_angle_difference(contact_bearing, bearing)) > (arc_width / 2))
				continue
		found += other
	return found

/// Build a contact assoc from an overmap object relative to `origin`.
/proc/overmap_radar_contact_data(obj/structure/overmap/origin, obj/structure/overmap/other)
	var/atom/position = istype(other.loc, /obj/structure/overmap) ? other.loc : other
	return list(
		"ref" = REF(other),
		"name" = other.name,
		"type" = other.contact_type,
		"type_label" = other.contact_label,
		"x" = position.x,
		"y" = position.y,
		"bearing" = get_bearing_to(origin, position),
		"distance" = get_dist(origin, position),
		"affiliation" = SSovermap.get_affiliation(other),
	)
