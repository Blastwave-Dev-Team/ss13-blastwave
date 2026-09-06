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
