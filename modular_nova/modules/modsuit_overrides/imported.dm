/datum/mod_theme/rustdicate // rusty syndie
	name = "Rusty syndicate"
	desc = "A suit designed by Gorlex Marauders, used to provide amazing armor, but it doesnt look like it'll be doing that anymore"
	extended_desc = "An advanced combat suit, rusted, dented and torched. \
		warped plasteel sheets hammered back into shape, the ceramic composites however- seem in-tact. \
		A small tag hangs off of it reading; 'Pr***rty o* **e Go**** M***ud**s- \
		All rights reserved, tampering with suit will void warranty."
	armor_type = /datum/armor/mod_theme_rustdicate
	atom_flags = PREVENT_CONTENTS_EXPLOSION_1
	siemens_coefficient = 0
	slowdown_deployed = 0
	complexity_max = DEFAULT_MAX_COMPLEXITY + -5
	charge_drain = DEFAULT_CHARGE_DRAIN * 3
	ui_theme = "syndicate"
	default_skin = "rustdicate"
	inbuilt_modules = list()
	variants = list(
		"rustdicate" = list(
			/obj/item/clothing/head/mod = list(
				UNSEALED_LAYER = NECK_LAYER,
				UNSEALED_CLOTHING = SNUG_FIT,
				SEALED_CLOTHING = THICKMATERIAL|STOPSPRESSUREDAMAGE|HEADINTERNALS,
				UNSEALED_INVISIBILITY = HIDEFACIALHAIR,
				SEALED_INVISIBILITY = HIDEMASK|HIDEEARS|HIDEEYES|HIDEFACE|HIDEHAIR|HIDESNOUT,
				SEALED_COVER = HEADCOVERSMOUTH|HEADCOVERSEYES|PEPPERPROOF,
				UNSEALED_MESSAGE = HELMET_UNSEAL_MESSAGE,
				SEALED_MESSAGE = HELMET_SEAL_MESSAGE,
			),
			/obj/item/clothing/suit/mod = list(
				UNSEALED_CLOTHING = THICKMATERIAL,
				SEALED_CLOTHING = STOPSPRESSUREDAMAGE,
				SEALED_INVISIBILITY = HIDEJUMPSUIT,
				UNSEALED_MESSAGE = CHESTPLATE_UNSEAL_MESSAGE,
				SEALED_MESSAGE = CHESTPLATE_SEAL_MESSAGE,
			),
			/obj/item/clothing/gloves/mod = list(
				UNSEALED_CLOTHING = THICKMATERIAL,
				SEALED_CLOTHING = STOPSPRESSUREDAMAGE,
				CAN_OVERSLOT = TRUE,
				UNSEALED_MESSAGE = GAUNTLET_UNSEAL_MESSAGE,
				SEALED_MESSAGE = GAUNTLET_SEAL_MESSAGE,
			),
			/obj/item/clothing/shoes/mod = list(
				UNSEALED_CLOTHING = THICKMATERIAL,
				SEALED_CLOTHING = STOPSPRESSUREDAMAGE,
				CAN_OVERSLOT = TRUE,
				UNSEALED_MESSAGE = BOOT_UNSEAL_MESSAGE,
				SEALED_MESSAGE = BOOT_SEAL_MESSAGE,
			),
		))



/datum/armor/mod_theme_rustdicate
	melee = 25
	bullet = 30
	laser = 30
	energy = 20
	bomb = 20
	bio = 100
	fire = 20
	acid = 50
	wound = 20

/obj/item/mod/control/pre_equipped/rustdicate
	theme = /datum/mod_theme/rustdicate
	applied_cell = /obj/item/stock_parts/power_store/cell/super
	applied_core = /obj/item/mod/construction/broken_core
	applied_modules = list(
	)
	default_pins = list(
	)
