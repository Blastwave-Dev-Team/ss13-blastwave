// MODULE ID: OVERMAP
// Paperwork keeps what was written on it, and stays aboard a filed ship whether
// it is loose on the deck, in a locker, or in the lockbox.

/datum/shipyard_serdes/item/paper
	target_type = /obj/item/paper
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/paper/capture(obj/item/paper/target)
	var/list/state = ..() || list()
	state["data"] = target.convert_to_data()
	return state

/// Cleared first, so a paper that starts out pre-written does not end up with
/// its default text twice. Name and colour come back with the data.
/datum/shipyard_serdes/item/paper/apply(obj/item/paper/target, list/state)
	. = ..()
	if(!islist(state["data"]))
		return
	target.clear_paper()
	target.write_from_data(state["data"])
	target.update_appearance()

/// Applied to the plane's own paper rather than a new one: taking that paper
/// out deletes the plane.
/datum/shipyard_serdes/item/paperplane
	target_type = /obj/item/paperplane
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/paperplane/capture(obj/item/paperplane/target)
	var/list/state = ..() || list()
	if(target.internal_paper)
		state["paper"] = shipyard_capture_state(target.internal_paper)
	return state

/datum/shipyard_serdes/item/paperplane/apply(obj/item/paperplane/target, list/state)
	if(target.internal_paper && islist(state["paper"]))
		shipyard_apply_state(target.internal_paper, state["paper"])
	return ..()

/// Stored and restored as the already-sanitized values, which is what
/// `trusted` exists for. Bibles and manuals inherit this.
/datum/shipyard_serdes/item/book
	target_type = /obj/item/book
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/book/capture(obj/item/book/target)
	var/list/state = ..() || list()
	if(target.book_data)
		state["title"] = target.book_data.title
		state["author"] = target.book_data.author
		state["content"] = target.book_data.content
	state["carved"] = target.carved
	return state

/// Carved before the roster restores the book's storage, so the compartment
/// exists by the time its contents go back in.
/datum/shipyard_serdes/item/book/apply(obj/item/book/target, list/state)
	if(target.book_data)
		if(!isnull(state["title"]))
			target.book_data.set_title(state["title"], trusted = TRUE)
		if(!isnull(state["author"]))
			target.book_data.set_author(state["author"], trusted = TRUE)
		if(!isnull(state["content"]))
			target.book_data.set_content(state["content"], trusted = TRUE)
	if(state["carved"] && !target.carved)
		target.carve_out()
	return ..()

/// A folder holds its papers directly rather than in storage. Whatever its type
/// spawns with is cleared before the saved contents go back.
/datum/shipyard_serdes/item/folder
	target_type = /obj/item/folder
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/folder/capture(obj/item/folder/target)
	var/list/state = ..() || list()
	state["contents"] = shipyard_roster_of(target)
	return state

/datum/shipyard_serdes/item/folder/apply(obj/item/folder/target, list/state)
	if(islist(state["contents"]))
		for(var/obj/item/spawned in target)
			qdel(spawned)
		for(var/list/held_entry in state["contents"])
			shipyard_restore_roster_entry(held_entry, target)
	return ..()

/// Papers in order, which one is on top, and the pen. An integrated pen is part
/// of the clipboard and is left alone.
/datum/shipyard_serdes/item/clipboard
	target_type = /obj/item/clipboard
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/clipboard/capture(obj/item/clipboard/target)
	var/list/state = ..() || list()
	var/list/papers = list()
	var/top_index = 0
	for(var/obj/item/paper/held in target)
		papers += list(shipyard_roster_entry(held))
		if(held == target.top_paper)
			top_index = length(papers)
	state["papers"] = papers
	state["top"] = top_index
	if(target.pen && !target.integrated_pen)
		state["pen"] = shipyard_roster_entry(target.pen)
	return state

/datum/shipyard_serdes/item/clipboard/apply(obj/item/clipboard/target, list/state)
	if(islist(state["papers"]))
		for(var/obj/item/paper/spawned in target)
			qdel(spawned)
		var/list/obj/item/paper/restored = list()
		for(var/list/held_entry in state["papers"])
			var/obj/item/paper/held = shipyard_restore_roster_entry(held_entry, target)
			if(istype(held))
				restored += held
		var/top_index = state["top"]
		if(isnum(top_index) && top_index >= 1 && top_index <= length(restored))
			if(target.top_paper)
				target.UnregisterSignal(target.top_paper, COMSIG_ATOM_UPDATED_ICON)
			target.top_paper = restored[top_index]
			target.RegisterSignal(target.top_paper, COMSIG_ATOM_UPDATED_ICON, TYPE_PROC_REF(/obj/item/clipboard, on_top_paper_change))
	if(!target.integrated_pen)
		if(target.pen)
			qdel(target.pen)
		if(islist(state["pen"]))
			var/obj/item/pen/pen = shipyard_restore_roster_entry(state["pen"], target)
			if(istype(pen))
				target.pen = pen
			else if(pen)
				qdel(pen)
	return ..()

/// Blank paper is a count; only written sheets are kept one by one.
/datum/shipyard_serdes/item/paper_bin
	target_type = /obj/item/paper_bin
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/paper_bin/capture(obj/item/paper_bin/target)
	var/list/state = ..() || list()
	state["total_paper"] = target.total_paper
	var/list/stack = list()
	for(var/obj/item/paper/sheet as anything in target.paper_stack)
		stack += list(shipyard_roster_entry(sheet))
	state["paper_stack"] = stack
	if(target.bin_pen)
		state["pen"] = shipyard_roster_entry(target.bin_pen)
	return state

/datum/shipyard_serdes/item/paper_bin/apply(obj/item/paper_bin/target, list/state)
	QDEL_LIST(target.paper_stack)
	if(islist(state["paper_stack"]))
		for(var/list/sheet_entry in state["paper_stack"])
			var/obj/item/paper/sheet = shipyard_restore_roster_entry(sheet_entry, target)
			if(istype(sheet))
				target.paper_stack += sheet
	if(isnum(state["total_paper"]))
		target.total_paper = max(state["total_paper"], length(target.paper_stack))
	if(target.bin_pen)
		QDEL_NULL(target.bin_pen)
	if(islist(state["pen"]))
		var/obj/item/pen/pen = shipyard_restore_roster_entry(state["pen"], target)
		if(istype(pen))
			target.bin_pen = pen
		else if(pen)
			qdel(pen)
	return ..()

/**
 * A photo's image is copied under `data/player_ships/photos/`, named by its
 * hash so a picture filed many times is stored once. Independent of the
 * picture log config, and of old picture logs still existing.
 */
/datum/shipyard_serdes/item/photo
	target_type = /obj/item/photo
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/photo/capture(obj/item/photo/target)
	var/list/state = ..() || list()
	if(target.scribble)
		state["scribble"] = target.scribble
	var/datum/picture/picture = target.picture
	if(!picture?.picture_image)
		return length(state) ? state : null
	var/image_path = shipyard_store_photo_image(picture.picture_image)
	if(!image_path)
		return length(state) ? state : null
	var/list/picture_state = picture.serialize_list(semvers = list())
	picture_state["logpath"] = image_path
	picture_state["id"] = "shipyard_[md5(image_path)]"
	state["picture"] = picture_state
	return state

/datum/shipyard_serdes/item/photo/apply(obj/item/photo/target, list/state)
	if(islist(state["picture"]))
		var/datum/picture/picture = new()
		if(picture.deserialize_list(state["picture"], list(SCHEMA_VERSION = "1.0.1")))
			target.set_picture(picture, TRUE, TRUE, TRUE)
	if(istext(state["scribble"]))
		target.scribble = state["scribble"]
	return ..()

/// Write a picture to its content-addressed file and return the path, or null.
/proc/shipyard_store_photo_image(icon/picture_image)
	var/staging_path = "data/player_ships/photos/staging_[world.time]_[rand(1, 999999)].png"
	fcopy(icon(picture_image, dir = SOUTH, frame = 1), staging_path)
	if(!fexists(staging_path))
		return null
	var/digest = rustg_hash_file(RUSTG_HASH_SHA256, staging_path)
	if(!digest)
		fdel(staging_path)
		return null
	var/final_path = "data/player_ships/photos/[digest].png"
	if(!fexists(final_path))
		fcopy(staging_path, final_path)
	fdel(staging_path)
	return fexists(final_path) ? final_path : null

/// No state of their own, but they stay aboard. An album's photos come back
/// through its storage.
/datum/shipyard_serdes/item/kept_paperwork
	target_type = /obj/item/storage/photo_album
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/documents
	target_type = /obj/item/documents
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/paperwork
	target_type = /obj/item/paperwork
	keeps_aboard = TRUE

/datum/shipyard_serdes/item/paperwork/capture(obj/item/paperwork/target)
	var/list/state = ..() || list()
	if(target.stamped)
		state["stamped"] = TRUE
	return length(state) ? state : null

/datum/shipyard_serdes/item/paperwork/apply(obj/item/paperwork/target, list/state)
	if(state["stamped"] && !target.stamped)
		target.add_stamp()
	return ..()
