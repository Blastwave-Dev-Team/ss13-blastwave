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
	// Load on demand. A deferred timer here races create_and_destroy / cargo
	// export qdel and can leave the disk stuck inside a container.

/obj/item/ship_blueprint_disk/proc/load_ship_plan()
	if(QDELETED(src))
		return null
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
	// Break closet/crate containment before the parent qdel chain. If we are
	// already QDELETED and later re-inserted, create_and_destroy hard-deletes.
	if(loc && !isturf(loc))
		moveToNullspace()
	return ..()

/obj/item/ship_blueprint_disk/update_name(updates)
	. = ..()
	if(ship_plan)
		name = "[ship_plan.name][registration_label ? " ([registration_label])" : ""] ship blueprint disk"

/obj/item/ship_blueprint_disk/examine(mob/user)
	. = ..()
	if(!ship_plan)
		load_ship_plan()
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

/**
 * A lost ship's last filed revision, printed by the registrar so it can be
 * built again and filed back into the same garage slot.
 *
 * Reads the saved map rather than a stock template, and registers the hull as
 * the port and area types that map carries, so a frigate comes back a frigate.
 * The lockbox roster lives in the registry rather than the map, so nothing it
 * held comes back with the hull.
 */
/obj/item/ship_blueprint_disk/registry_rebuild
	name = "registry rebuild blueprint disk"
	desc = "A registrar-issued design disk holding the last filed survey of a lost vessel."
	icon_state = "datadisk3"
	registration_label = "registry rebuild"
	/// The registry row a hull built from this disk files back into.
	var/registry_record_id
	/// Only this character's build is stamped with the row.
	var/registry_owner_uuid
	var/source_map_path
	var/source_revision
	var/source_checksum
	/// Kept alive for the plan, which reads its source template as it builds.
	var/datum/map_template/shuttle/runtime/runtime_template

/obj/item/ship_blueprint_disk/registry_rebuild/proc/imprint(datum/player_ship_record/record)
	registry_record_id = record.id
	registry_owner_uuid = record.owner_uuid
	source_map_path = record.map_path
	source_revision = record.revision
	source_checksum = record.map_checksum
	name = "[record.ship_name] registry rebuild blueprint disk"

/obj/item/ship_blueprint_disk/registry_rebuild/load_ship_plan()
	if(QDELETED(src))
		return null
	if(ship_plan)
		return ship_plan
	if(!source_map_path || !fexists(source_map_path))
		return null
	if(source_checksum && rustg_hash_file(RUSTG_HASH_SHA256, source_map_path) != source_checksum)
		return null
	var/datum/parsed_map/parsed = new(file(source_map_path))
	var/datum/ship_teardown/rebuilt = shipyard_teardown_from_parsed(parsed)
	adopt_registration(rebuilt)
	qdel(rebuilt)
	runtime_template = new(source_map_path)
	ship_plan = new /datum/ship_plan/template(runtime_template)
	update_appearance()
	return ship_plan

/// Take the port and area types the saved hull was registered as.
/obj/item/ship_blueprint_disk/registry_rebuild/proc/adopt_registration(datum/ship_teardown/rebuilt)
	var/list/area_counts = list()
	for(var/cell_key in rebuilt.cells)
		var/list/cell = rebuilt.cells[cell_key]
		var/area_path = cell["area_path"]
		if(ispath(area_path, /area/shuttle))
			area_counts[area_path] = (area_counts[area_path] || 0) + 1
		for(var/list/member as anything in cell["objects"])
			if(ispath(member["path"], /obj/docking_port/mobile))
				registration_port_type = member["path"]
	var/best_count = 0
	for(var/area_path in area_counts)
		if(area_counts[area_path] > best_count)
			best_count = area_counts[area_path]
			registration_area_type = area_path
	registration_is_custom = ispath(registration_port_type, /obj/docking_port/mobile/custom)

/obj/item/ship_blueprint_disk/registry_rebuild/Destroy()
	. = ..()
	QDEL_NULL(runtime_template)

/obj/item/ship_blueprint_disk/registry_rebuild/examine(mob/user)
	. = ..()
	if(registry_record_id)
		. += span_notice("Registry record [registry_record_id], revision [source_revision]. A hull built from this by its owner files back into the same garage slot.")

/// Builds the route coverage fixture. Every construction route has a
/// representative on this hull, so a build that finishes here has exercised the
/// whole route table rather than the subset a real ship happens to use.
/obj/item/ship_blueprint_disk/shipyard_validation
	name = "shipyard validation blueprint disk"
	desc = "A diagnostic design disk. The hull it describes is a test rig: one of everything, bolted to a box."
	template_type = /datum/map_template/shuttle/overmap/shipyard_validation

