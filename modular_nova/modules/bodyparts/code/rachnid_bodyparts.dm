// Arachnid base bodyparts. Wraps the original Whitesands `spider_parts.dmi`
// art - the DMI is wired in through the `icon_greyscale` slot like every other
// modern species, even though the sprites themselves are pre-colored (not true
// greyscale). That means MUTANT_COLOR tinting will not multiply through these
// limbs the way it does on insectoid/akula/etc.; the player's chosen mutant
// color only paints the external chitin overlays (legs, spinneret, mandibles)
// for now. Converting `rachnid_parts_greyscale.dmi` to a real greyscale pass
// is tracked as a follow-up.
//
// Icon-state naming inside the DMI follows the modern
// `<limb_id>_<body_zone>` convention enforced by /obj/item/bodypart/get_limb_icon
// (`rachnid_head`, `rachnid_chest`, `rachnid_l_arm`, `rachnid_r_hand`, ...).
// The chest is intentionally non-dimorphic (matches WS `sexes = 0`).

/obj/item/bodypart/head/arachnid
	icon_greyscale = BODYPART_ICON_ARACHNID
	limb_id = SPECIES_ARACHNID
	is_dimorphic = FALSE
	// Drop facial hair only - the outer mandibles overlay sits exactly where a
	// beard or moustache would render and the combo looks wrong. Everything
	// else (hair, lips, eye sprites/color, brain) stays on.
	head_flags = HEAD_DEFAULT_FEATURES & ~HEAD_FACIAL_HAIR

/obj/item/bodypart/chest/arachnid
	icon_greyscale = BODYPART_ICON_ARACHNID
	limb_id = SPECIES_ARACHNID
	is_dimorphic = FALSE

/obj/item/bodypart/arm/left/arachnid
	icon_greyscale = BODYPART_ICON_ARACHNID
	limb_id = SPECIES_ARACHNID

/obj/item/bodypart/arm/right/arachnid
	icon_greyscale = BODYPART_ICON_ARACHNID
	limb_id = SPECIES_ARACHNID

/obj/item/bodypart/leg/left/arachnid
	icon_greyscale = BODYPART_ICON_ARACHNID
	limb_id = SPECIES_ARACHNID

/obj/item/bodypart/leg/right/arachnid
	icon_greyscale = BODYPART_ICON_ARACHNID
	limb_id = SPECIES_ARACHNID
