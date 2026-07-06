/// Strips a raw slug down to safe wiki path characters and removes any ugc/ prefix.
/proc/sanitize_ugc_page_slug(raw_slug)
	if(!raw_slug)
		return null

	var/slug = trim(raw_slug)
	if(findtext(slug, "ugc/") == 1)
		slug = copytext(slug, 5)

	var/list/out = list()
	for(var/i in 1 to length(slug))
		var/char = slug[i]
		if((char >= "a" && char <= "z") || (char >= "A" && char <= "Z") || (char >= "0" && char <= "9") || char == "-" || char == "_")
			out += char
			if(length(out) >= UGC_PAGE_SLUG_MAX_LEN)
				break

	if(!length(out))
		return null

	return jointext(out, "")

/proc/sanitize_wiki_page_segment(segment)
	var/list/out = list()
	for(var/i in 1 to length(segment))
		var/char = segment[i]
		if((char >= "a" && char <= "z") || (char >= "A" && char <= "Z") || (char >= "0" && char <= "9") || char == "-" || char == "_")
			out += char
			if(length(out) >= UGC_PAGE_SLUG_MAX_LEN)
				break
	return length(out) ? jointext(out, "") : null

/// Sanitizes a full wiki page path, allowing nested segments separated by slashes.
/proc/sanitize_wiki_page_path(raw_path)
	if(!raw_path)
		return null

	var/path = trim(raw_path)
	while(length(path) && (path[1] == "/" || path[length(path)] == "/"))
		if(path[1] == "/")
			path = copytext(path, 2)
		if(length(path) && path[length(path)] == "/")
			path = copytext(path, 1, length(path))

	if(findtext(path, ".."))
		return null

	var/list/segments = splittext(path, "/")
	var/list/safe = list()
	var/total_len = 0
	for(var/segment in segments)
		if(!segment)
			continue
		var/safe_segment = sanitize_wiki_page_segment(segment)
		if(!safe_segment)
			continue
		safe += safe_segment
		total_len += length(safe_segment)
		if(length(safe) > 1)
			total_len++
		if(total_len > WIKI_PAGE_PATH_MAX_LEN)
			break

	return length(safe) ? jointext(safe, "/") : null

/// Archive rows uploaded before full paths were stored use bare lowercase slugs.
/proc/is_legacy_ugc_archive_slug(stored_content)
	if(findtext(stored_content, "/"))
		return FALSE
	if(findtext(stored_content, "_"))
		return FALSE
	return TRUE

/// Resolves the wiki page_link for a textbook. Non-admins are restricted to ugc/ paths.
/proc/resolve_textbook_page_link(raw_slug, restrict_to_ugc = TRUE, trusted = FALSE)
	if(!raw_slug)
		return null

	if(trusted)
		if(is_legacy_ugc_archive_slug(raw_slug))
			var/slug = sanitize_ugc_page_slug(raw_slug)
			return slug ? "ugc/[slug]" : null
		return sanitize_wiki_page_path(raw_slug)

	if(restrict_to_ugc)
		var/slug = sanitize_ugc_page_slug(raw_slug)
		return slug ? "ugc/[slug]" : null

	return sanitize_wiki_page_path(raw_slug)

/proc/can_print_wiki_paths(client/C)
	return C && check_rights_for(C, R_ADMIN)

/// Spawns a wiki-linked textbook that opens book.blastwave.space/<page_link>.
/proc/spawn_ugc_textbook(atom/location, title, author, page_slug, trusted = FALSE, restrict_to_ugc = TRUE)
	var/page_link = resolve_textbook_page_link(page_slug, restrict_to_ugc, trusted)
	if(!page_link || !title)
		return null

	var/datum/book_info/staging = new()
	staging.set_title(title, trusted = trusted)
	staging.set_author(author || "Community", trusted = trusted)
	if(!staging.title)
		return null

	var/obj/item/book/manual/wiki/ugc/book = new(location)
	book.page_link = page_link
	book.name = staging.get_title()
	book.starting_title = staging.title
	book.starting_author = staging.author
	book.book_data.set_title(staging.title, trusted = TRUE)
	book.book_data.set_author(staging.author, trusted = TRUE)
	return book
