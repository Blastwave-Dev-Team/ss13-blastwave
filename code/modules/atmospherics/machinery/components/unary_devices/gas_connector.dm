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

// BLASTWAVE EDIT ADDITION START - Shuttle transit resilience.
// The connector rides shuttle moves via abstract_move (forced, no disconnect),
// so after a rotated transit its parents[1] can hold a stale pipeline while
// nodes no longer contain the pipe that's reconnecting. The base component
// return_pipenet() then indexes parents[nodes.Find(pipe)] = parents[0] (out of
// bounds) and add_member() CRASHes. Fail soft here and let the SSair rebuild
// queue reconcile the network instead.
/obj/machinery/atmospherics/components/unary/gas_connector/return_pipenet(obj/machinery/atmospherics/target_component = nodes[1])
	if(!nodes.Find(target_component))
		return null
	return ..()

/obj/machinery/atmospherics/components/unary/gas_connector/add_member(obj/machinery/atmospherics/considered_device)
	if(!return_pipenet(considered_device))
		SSair.add_to_rebuild_queue(src)
		return
	return ..()
// BLASTWAVE EDIT ADDITION END
