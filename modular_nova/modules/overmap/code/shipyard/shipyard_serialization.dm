// MODULE ID: OVERMAP
// Type-level state capture for ship teardown. The route decides the strategy in
// shipyard_construction_routes.dm; this decides what a given type is worth
// writing down, and is the inverse of the shipyard_prepare/shipyard_commission
// pair in shipyard_phases.dm.

/**
 * Contribute this atom's state to the map cell describing it.
 *
 * The base implementation emits the mapped-variable allowlist filtered to
 * values that differ from the type's own defaults, which is what a blueprint
 * would have had to state to produce this atom. Types whose state the allowlist
 * cannot express contribute it here, either as more vars or as a mapping helper,
 * so the knowledge lives on the type rather than in a serializer registry.
 */
/atom/proc/shipyard_describe(list/described_vars, list/described_helpers)
	for(var/var_name in shipyard_mapped_var_allowlist())
		if(!(var_name in vars))
			continue
		// A smoothed atom rewrites its own appearance from its neighbours on
		// every load, so recording the result bakes one arrangement of
		// neighbours into a hull that will be rebuilt somewhere else.
		if(smoothing_flags && (var_name == "icon" || var_name == "icon_state"))
			continue
		var/value = vars[var_name]
		if(isnull(value) || !issaved(vars[var_name]))
			continue
		if(islist(value))
			var/list/list_value = value
			if(!length(list_value))
				continue
			described_vars[var_name] = list_value.Copy()
			continue
		if(value == initial(vars[var_name]))
			continue
		described_vars[var_name] = value

/**
 * Machinery reports the tier of the parts it was assembled with.
 *
 * `component_parts` is a list of objects, and TGM encodes constants only, so
 * this cannot be a var override; it rides in a mapping helper instead. Only an
 * assembly holding something better than the baseline is worth recording -
 * everything else is what a fresh build produces anyway.
 */
/obj/machinery/shipyard_describe(list/described_vars, list/described_helpers)
	. = ..()
	var/list/tiers = list()
	var/upgraded = FALSE
	for(var/datum/stock_part/part as anything in component_parts)
		if(!istype(part))
			continue
		tiers[part.type] = (tiers[part.type] || 0) + 1
		if(part.type != shipyard_stock_part_family(part.type))
			upgraded = TRUE
	if(!upgraded)
		return
	described_helpers += list(list(
		"path" = /obj/effect/mapping_helpers/machine_parts,
		"vars" = list(
			"part_tiers" = tiers,
			"target_type" = type,
		),
	))

/// The baseline tier of a stock part family, which every better tier descends
/// from. Used to tell an upgraded assembly apart from a freshly built one.
/proc/shipyard_stock_part_family(part_type)
	var/static/list/families = list()
	var/cached = families[part_type]
	if(cached)
		return cached
	var/family = part_type
	while(family && type2parent(family) != /datum/stock_part)
		family = type2parent(family)
	families[part_type] = family
	return family

// --- Machinery state carrier ------------------------------------------------

/**
 * Reinstalls the stock part tiers a saved machine was holding.
 *
 * Modelled on the apc helper: mapload finds its machine on the tile, and a
 * shipyard reprint hands one over directly. `target_type` disambiguates a tile
 * stacking two machines, which a blueprint is allowed to do.
 */
/obj/effect/mapping_helpers/machine_parts
	name = "machine parts helper"
	desc = "You shouldn't see this. Report it please."
	late = TRUE
	/// Stock part datum path to the number of them installed.
	var/list/part_tiers
	/// Machine on this tile the tiers belong to.
	var/target_type = /obj/machinery

/obj/effect/mapping_helpers/machine_parts/Initialize(mapload, atom/movable/explicit_target, list/mapped_vars)
	. = ..()
	if(shipyard_target)
		if(!ismachinery(shipyard_target))
			return INITIALIZE_HINT_QDEL
		return INITIALIZE_HINT_LATELOAD
	if(!mapload)
		log_mapping("[src] spawned outside of mapload!")
		return INITIALIZE_HINT_QDEL
	return INITIALIZE_HINT_LATELOAD

/obj/effect/mapping_helpers/machine_parts/LateInitialize()
	var/obj/machinery/target = shipyard_target || locate(target_type) in loc
	if(isnull(target) || !length(part_tiers))
		if(isnull(target))
			log_mapping("[src] failed to find [target_type] at [AREACOORD(src)].")
		qdel(src)
		return
	payload(target)
	qdel(src)

/obj/effect/mapping_helpers/machine_parts/proc/payload(obj/machinery/target)
	// Physical components - a cell, a beaker - are left alone; this only
	// restates which tier of each stock part the assembly was closed around.
	var/list/rebuilt = list()
	for(var/component in target.component_parts)
		if(!istype(component, /datum/stock_part))
			rebuilt += component
	for(var/part_path in part_tiers)
		var/datum/stock_part/part = GLOB.stock_part_datums[part_path]
		if(!part)
			log_mapping("[src] at [AREACOORD(src)] names an unknown stock part [part_path].")
			continue
		for(var/index in 1 to part_tiers[part_path])
			rebuilt += part
	target.component_parts = rebuilt
	target.RefreshParts()

// --- Partially built machinery ----------------------------------------------

/**
 * A frame reports the board it is waiting on and how far along it is.
 *
 * An unfinished frame is a ship someone is still working on rather than an
 * error, so teardown records what is actually standing. Neither the board nor
 * the construction stage survives as a var override - one is an object and the
 * other is not a mapped variable - so both ride in a helper.
 */
/obj/structure/frame/shipyard_describe(list/described_vars, list/described_helpers)
	. = ..()
	if(state == initial(state) && isnull(circuit))
		return
	described_helpers += list(list(
		"path" = /obj/effect/mapping_helpers/frame_state,
		"vars" = list(
			"board_path" = circuit?.type,
			"frame_state" = state,
			"target_type" = type,
		),
	))

/// Reinstalls the board a saved frame was built around and restores the
/// construction stage it had reached. Loose components already dropped into an
/// open frame are not preserved; the frame comes back asking for them again.
/obj/effect/mapping_helpers/frame_state
	name = "frame state helper"
	desc = "You shouldn't see this. Report it please."
	late = TRUE
	/// Circuit board installed in the frame, if any.
	var/board_path
	/// Construction stage the frame had reached.
	var/frame_state
	/// Frame on this tile the state belongs to.
	var/target_type = /obj/structure/frame

/obj/effect/mapping_helpers/frame_state/Initialize(mapload, atom/movable/explicit_target, list/mapped_vars)
	. = ..()
	if(shipyard_target)
		if(!istype(shipyard_target, /obj/structure/frame))
			return INITIALIZE_HINT_QDEL
		return INITIALIZE_HINT_LATELOAD
	if(!mapload)
		log_mapping("[src] spawned outside of mapload!")
		return INITIALIZE_HINT_QDEL
	return INITIALIZE_HINT_LATELOAD

/obj/effect/mapping_helpers/frame_state/LateInitialize()
	var/obj/structure/frame/target = shipyard_target || locate(target_type) in loc
	if(isnull(target))
		log_mapping("[src] failed to find [target_type] at [AREACOORD(src)].")
		qdel(src)
		return
	if(ispath(board_path, /obj/item/circuitboard))
		var/obj/item/circuitboard/board = new board_path(null)
		if(!target.install_board(null, board, FALSE))
			qdel(board)
	// After the board, which advances the stage itself on the way in.
	if(!isnull(frame_state))
		target.state = frame_state
	target.update_appearance()
	qdel(src)

// --- Turf decals ------------------------------------------------------------
//
// A turf decal hands its appearance to a /datum/element/decal and deletes
// itself, so a hull holds appearances rather than type paths. The way back is
// an index built from the exact tuple the effect passes to AddElement, which is
// nearly free to populate at the point the effect already computes it, and
// which captures runtime recolouring that reading type defaults cannot see.

GLOBAL_LIST_EMPTY(shipyard_decal_signatures)
GLOBAL_LIST_EMPTY(shipyard_decal_shapes)
GLOBAL_LIST_EMPTY(shipyard_decal_types_seen)
GLOBAL_VAR_INIT(shipyard_decal_index_seeded, FALSE)

/// Identity of one applied decal. Colour matrices have no stable text form and
/// are not indexed; a decal wearing one is reported as lost detail instead.
/proc/shipyard_decal_signature(decal_icon, decal_icon_state, decal_dir, decal_layer, decal_alpha, decal_color)
	if(islist(decal_color) || !decal_icon || !decal_icon_state)
		return null
	return "[decal_icon]|[decal_icon_state]|[decal_dir]|[decal_layer]|[decal_alpha]|[decal_color]"

/// The same identity without direction, so a decal a shuttle rotation has
/// turned still resolves to the path it started as.
/proc/shipyard_decal_shape(decal_icon, decal_icon_state, decal_layer, decal_alpha, decal_color)
	if(islist(decal_color) || !decal_icon || !decal_icon_state)
		return null
	return "[decal_icon]|[decal_icon_state]|[decal_layer]|[decal_alpha]|[decal_color]"

/**
 * Record the appearance a decal effect is about to apply, once per type.
 *
 * Called from the effect's own `Initialize()`, where the tuple is already in
 * hand. The per-type gate keeps mapload to one dictionary write per distinct
 * decal rather than one per instance.
 */
/proc/shipyard_note_turf_decal(obj/effect/turf_decal/decal)
	if(GLOB.shipyard_decal_types_seen[decal.type])
		return
	GLOB.shipyard_decal_types_seen[decal.type] = TRUE
	shipyard_seed_decal_index()
	shipyard_record_decal_signature(decal.type, decal.icon, decal.icon_state, decal.dir, decal.layer, decal.alpha, decal.color)

/// File one appearance under a path that produces it. First writer keeps the
/// key, which is what makes the answer the same on every round rather than a
/// record of which decal happened to be placed last.
/proc/shipyard_record_decal_signature(decal_path, decal_icon, decal_icon_state, decal_dir, decal_layer, decal_alpha, decal_color)
	var/signature = shipyard_decal_signature(decal_icon, decal_icon_state, decal_dir, decal_layer, decal_alpha, decal_color)
	if(signature && !GLOB.shipyard_decal_signatures[signature])
		GLOB.shipyard_decal_signatures[signature] = decal_path
	var/shape = shipyard_decal_shape(decal_icon, decal_icon_state, decal_layer, decal_alpha, decal_color)
	if(shape && !GLOB.shipyard_decal_shapes[shape])
		GLOB.shipyard_decal_shapes[shape] = decal_path

/**
 * Seed the index from declared type defaults, before any instance is filed.
 *
 * Appearances are not unique to a path: a family that never declares its own
 * intermediate type inherits the base decal's icon state, so several paths draw
 * exactly the same thing and only one of them can hold the key. Seeding the
 * whole set up front settles that by declaration order instead of by whatever
 * the round happened to place, and since the paths that collide are identical
 * by construction, which one wins changes nothing about the ship.
 *
 * What instance registration adds on top is appearances no default explains -
 * a decal recoloured for a holiday, or one a mapper turned.
 */
/proc/shipyard_seed_decal_index()
	if(GLOB.shipyard_decal_index_seeded)
		return
	GLOB.shipyard_decal_index_seeded = TRUE
	for(var/obj/effect/turf_decal/decal_path as anything in subtypesof(/obj/effect/turf_decal))
		shipyard_record_decal_signature(
			decal_path,
			initial(decal_path.icon),
			initial(decal_path.icon_state),
			initial(decal_path.dir),
			initial(decal_path.layer),
			initial(decal_path.alpha),
			initial(decal_path.color),
		)

/**
 * Every deck marking on a turf, described as map cell members.
 *
 * Decals a turf or a component applies for itself - neon carpet, blood, a
 * forensic trace - are excluded rather than written down: the turf regenerates
 * them on load, so recording them doubles them. All three of those arrive with
 * a smoothing junction, a cleanable flag or a description, and a turf decal
 * carries none of the three.
 */
/proc/shipyard_describe_turf_decals(turf/deck, list/lost_detail)
	var/list/described = list()
	var/list/datum/element/decal/applied = list()
	SEND_SIGNAL(deck, COMSIG_ATOM_DECALS_ROTATING, applied)
	if(!length(applied))
		return described

	shipyard_seed_decal_index()
	for(var/datum/element/decal/decal as anything in applied)
		if(!isnull(decal.smoothing) || decal.cleanable || decal.description)
			continue
		var/decal_icon = decal.pic?.icon
		var/decal_color = decal.pic?.color
		var/decal_layer = decal.pic?.layer
		var/decal_alpha = decal.pic?.alpha
		var/signature = shipyard_decal_signature(decal_icon, decal.base_icon_state, decal.directional, decal_layer, decal_alpha, decal_color)
		var/decal_path = signature && GLOB.shipyard_decal_signatures[signature]
		if(!decal_path)
			var/shape = shipyard_decal_shape(decal_icon, decal.base_icon_state, decal_layer, decal_alpha, decal_color)
			decal_path = shape && GLOB.shipyard_decal_shapes[shape]
		if(!decal_path)
			lost_detail += "([deck.x], [deck.y]): unrecognized deck marking '[decal.base_icon_state]'"
			continue
		described += list(list(
			"path" = decal_path,
			"vars" = shipyard_decal_overrides(decal_path, decal),
			"helpers" = list(),
		))
	return described

/// What a matched decal path would have to be told to reproduce this decal.
/proc/shipyard_decal_overrides(obj/effect/turf_decal/decal_path, datum/element/decal/decal)
	var/list/overrides = list()
	if(decal.directional && decal.directional != initial(decal_path.dir))
		overrides["dir"] = decal.directional
	if(decal.base_icon_state != initial(decal_path.icon_state))
		overrides["icon_state"] = decal.base_icon_state
	if(isnull(decal.pic))
		return overrides
	if(!islist(decal.pic.color) && decal.pic.color != initial(decal_path.color))
		overrides["color"] = decal.pic.color
	if(decal.pic.alpha != initial(decal_path.alpha))
		overrides["alpha"] = decal.pic.alpha
	if(decal.pic.layer != initial(decal_path.layer))
		overrides["layer"] = decal.pic.layer
	return overrides

// --- Lockbox ----------------------------------------------------------------

/**
 * The one container on a ship whose contents survive being saved.
 *
 * Everything else aboard, loose or in a locker, is discarded on teardown. A
 * single bounded container is what makes the items problem tractable: the
 * payload is auditable, appraisal has a fixed scope, and a player knows exactly
 * what is coming back with them.
 */
/obj/structure/closet/secure_closet/ship_lockbox
	name = "ship lockbox"
	desc = "A registry-sealed hold. Whatever is inside it when a vessel is filed away comes back out with the vessel; whatever is not, does not."
	locked = FALSE
