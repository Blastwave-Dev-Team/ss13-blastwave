/// Hidden unary port used by `/datum/gas_machine_connector` for machine-side pipe hookups.
/obj/machinery/atmospherics/components/unary/gas_connector
	name = "gas connector"
	desc = "An internal gas hookup. You should not be seeing this."
	icon_state = "inje_map-3"
	density = FALSE
	anchored = TRUE
	hide = TRUE
	layer = GAS_PIPE_HIDDEN_LAYER
	pipe_state = "injector"
	can_unwrench = FALSE
	shift_underlay_only = FALSE
	resistance_flags = FIRE_PROOF | UNACIDABLE | ACID_PROOF

/obj/machinery/atmospherics/components/unary/gas_connector/set_init_directions()
	initialize_directions = dir
