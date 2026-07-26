// MODULE ID: OVERMAP
// Blueprint media consumed by the shipyard fabricator.

/obj/item/ship_blueprint_disk
	name = "ship blueprint disk"
	desc = "A ruggedized design disk containing a declarative vessel construction manifest."
	icon = 'icons/obj/devices/floppy_disks.dmi'
	icon_state = "datadisk1"
	w_class = WEIGHT_CLASS_SMALL
	/// Shuttle template used to derive this disk's immutable build plan.
	var/template_type
	/// Runtime manifest owned by this disk.
	var/datum/ship_plan/ship_plan
	/// Area and mobile port used when the plated hull is registered.
	var/registration_area_type = /area/shuttle/custom
	var/registration_port_type = /obj/docking_port/mobile/custom
	var/registration_is_custom = TRUE
	/// Optional qualifier that distinguishes registration variants in-world.
	var/registration_label

/obj/item/ship_blueprint_disk/Initialize(mapload)
	. = ..()
	addtimer(CALLBACK(src, PROC_REF(load_ship_plan)), 0)

/obj/item/ship_blueprint_disk/proc/load_ship_plan()
	if(ship_plan)
		return ship_plan
	if(!ispath(template_type, /datum/map_template/shuttle))
		return null
	var/datum/map_template/shuttle/template = new template_type()
	ship_plan = new /datum/ship_plan/template(template)
	update_appearance()
	return ship_plan

/obj/item/ship_blueprint_disk/Destroy()
	QDEL_NULL(ship_plan)
	return ..()

/obj/item/ship_blueprint_disk/update_name(updates)
	. = ..()
	if(ship_plan)
		name = "[ship_plan.name][registration_label ? " ([registration_label])" : ""] ship blueprint disk"

/obj/item/ship_blueprint_disk/examine(mob/user)
	. = ..()
	if(!ship_plan)
		. += span_warning("The disk contains no readable ship manifest.")
		return
	. += span_notice("Design: <b>[ship_plan.name]</b> ([ship_plan.width]×[ship_plan.height]).")
	. += span_notice("Manifest: [length(ship_plan.manifest)] operations; [length(ship_plan.skipped_contents)] skipped map entries.")

/obj/item/ship_blueprint_disk/personal_shuttle
	name = "personal travel shuttle blueprint disk"
	template_type = /datum/map_template/shuttle/whiteship/personalshuttle

/obj/item/ship_blueprint_disk/solfed_cutter
	name = "SolFed Cutter custom-registration blueprint disk"
	template_type = /datum/map_template/shuttle/overmap/frigate/solfed_cutter
	registration_label = "custom registration"

/obj/item/ship_blueprint_disk/solfed_cutter/typed
	name = "SolFed Cutter frigate-registration blueprint disk"
	registration_area_type = /area/shuttle/overmap/frigate
	registration_port_type = /obj/docking_port/mobile/overmap/frigate/solfed_cutter
	registration_is_custom = FALSE
	registration_label = "frigate registration"

/obj/item/ship_blueprint_disk/solfed_patrol
	name = "SolFed Patrol custom-registration blueprint disk"
	template_type = /datum/map_template/shuttle/overmap/frigate/solfed_patrol
	registration_label = "custom registration"

/obj/item/ship_blueprint_disk/solfed_patrol/typed
	name = "SolFed Patrol frigate-registration blueprint disk"
	registration_area_type = /area/shuttle/overmap/frigate
	registration_port_type = /obj/docking_port/mobile/overmap/frigate/solfed_patrol
	registration_is_custom = FALSE
	registration_label = "frigate registration"

