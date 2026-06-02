// MODULE ID: SPACEPODS
// Fully-assembled spacepods for mapping and events.
// Ported from Whitesands (whitesands/code/modules/spacepods/prebuilt.dm).

/obj/spacepod/prebuilt
	icon = 'modular_nova/modules/spacepods/icons/2x2.dmi'
	icon_state = "pod_civ"
	var/cell_type = /obj/item/stock_parts/power_store/cell/high
	var/pod_armor_type = /obj/item/pod_parts/armor
	var/internal_tank_type = /obj/machinery/portable_atmospherics/canister/air
	var/list/equipment_types = list()

/obj/spacepod/prebuilt/Initialize(mapload)
	. = ..()
	add_armor(new pod_armor_type(src))
	if(cell_type)
		cell = new cell_type(src)
	if(internal_tank_type)
		internal_tank = new internal_tank_type(src)
	for(var/equip in equipment_types)
		var/obj/item/spacepod_equipment/installed = new equip(src)
		installed.on_install(src)

/obj/spacepod/prebuilt/sec
	name = "security space pod"
	icon_state = "pod_mil"
	locked = TRUE
	pod_armor_type = /obj/item/pod_parts/armor/security
	equipment_types = list(
		/obj/item/spacepod_equipment/weaponry/disabler,
		/obj/item/spacepod_equipment/lock/keyed/sec,
		/obj/item/spacepod_equipment/tracker,
		/obj/item/spacepod_equipment/cargo/chair,
	)

// adminbus spacepod for jousting events
/obj/spacepod/prebuilt/jousting
	name = "jousting space pod"
	icon_state = "pod_mil"
	pod_armor_type = /obj/item/pod_parts/armor/security
	cell_type = /obj/item/stock_parts/power_store/cell/infinite
	equipment_types = list(
		/obj/item/spacepod_equipment/weaponry/laser,
		/obj/item/spacepod_equipment/cargo/chair,
		/obj/item/spacepod_equipment/cargo/chair,
	)

/obj/spacepod/prebuilt/jousting/red
	icon_state = "pod_synd"
	pod_armor_type = /obj/item/pod_parts/armor/security/red
