/obj/item/disk/design_disk/techweb_unlock
	name = "Research Technology Disk"
	desc = "A disk containing research data for upload at an R&D Console."
	icon_state = "rndmajordisk"
	/// The techweb node ID this disk unlocks.
	var/node_id
	var/datum/techweb_node/target_node

/obj/item/disk/design_disk/techweb_unlock/Initialize(mapload)
	. = ..()
	if(!node_id)
		return
	target_node = SSresearch.techweb_node_by_id(node_id)
	for(var/design_id in target_node.design_ids)
		blueprints += SSresearch.techweb_design_by_id(design_id)

/obj/item/disk/design_disk/techweb_unlock/on_upload(datum/techweb/stored_research, atom/research_source)
	if(!target_node)
		return
	stored_research.hidden_nodes -= target_node.id
	stored_research.research_node(target_node, force = TRUE, auto_adjust_cost = FALSE, research_source = research_source)

/obj/item/disk/design_disk/techweb_unlock/armory_munitions
	name = "Armory Munitions Research Disk"
	desc = "Contains research data for printable armory ballistic magazine bodies. Upload to an R&D Console to unlock Armory Munitions."
	node_id = TECHWEB_NODE_ARMORY_MUNITIONS

/obj/item/disk/design_disk/techweb_unlock/armory_ordnance
	name = "Armory Ordnance Research Disk"
	desc = "Contains research data for printable Kiboko grenade drum magazine bodies. Upload to an R&D Console to unlock Armory Ordnance."
	node_id = TECHWEB_NODE_ARMORY_ORDNANCE

/obj/item/disk/design_disk/techweb_unlock/commander_munitions
	name = "Commander Munitions Research Disk"
	desc = "Contains research data for printable Commander and Commissar magazine bodies. Upload to an R&D Console to unlock Commander Munitions."
	node_id = TECHWEB_NODE_COMMANDER_MUNITIONS

/datum/supply_pack/security/armory_munitions_disk
	name = "Armory Munitions Research Disk"
	desc = "A research disk that unlocks protolathe designs for empty Sol pistol, Sol rifle, and Kiboko grenade box magazines."
	cost = CARGO_CRATE_VALUE * 4
	contains = list(/obj/item/disk/design_disk/techweb_unlock/armory_munitions = 1)
	crate_name = "Armory Munitions Research Disk Crate"

/datum/supply_pack/security/armory_ordnance_disk
	name = "Armory Ordnance Research Disk"
	desc = "A research disk that unlocks protolathe designs for empty Kiboko grenade drum magazines."
	cost = CARGO_CRATE_VALUE * 5
	contains = list(/obj/item/disk/design_disk/techweb_unlock/armory_ordnance = 1)
	crate_name = "Armory Ordnance Research Disk Crate"

/datum/supply_pack/security/commander_munitions_disk
	name = "Commander Munitions Research Disk"
	desc = "A research disk that unlocks protolathe designs for empty Commander and Commissar pistol magazines."
	cost = CARGO_CRATE_VALUE * 2
	contains = list(/obj/item/disk/design_disk/techweb_unlock/commander_munitions = 1)
	crate_name = "Commander Munitions Research Disk Crate"
