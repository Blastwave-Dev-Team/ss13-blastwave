// MODULE ID: OVERMAP
// The front desk shared by every shipyard counter: who is logged in, what their
// ledger and the registry say, and which landing pad the console works over.
//
// Held by the console rather than inherited, so the registrar and the broker
// keep their own type paths. One per console, for its whole life: a login fills
// the operator half in and a logout clears it, while the pad link stays.

/// Longest a single operation may hold a counter before it is let go regardless.
#define SHIPYARD_BUSY_TIMEOUT (30 SECONDS)

/datum/shipyard_session
	/// The console this desk belongs to.
	var/obj/machinery/computer/owner
	/// ID record captured at login, for the operator name on screen.
	var/alist/operator_id_data
	/// Character the session acts for.
	var/operator_uuid
	var/operator_ckey
	var/character_name
	/// ID card affiliation at login (an OVERMAP_AFFILIATION_* id, or null for
	/// open), which the broker's catalog is filtered by.
	var/affiliation
	/// ID trim type at login, for listings restricted to one employer.
	var/operator_trim
	/// Ledger PIN captured at login, which purchases must match.
	var/operator_pin
	var/ledger_balance
	var/registry_online = FALSE
	var/ledger_online = FALSE
	/// list("kind" = "good" or "bad", "text" = ...), or null.
	var/list/status_message
	/// Landing controller supplying the pad this console works over.
	var/datum/weakref/linked_controller
	/// What the counter is in the middle of, shown over its whole UI, or null.
	var/busy_operation
	/// world.time after which a stuck operation stops holding the console.
	var/busy_until = 0
	/// The operator walked away mid-operation; log out when it finishes.
	var/logout_pending = FALSE

/datum/shipyard_session/New(obj/machinery/computer/owner)
	. = ..()
	src.owner = owner

/datum/shipyard_session/Destroy()
	owner = null
	return ..()

/// Link to the landing controller in a multitool's buffer. Returns an item_interaction result, or null to fall through.
/datum/shipyard_session/proc/try_link(mob/living/user, obj/item/multitool/tool)
	if(!istype(tool.buffer, /obj/machinery/computer/landing_controller))
		return null
	if(!link_controller(tool.buffer))
		owner.balloon_alert(user, "controller off-Z")
		return ITEM_INTERACT_BLOCKING
	owner.balloon_alert(user, "landing zone linked")
	return ITEM_INTERACT_SUCCESS

/// Links a same-Z landing controller. FALSE when it sits on another Z.
/datum/shipyard_session/proc/link_controller(obj/machinery/computer/landing_controller/controller)
	if(controller.z != owner.z)
		return FALSE
	linked_controller = WEAKREF(controller)
	return TRUE

/datum/shipyard_session/proc/examine_line()
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	return span_notice("Landing zone: [controller ? controller.zone_label : "unlinked"].")

/// The pad this console works over, or null when nothing is linked.
/datum/shipyard_session/proc/active_zone()
	var/obj/machinery/computer/landing_controller/controller = linked_controller?.resolve()
	if(QDELETED(controller?.active_zone))
		return null
	return controller.active_zone

/// Secure login: checks reach, power and access.
/datum/shipyard_session/proc/secure_login(mob/user)
	if(!user.can_perform_action(owner, ALLOW_SILICON_REACH) || !owner.is_operational)
		return FALSE
	if(!owner.allowed(user))
		owner.balloon_alert(user, "access denied")
		playsound(owner, 'sound/machines/terminal/terminal_error.ogg', 70, TRUE)
		return FALSE
	owner.balloon_alert(user, "logged in")
	playsound(owner, 'sound/machines/terminal/terminal_on.ogg', 70, TRUE)
	return TRUE

/// Open a session for `user`'s character.
/datum/shipyard_session/proc/start(mob/user)
	owner.authenticated = TRUE
	operator_id_data = ID_DATA(user)
	operator_uuid = user.mind?.character_uuid
	operator_ckey = user.ckey
	character_name = user.real_name
	var/mob/living/living_user = user
	var/obj/item/card/id/card = istype(living_user) ? living_user.get_idcard(hand_first = TRUE) : null
	affiliation = card ? get_id_overmap_faction(card) : null
	operator_trim = card?.trim?.type
	operator_pin = user.mind?.atm_pin
	status_message = null
	if(!operator_uuid)
		set_status(FALSE, "No persistent identity is on record for [user.real_name]. This counter cannot act for you.")
	refresh()

/datum/shipyard_session/proc/end()
	owner.authenticated = FALSE
	operator_id_data = null
	operator_uuid = null
	operator_ckey = null
	character_name = null
	affiliation = null
	operator_trim = null
	operator_pin = null
	ledger_balance = null
	status_message = null
	logout_pending = FALSE

/// Re-read the registry and ledger state `ui_data` shows.
/datum/shipyard_session/proc/refresh()
	registry_online = GLOB.ship_registry.is_online()
	ledger_online = SScharacter_ledger.is_available()
	ledger_balance = (ledger_online && operator_uuid) ? SScharacter_ledger.get_balance(operator_uuid) : null

/datum/shipyard_session/proc/set_status(good, text)
	status_message = list("kind" = good ? "good" : "bad", "text" = text)

/**
 * Hold the console for `operation`, the line its UI shows while it runs. Loading
 * and storing a map sleeps, and a click landing mid-load would otherwise run the
 * whole action again. FALSE when another operation already holds it.
 */
/datum/shipyard_session/proc/begin_busy(operation)
	if(is_busy())
		set_status(FALSE, "The counter is still working on the last request.")
		return FALSE
	busy_operation = operation
	busy_until = world.time + SHIPYARD_BUSY_TIMEOUT
	SStgui.update_uis(owner)
	return TRUE

/datum/shipyard_session/proc/end_busy()
	busy_operation = null
	busy_until = 0
	if(logout_pending)
		end()
		playsound(owner, 'sound/machines/terminal/terminal_off.ogg', 70, TRUE)
	SStgui.update_uis(owner)

/**
 * Confirm the logged-in character's ledger PIN, the same check the ATM uses
 * on withdraw. Unit tests and admin ghosts skip it: they call the action
 * procs directly, or they are not a character with a PIN.
 */
/datum/shipyard_session/proc/require_pin(mob/user, submitted)
	if(!user || isAdminGhostAI(user))
		return TRUE
	if(isnull(operator_pin))
		set_status(FALSE, "No PIN is on file for this character.")
		return FALSE
	var/entered = isnum(submitted) ? submitted : text2num(submitted)
	if(!isnull(entered) && entered == operator_pin)
		return TRUE
	set_status(FALSE, "Incorrect PIN.")
	return FALSE

/// End the session when the operator closes the UI or walks out of range.
/datum/shipyard_session/proc/on_operator_leave(mob/user)
	if(!owner.authenticated)
		return
	if(operator_ckey && user?.ckey && user.ckey != operator_ckey && !isAdminGhostAI(user))
		return
	if(is_busy())
		logout_pending = TRUE
		return
	end()
	playsound(owner, 'sound/machines/terminal/terminal_off.ogg', 70, TRUE)

/datum/shipyard_session/proc/is_busy()
	return !isnull(busy_operation) && world.time < busy_until

/datum/shipyard_session/proc/has_session(mob/user)
	return (owner.authenticated && isliving(user)) || isAdminGhostAI(user)

/// Garage slots for the logged-in player, in the shape both consoles send.
/datum/shipyard_session/proc/slot_usage()
	return GLOB.ship_garage_slots.usage(operator_ckey)

/// The keys every counter's `ui_data` starts with.
/datum/shipyard_session/proc/base_ui_data(mob/user)
	return list(
		"authenticated" = has_session(user),
		"operatorName" = operator_id_data?["name"],
		"characterName" = character_name,
		"registryOnline" = registry_online,
		"ledgerOnline" = ledger_online,
		"busy" = is_busy() ? busy_operation : null,
	)

/**
 * Handle the login and logout actions every counter shares. Returns TRUE when
 * `action` was one of them, so the console's `ui_act` can stop there.
 */
/datum/shipyard_session/proc/handle_login_act(action, mob/user)
	switch(action)
		if("login")
			if(isAdminGhostAI(user) || secure_login(user))
				start(user)
			return TRUE
		if("logout")
			end()
			owner.balloon_alert(user, "logged out")
			playsound(owner, 'sound/machines/terminal/terminal_off.ogg', 70, TRUE)
			return TRUE
	return FALSE

#undef SHIPYARD_BUSY_TIMEOUT
