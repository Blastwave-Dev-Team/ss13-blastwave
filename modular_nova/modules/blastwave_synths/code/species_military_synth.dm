// MODULE ID: BLASTWAVE_SYNTHS
// A corpse-and-mob-only synth chassis line that bleeds coolant instead of oil.
// Deliberately locked out of character prefs, roundstart races, pride mirrors and slime extracts: it exists so that
// ruin bodies read as military hardware, not so anyone can play one.

/datum/species/synthetic/military
	name = "Military Synthetic Humanoid"
	// Must be unique. GLOB.species_list is keyed on id, so reusing SPECIES_SYNTH would collide with the playable synth.
	id = SPECIES_SYNTH_MILITARY
	// Still reads as a synth when examined, since that is what the body looks like.
	examine_limb_id = SPECIES_SYNTH
	// Narrowed from the parent so this cannot leak out through pride mirrors, slime extracts, race swaps or ERT spawns.
	changesource_flags = MIRROR_BADMIN
	always_customizable = FALSE
	// The one real difference from the playable chassis. Everything else (synth organs, synth bodyparts,
	// TRAIT_ROBOTIC_DNA_ORGANS) is inherited, so surgery still yields real synth organs.
	exotic_bloodtype = BLOOD_TYPE_COOLANT

/datum/species/synthetic/military/check_roundstart_eligible()
	return FALSE
