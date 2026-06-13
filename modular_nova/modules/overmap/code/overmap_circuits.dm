// MODULE ID: OVERMAP
// Circuit boards for overmap-specific machines. These mirror the existing
// shuttle / shuttle_engine boards so deconstructing and rebuilding works.
// Cargo packs and research designs are deferred past prototype.

/obj/item/circuitboard/computer/shuttle/helm
	name = "Helm Console"
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/helm

/obj/item/circuitboard/computer/shuttle/helm/viewscreen
	name = "Helm Viewscreen"
	build_path = /obj/machinery/computer/helm/viewscreen

/obj/item/circuitboard/computer/shuttle/overmap_nav
	name = "Overmap Navigation Computer"
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav

/obj/item/circuitboard/machine/engine/overmap
	name = "Overmap Thruster"
	greyscale_colors = CIRCUIT_COLOR_ENGINEERING
	build_path = /obj/machinery/power/shuttle_engine/overmap
	needs_anchored = FALSE

/obj/item/circuitboard/machine/engine/overmap/void
	name = "Void Thruster"
	build_path = /obj/machinery/power/shuttle_engine/overmap/void

/obj/item/circuitboard/machine/engine/overmap/standard
	name = "Fusion Thruster"
	build_path = /obj/machinery/power/shuttle_engine/overmap/standard

/obj/item/circuitboard/machine/overmap/fuel_injector
	name = "Overmap Fuel Injector"
	greyscale_colors = CIRCUIT_COLOR_ENGINEERING
	build_path = /obj/machinery/overmap/fuel_injector
	needs_anchored = FALSE
