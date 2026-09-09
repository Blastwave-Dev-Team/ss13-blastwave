// MODULE ID: BLASTWAVE_SYNTHS

/// Blood analogue for military synth chassis. Not a fuel subtype: the whole point of coolant over oil is that it does not burn.
/datum/reagent/coolant
	name = "Coolant"
	description = "A milky phase-change coolant thick with suspended ceramic. Non-flammable, and cold enough on contact to sting."
	color = BLOOD_COLOR_COOLANT
	taste_description = "chalk and antifreeze"
	ph = 8.5
	default_container = /obj/effect/decal/cleanable/blood/coolant

/// Military synth chassis coolant. Reads as a different hardware line to oil-blooded civilian synths, and unlike oil it will not catch fire.
/datum/blood_type/coolant
	name = BLOOD_TYPE_COOLANT
	desc = "A milky phase-change coolant, thick with suspended ceramic. Whatever it was pumped through was not built to be repaired in the field."
	dna_string = "Coolant"
	color = BLOOD_COLOR_COOLANT
	reagent_type = /datum/reagent/coolant
	restoration_chem = /datum/reagent/coolant
	blood_flags = BLOOD_COVER_ALL

/datum/blood_type/coolant/set_up_blood(obj/effect/decal/cleanable/blood/blood, new_splat = FALSE)
	. = ..()
	if(!new_splat)
		return

	// Always force our reagent so butchered synths do not leak liquid guts.
	blood.decal_reagent = reagent_type

	// Coolant dries to a chalky film rather than staying wet like oil, which is how you tell the two apart on a floor.
	blood.dry_prefix = "caked"
	blood.dry_desc = "A crust of dried coolant. Flakes when you scuff it."

	if(blood.desc == /obj/effect/decal/cleanable/blood::desc)
		blood.desc = /obj/effect/decal/cleanable/blood/coolant::desc

/obj/effect/decal/cleanable/blood/coolant
	name = "spilled coolant"
	// This is fetched in /datum/blood_type/coolant/set_up_blood() for all blood decals with default desc
	desc = "Milky white and faintly cold. Something with a closed loop bled out here."
	color = /datum/blood_type/coolant::color // For mapper sanity

/obj/effect/decal/cleanable/blood/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/obj/effect/decal/cleanable/blood/splatter/coolant
	name = "spilled coolant"
	color = /datum/blood_type/coolant::color

/obj/effect/decal/cleanable/blood/splatter/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/*
 * Mapper-placeable variants of the rest of the blood decals.
 *
 * Anything a synth bleeds at runtime is already coolant-coloured, because every decal gets built
 * from the mob's blood type. These exist purely so a mapper can dress a scene that happened before
 * the round started, which is the only case the engine cannot colour for us.
 *
 * The single thing each variant actually needs is get_default_blood_type(). DM has no multiple
 * inheritance, so that override cannot be shared and gets restated once per decal - same as
 * upstream's oil variants directly above ours in the type tree.
 *
 * `name` and `color` are mapper previews. At runtime update_name() rebuilds the name from
 * `base_name`/`base_suffix` plus the blood type ("pool of coolant", "drop of coolant"), and
 * update_blood_color() recolours from the blood DNA, so both get overwritten on init except where
 * a parent nulls `base_name`. Set them anyway or the ruin is dressed with red puddles in StrongDMM.
 *
 * Skipped deliberately: `hitsplatter` and `trail_holder` are runtime-only machinery that never
 * survive maploading, `innards` is organic viscera, and `bubblegum` belongs to the megafauna.
 */

/// Coolant is a phase-change fluid, so a fresh pool is every bit as treacherous as spilled oil.
/obj/effect/decal/cleanable/blood/coolant/slippery/Initialize(mapload, list/datum/disease/diseases, list/blood_or_dna)
	. = ..()
	AddComponent(/datum/component/slippery, 80, (NO_SLIP_WHEN_WALKING | SLIDE))

/obj/effect/decal/cleanable/blood/old/coolant
	name = "caked coolant"
	// Not the true dried colour - update_blood_color() computes that from our base colour at init,
	// landing on a slate grey-teal. This is the wet colour so the decal at least previews as coolant.
	color = /datum/blood_type/coolant::color

/obj/effect/decal/cleanable/blood/old/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/obj/effect/decal/cleanable/blood/drip/coolant
	name = "drop of coolant"
	color = /datum/blood_type/coolant::color

/obj/effect/decal/cleanable/blood/drip/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/// The holder is the mappable half of the trail system: `/blood/trail` qdels itself
/// unless its loc is a holder, and `add_dir_to_trail()` always builds components as
/// the base type, so a `/blood/trail` subtype could never be reached. The components
/// take their DNA from the holder, so overriding it here is what colours them.
/obj/effect/decal/cleanable/blood/trail_holder/coolant
	name = "trail of coolant"
	desc = "Your instincts say you shouldn't be following these."
	color = /datum/blood_type/coolant::color

/obj/effect/decal/cleanable/blood/trail_holder/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/// Wheeled and treaded chassis dragging a leak. The parent nulls `base_name`, so this name sticks.
/obj/effect/decal/cleanable/blood/tracks/coolant
	name = "coolant tracks"
	desc = "They look like tracks left by wheels, laid down in something pale."
	color = /datum/blood_type/coolant::color

/obj/effect/decal/cleanable/blood/tracks/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/// Something walked away from wherever it was leaking. The parent nulls `base_name` too.
/obj/effect/decal/cleanable/blood/footprints/coolant
	name = "coolant footprints"
	desc = "Pale, faintly cold prints. Whatever left them was still walking."
	color = /datum/blood_type/coolant::color

/obj/effect/decal/cleanable/blood/footprints/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/*
 * Gibs
 *
 * Two flavours on purpose. The organic-shaped `gibs` recolour suits our humanoid chassis, which
 * wear a human sprite and come apart like one; `robot_debris` suits anything that read as a
 * machine from the outside. Both pull their reagent from set_up_blood() above, so neither leaks
 * liquid gibs the way a stock organic gib pile would.
 */

/obj/effect/decal/cleanable/blood/gibs/coolant
	name = "wrecked assembly"
	desc = "Torn ceramic and loom, wet with something milky. It was built to look like it had organs."
	color = /datum/blood_type/coolant::color

/obj/effect/decal/cleanable/blood/gibs/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/obj/effect/decal/cleanable/blood/gibs/old/coolant
	name = "dried wrecked assembly"
	color = /datum/blood_type/coolant::color

/obj/effect/decal/cleanable/blood/gibs/old/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

// Note that robot_debris nulls its own colour and skips update_blood_color() entirely, so these
// four look identical to the oil-blooded originals. Only the reagent and blood DNA differ, which
// still matters: a scanner, a mop, and anything drinking off the floor all read coolant.
/obj/effect/decal/cleanable/blood/gibs/robot_debris/coolant/get_default_blood_type()
	return get_blood_type(BLOOD_TYPE_COOLANT)

/obj/effect/decal/cleanable/blood/gibs/robot_debris/coolant/limb
	icon_state = "gibarm"
	random_icon_states = list("gibarm", "gibleg")

/obj/effect/decal/cleanable/blood/gibs/robot_debris/coolant/up
	icon_state = "gibup"
	random_icon_states = list("gib1", "gib2", "gib3", "gib4", "gib5", "gib6", "gib7", "gibup", "gibup")

/obj/effect/decal/cleanable/blood/gibs/robot_debris/coolant/down
	icon_state = "gibdown"
	random_icon_states = list("gib1", "gib2", "gib3", "gib4", "gib5", "gib6", "gib7", "gibdown", "gibdown")
