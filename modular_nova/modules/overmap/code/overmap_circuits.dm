// MODULE ID: OVERMAP
// Circuit boards for overmap-specific machines. These mirror the existing
// shuttle / shuttle_engine boards so deconstructing and rebuilding works.

/obj/item/circuitboard/computer/shuttle/helm
	name = "Astrogation Helm"
	desc = "A computer board. Full ship piloting: throttle, heading, autopilot, and NavBall."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/helm

/obj/item/circuitboard/computer/shuttle/helm/viewscreen
	name = "Astrogation Viewscreen"
	desc = "A computer board. Displays the astrogation helm interface as a wall-mounted screen."
	build_path = /obj/machinery/computer/helm/viewscreen

/obj/item/circuitboard/computer/shuttle/overmap_nav
	name = "Astrogation Landing Console"
	desc = "A computer board. Camera-based landing at astrogation landing zones and points of interest."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/camera_advanced/shuttle_docker/overmap_nav

/obj/item/circuitboard/machine/engine/overmap
	name = "Astrogation Thruster"
	desc = "A machine board. A basic low-thrust engine for interstellar travel."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/power/shuttle_engine/overmap
	needs_anchored = FALSE

/obj/item/circuitboard/machine/engine/overmap/void
	name = "Void Thruster"
	desc = "A machine board. Experimental zero-fuel engine. Thrust from nothing."
	build_path = /obj/machinery/power/shuttle_engine/overmap/void

/obj/item/circuitboard/machine/engine/overmap/standard
	name = "Hall-Nuclear-Thermal Engine"
	desc = "A machine board. High-performance astrogation engine with nuclear-thermal assist and a hall-only emergency mode."
	build_path = /obj/machinery/power/shuttle_engine/overmap/standard

/obj/item/circuitboard/machine/overmap/fuel_injector
	name = "Fuel Injector"
	desc = "A machine board. Processes piped or tanked propellant for linked astrogation engines."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/overmap/fuel_injector
	needs_anchored = FALSE
	// Frame construction requires a parts list: circuit_added() copies it
	// unconditionally, so a null list runtimes. These match RefreshParts().
	req_components = list(
		/datum/stock_part/matter_bin = 1,
		/datum/stock_part/micro_laser = 1,
	)

/obj/item/circuitboard/machine/landing_corner
	name = "Landing Zone Corner Beacon"
	desc = "A machine board. Marks one corner of an astrogation landing zone rectangle."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/landing_corner
	req_components = list(
		/datum/stock_part/scanning_module = 1,
		/obj/item/stack/sheet/glass = 1,
	)

/obj/item/circuitboard/computer/landing_controller
	name = "Landing Zone Controller"
	desc = "A computer board. Manages a player-built astrogation landing zone from four corner beacons."
	greyscale_colors = CIRCUIT_COLOR_COMMAND
	build_path = /obj/machinery/computer/landing_controller
