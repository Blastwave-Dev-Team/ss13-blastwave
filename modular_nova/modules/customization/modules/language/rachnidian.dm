/datum/language/rachnidian
	name = "Rachnidian"
	desc = "A language that exploits the multiple limbs of arachnids to do subtle dance-like movements to communicate. \
		A proper speaker's movements are quick and sharp enough to make audible whiffs and thumps however, which are \
		intelligible over the radio."
	key = "r"
	flags = NO_STUTTER | LANGUAGE_HIDE_ICON_IF_NOT_UNDERSTOOD
	icon = 'modular_nova/modules/customization/icons/effects/arachnid_language.dmi'
	icon_state = "spider"
	default_priority = 90
	// Syllables are referenced by the modern scramble pipeline as a sanity
	// fallback even when scramble_word is overridden, and they keep the
	// "Check Languages" preview from looking empty.
	syllables = list("wiff", "thump")

/// Per-word override mirrors the original Whitesands flavor: every spoken word
/// becomes either *wiff* or *thump*. The sentence-level scrambler assembles
/// them and re-applies trailing punctuation, so a question still ends in "?"
/// and a statement in ".".
/datum/language/rachnidian/scramble_word(input)
	return prob(65) ? "<i>wiff</i>" : "<i>thump</i>"

/datum/language/rachnidian/get_random_name(
	gender = NEUTER,
	name_count = default_name_count,
	syllable_min = default_name_syllable_min,
	syllable_max = default_name_syllable_max,
	force_use_syllables = FALSE,
)
	if(force_use_syllables || !length(GLOB.rachnid_first_names) || !length(GLOB.rachnid_last_names))
		return ..()
	return "[pick(GLOB.rachnid_first_names)] [pick(GLOB.rachnid_last_names)]"
