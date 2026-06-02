// MODULE ID: SPACEPODS
// Spacepod construction frame + /datum/component/construction definition.
//
// Construction happens on a dedicated /obj/structure/spacepod_frame, mirroring the
// mech chassis pattern. When the final step completes, spawn_result() creates the
// flyable /obj/spacepod and deletes the frame. A destroyed pod also leaves one of
// these frames behind (see /obj/spacepod/atom_destruction), so wrecks are repairable.

/obj/structure/spacepod_frame
	name = "space pod frame"
	desc = "An assembled space pod frame."
	icon = 'modular_nova/modules/spacepods/icons/construction_2x2.dmi'
	icon_state = "pod_1"
	density = TRUE
	anchored = TRUE
	layer = SPACEPOD_LAYER
	bound_width = 64
	bound_height = 64
	max_integrity = 50
	/// Construction step index this frame starts at. 1 is a bare, freshly-strutted frame.
	var/start_index = 1
	/// Heading (degrees, clockwise from north) the finished pod will face.
	var/build_angle = 0

/obj/structure/spacepod_frame/Initialize(mapload, _start_index, _build_angle, obj/item/pod_parts/armor/existing_armor)
	. = ..()
	if(!isnull(_start_index))
		start_index = _start_index
	if(!isnull(_build_angle))
		build_angle = _build_angle
	if(existing_armor)
		existing_armor.forceMove(src)
	var/datum/component/construction/spacepod/build = AddComponent(/datum/component/construction/spacepod)
	build.index = clamp(start_index, 1, length(build.steps))
	build.update_parent(build.index)

// Same 2x2 footprint as the finished pod; allow tool/part interactions from any adjacent tile.
/obj/structure/spacepod_frame/Adjacent(atom/neighbor, atom/target, atom/movable/mover)
	return spacepod_footprint_adjacent(src, neighbor)

/// Hands the four frame pieces back, aligned to the frame's build heading.
/obj/structure/spacepod_frame/proc/drop_frame_pieces()
	var/clamped_angle = (round(build_angle, 90) % 360 + 360) % 360
	var/target_dir = NORTH
	switch(clamped_angle)
		if(0)
			target_dir = NORTH
		if(90)
			target_dir = EAST
		if(180)
			target_dir = SOUTH
		if(270)
			target_dir = WEST

	var/list/frame_piece_types = list(
		/obj/item/pod_parts/pod_frame/aft_port,
		/obj/item/pod_parts/pod_frame/aft_starboard,
		/obj/item/pod_parts/pod_frame/fore_port,
		/obj/item/pod_parts/pod_frame/fore_starboard,
	)
	var/obj/item/pod_parts/pod_frame/current_piece = null
	var/turf/current_turf = get_turf(src)
	var/list/frame_pieces = list()
	for(var/frame_type in frame_piece_types)
		var/obj/item/pod_parts/pod_frame/frame = new frame_type
		frame.setDir(target_dir)
		frame.anchored = TRUE
		if(NORTH == turn(frame.dir, -frame.link_angle))
			current_piece = frame
		frame_pieces += frame
	while(current_piece && !current_piece.loc)
		if(!current_turf)
			break
		current_piece.forceMove(current_turf)
		current_turf = get_step(current_turf, turn(current_piece.dir, -current_piece.link_angle))
		current_piece = locate(current_piece.link_to) in frame_pieces

/datum/component/construction/spacepod
	steps = list(
		list( // 1: bare struts
			"key" = /obj/item/stack/cable_coil,
			"amount" = 10,
			"back_key" = TOOL_WIRECUTTER,
			"desc" = "The struts are bare and need <b>wiring</b>. The frame can be split back into pieces with <b>wirecutters</b>.",
			"forward_message" = "wired the frame",
			"icon_state" = "pod_1",
		),
		list( // 2: wires loose
			"key" = TOOL_SCREWDRIVER,
			"back_key" = TOOL_WIRECUTTER,
			"desc" = "The wiring is loose and can be <b>screwed</b> down.",
			"forward_message" = "screwed down the wiring",
			"backward_message" = "cut out the wiring",
			"icon_state" = "pod_2",
		),
		list( // 3: wires secured
			"key" = /obj/item/circuitboard/mecha/pod,
			"action" = ITEM_DELETE,
			"back_key" = TOOL_SCREWDRIVER,
			"desc" = "The wiring is secured. A <b>circuit board</b> can be inserted.",
			"forward_message" = "inserted the circuit board",
			"backward_message" = "unscrewed the wiring",
			"icon_state" = "pod_3",
		),
		list( // 4: circuit loose
			"key" = TOOL_SCREWDRIVER,
			"back_key" = TOOL_CROWBAR,
			"desc" = "The circuit board is loose and can be <b>screwed</b> down.",
			"forward_message" = "secured the circuit board",
			"backward_message" = "pried out the circuit board",
			"icon_state" = "pod_4",
		),
		list( // 5: circuit secured
			"key" = /obj/item/pod_parts/core,
			"action" = ITEM_DELETE,
			"back_key" = TOOL_SCREWDRIVER,
			"desc" = "The circuit board is secured. A <b>core</b> can be inserted.",
			"forward_message" = "inserted the core",
			"backward_message" = "unsecured the circuit board",
			"icon_state" = "pod_5",
		),
		list( // 6: core loose
			"key" = TOOL_WRENCH,
			"back_key" = TOOL_CROWBAR,
			"desc" = "The core is loose and can be <b>bolted</b> in.",
			"forward_message" = "bolted in the core",
			"backward_message" = "pried out the core",
			"icon_state" = "pod_6",
		),
		list( // 7: core secured
			"key" = /obj/item/stack/sheet/iron,
			"amount" = 5,
			"back_key" = TOOL_WRENCH,
			"desc" = "The core is bolted in. Five <b>iron sheets</b> can form the bulkhead.",
			"forward_message" = "fabricated the bulkhead",
			"backward_message" = "unbolted the core",
			"icon_state" = "pod_7",
		),
		list( // 8: bulkhead loose
			"key" = TOOL_WRENCH,
			"back_key" = TOOL_CROWBAR,
			"desc" = "The bulkhead is loose and can be <b>bolted</b> down.",
			"forward_message" = "bolted down the bulkhead",
			"backward_message" = "popped the bulkhead loose",
			"icon_state" = "pod_8",
		),
		list( // 9: bulkhead secured
			"key" = TOOL_WELDER,
			"back_key" = TOOL_WRENCH,
			"desc" = "The bulkhead is bolted and can be <b>welded</b> shut.",
			"forward_message" = "welded the bulkhead shut",
			"backward_message" = "unbolted the bulkhead",
			"icon_state" = "pod_9",
		),
		list( // 10: bulkhead welded
			"key" = /obj/item/pod_parts/armor,
			"action" = ITEM_MOVE_INSIDE,
			"back_key" = TOOL_WELDER,
			"desc" = "The bulkhead is sealed. <b>Armor plating</b> can be attached.",
			"forward_message" = "attached the armor plating",
			"backward_message" = "cut the bulkhead loose",
			"icon_state" = "pod_10",
		),
		list( // 11: armor loose
			"key" = TOOL_WRENCH,
			"back_key" = TOOL_CROWBAR,
			"desc" = "The armor is loose and can be <b>bolted</b> down.",
			"forward_message" = "bolted down the armor",
			"backward_message" = "pried off the armor",
			"icon_state" = "pod_11",
		),
		list( // 12: armor secured
			"key" = TOOL_WELDER,
			"back_key" = TOOL_WRENCH,
			"desc" = "The armor is bolted and can be <b>welded</b> on to finish the pod.",
			"forward_message" = "welded on the armor",
			"backward_message" = "unbolted the armor",
			"icon_state" = "pod_12",
		),
	)

// Suppress the post-attackby melee ("you ineffectively jab the frame") when the held item is a
// valid construction key. The base component's action() is ASYNC, so it always returns 0 to the
// signal and never sets COMPONENT_NO_AFTERATTACK; that's harmless for the mech chassis (an item with
// no CAN_BE_HIT) but our frame is a structure, so /obj/attackby falls through to attack_atom.
// We still run check_step asynchronously so welder steps can use their do_after delay.
/datum/component/construction/spacepod/action(datum/source, obj/item/I, mob/living/user)
	SIGNAL_HANDLER
	if(!is_right_key(I))
		return NONE // not a construction step; let normal combat (and frame damage) happen.
	INVOKE_ASYNC(src, PROC_REF(check_step), I, user)
	return COMPONENT_NO_AFTERATTACK

/datum/component/construction/spacepod/custom_action(obj/item/I, mob/living/user, diff)
	// Wirecutters on the bare frame split the whole assembly back into its four pieces.
	if(index == 1 && I.tool_behaviour == TOOL_WIRECUTTER)
		var/obj/structure/spacepod_frame/frame = parent
		user.visible_message(span_notice("[user] takes [frame] apart."), span_notice("You take [frame] apart."))
		I.play_tool_sound(frame)
		frame.drop_frame_pieces()
		qdel(frame)
		return FALSE // The frame is gone; do not let the component advance the index.

	// Welding steps need a real delay and fuel, unlike the base component's instant tool use.
	if(I.tool_behaviour == TOOL_WELDER)
		var/delay = (index == length(steps) && diff == FORWARD) ? 50 : 20
		. = I.use_tool(parent, user, delay, amount = 3, volume = 50)
		if(.)
			announce_step(user, diff)
		return .

	. = ..()
	if(.)
		announce_step(user, diff)

/// Balloon-alerts the action that just occurred to onlookers.
/datum/component/construction/spacepod/proc/announce_step(mob/living/user, diff)
	var/list/current_step = steps[index]
	if(diff == FORWARD && current_step["forward_message"])
		user.balloon_alert_to_viewers(current_step["forward_message"])
	else if(diff == BACKWARD && current_step["backward_message"])
		user.balloon_alert_to_viewers(current_step["backward_message"])

/datum/component/construction/spacepod/update_parent(step_index)
	. = ..()
	var/obj/structure/spacepod_frame/frame = parent
	frame.cut_overlays()
	// Once the armor is on (step 11+), draw it as a masked overlay just like a finished pod.
	if(step_index >= 11)
		var/obj/item/pod_parts/armor/armor = locate() in frame
		if(armor)
			var/mutable_appearance/masked_armor = mutable_appearance(frame.icon, "armor_mask")
			var/mutable_appearance/armor_appearance = mutable_appearance(armor.pod_icon, armor.pod_icon_state)
			armor_appearance.blend_mode = BLEND_MULTIPLY
			masked_armor.overlays = list(armor_appearance)
			masked_armor.appearance_flags = KEEP_TOGETHER
			frame.add_overlay(masked_armor)

/datum/component/construction/spacepod/spawn_result()
	var/obj/structure/spacepod_frame/frame = parent
	var/turf/spawn_turf = get_turf(frame)
	if(!spawn_turf)
		return
	var/obj/spacepod/pod = new(spawn_turf)
	pod.angle = frame.build_angle
	var/obj/item/pod_parts/armor/armor = locate() in frame
	if(armor)
		armor.forceMove(pod)
		pod.add_armor(armor)
	pod.process(0.2) // prime the visual transform/offset the way frame assembly used to.
	qdel(frame)
