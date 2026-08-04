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
	/// Designs this trusted stock license may synthesize for its own manifest.
	var/list/embedded_design_ids = list()
	/// Opt-in for purchased stock disks whose license covers every designed dependency.
	var/prebake_dependency_designs = FALSE

/obj/item/ship_blueprint_disk/Initialize(mapload)
	. = ..()
	embedded_design_ids = embedded_design_ids.Copy()
	addtimer(CALLBACK(src, PROC_REF(load_ship_plan)), 0)

/obj/item/ship_blueprint_disk/proc/load_ship_plan()
	if(ship_plan)
		return ship_plan
	if(!ispath(template_type, /datum/map_template/shuttle))
		return null
	var/datum/map_template/shuttle/template_defaults = template_type
	var/template_key = "[initial(template_defaults.port_id)]_[initial(template_defaults.suffix)]"
	var/datum/map_template/shuttle/template = SSmapping.shuttle_templates[template_key]
	if(!template)
		template = new template_type()
	ship_plan = new /datum/ship_plan/template(template)
	if(prebake_dependency_designs)
		for(var/requirement in ship_plan.required_parts)
			var/datum/design/design = shipyard_dependency_design(requirement)
			if(design)
				embedded_design_ids[design.id] = TRUE
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
	if(length(embedded_design_ids))
		. += span_notice("Licensed dependencies: [length(embedded_design_ids)] designs.")

/obj/item/ship_blueprint_disk/personal_shuttle
	name = "NT Personal custom-registration blueprint disk"
	template_type = /datum/map_template/shuttle/overmap/frigate/nt_personal
	registration_label = "custom registration"

/obj/item/ship_blueprint_disk/personal_shuttle/typed
	name = "NT Personal frigate-registration blueprint disk"
	registration_area_type = /area/shuttle/overmap/frigate
	registration_port_type = /obj/docking_port/mobile/overmap/frigate/nt_personal
	registration_is_custom = FALSE
	registration_label = "frigate registration"
	prebake_dependency_designs = TRUE

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

/// Builds the route coverage fixture. Every construction route has a
/// representative on this hull, so a build that finishes here has exercised the
/// whole route table rather than the subset a real ship happens to use.
/obj/item/ship_blueprint_disk/shipyard_validation
	name = "shipyard validation blueprint disk"
	desc = "A diagnostic design disk. The hull it describes is a test rig: one of everything, bolted to a box."
	template_type = /datum/map_template/shuttle/overmap/shipyard_validation

