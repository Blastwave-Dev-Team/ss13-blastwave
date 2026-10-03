// MODULE ID: OVERMAP
/// Hidden unary port used by `/datum/gas_machine_connector` for machine-side pipe hookups.
/obj/machinery/atmospherics/components/unary/gas_connector
	name = "gas connector"
	desc = "An internal manifold tap that joins machine plumbing to the local pipenet."
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

// `gas_machine_connector/New()` queues this rebuild in the middle of a map load,
// and SSair can reach it while the load yields between linking devices and
// building their pipelines. A pipeline grown from this side takes the adjacent
// pipe, the load's own build takes the pipe back, and the first pipeline is left
// holding the pipe and this port for good. Join the pipe's network instead, or
// leave it to the pipe's own build to reach us.
/obj/machinery/atmospherics/components/unary/gas_connector/get_rebuild_targets()
	var/obj/machinery/atmospherics/pipe/pipe = nodes[1]
	if(parents[1] || !istype(pipe))
		return ..()
	pipe.parent?.add_member(src, pipe)

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

// The same stale link seen from the pipe's side: a pipe being deleted still lists
// this connector, which no longer lists it back. The base disconnect() indexes
// nodes[nodes.Find(pipe)] = nodes[0], and that runtime aborts the pipe's Destroy()
// partway, leaving it in its pipeline as a hard delete.
/obj/machinery/atmospherics/components/unary/gas_connector/disconnect(obj/machinery/atmospherics/reference)
	if(nodes.Find(reference))
		return ..()
	if(istype(reference, /obj/machinery/atmospherics/pipe))
		var/obj/machinery/atmospherics/pipe/pipe = reference
		pipe.destroy_network()
