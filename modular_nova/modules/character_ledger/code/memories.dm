/// Character ATM PIN, copied from prefs at spawn so the player can look it up.
/datum/memory/key/atm_pin
	memory_flags = MEMORY_FLAG_NOMOOD|MEMORY_FLAG_NOLOCATION|MEMORY_FLAG_NOPERSISTENCE|MEMORY_SKIP_UNCONSCIOUS|MEMORY_NO_STORY
	var/atm_pin

/datum/memory/key/atm_pin/New(
	datum/mind/memorizer_mind,
	atom/protagonist,
	atom/deuteragonist,
	atom/antagonist,
	atm_pin,
)
	src.atm_pin = atm_pin
	return ..()

/datum/memory/key/atm_pin/get_names()
	return list("The ATM PIN of [protagonist_name], [atm_pin].")

/datum/memory/key/atm_pin/get_starts()
	return list(
		"[protagonist_name] covering the keypad while entering [atm_pin].",
		"A sticky note with [atm_pin] hidden under [protagonist_name]'s ID.",
	)
