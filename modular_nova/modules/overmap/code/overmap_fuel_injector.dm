// MODULE ID: OVERMAP
// Hybrid propellant processor: any atmos mix, LINDA chemical burn + thermal expulsion.

/obj/machinery/overmap/fuel_injector
	name = "fuel injector"
	desc = "Processes piped or tanked propellant for linked thrusters."
	icon = 'modular_nova/modules/overmap/icons/fuel_machine.dmi'
	icon_state = "machine"
	density = TRUE
	use_power = IDLE_POWER_USE
	idle_power_usage = BASE_MACHINE_IDLE_CONSUMPTION * 0.5
	circuit = /obj/item/circuitboard/machine/overmap/fuel_injector
	max_integrity = 400
	armor_type = /datum/armor/portable_atmospherics_canister

	var/datum/gas_mixture/air_contents
	var/datum/gas_machine_connector/input_connector
	var/datum/gas_machine_connector/exhaust_connector
	var/datum/gas_machine_connector/feed_connector
	var/list/datum/weakref/linked_engines = list()
	var/link_rescan_counter = 0

	var/obj/item/tank/fuel_tank
	var/chamber_volume = TANK_STANDARD_VOLUME
	var/max_moles = 0
	var/base_isp = 1
	var/micro_laser_rating = 1
	var/matter_bin_rating = 1
	var/burning = FALSE
	var/consuming = FALSE
	var/max_operating_pressure = OVERMAP_FUEL_DEFAULT_PRESSURE
	/// Glow-plug chamber preheater toggle. Draws power each tick to walk the chamber toward the setpoint.
	var/preheat_enabled = FALSE
	/// Target chamber temperature (K) for the preheater. Clamped to the micro laser's reachable range.
	var/preheat_setpoint = PLASMA_MINIMUM_BURN_TEMPERATURE
	/// Assoc gas_path -> TRUE if allowed from L1 into chamber.
	var/list/intake_filter = list()
	/// Assoc gas_path -> TRUE if scrubbed from chamber to L3.
	var/list/scrub_filter = list()

/obj/machinery/overmap/fuel_injector/Initialize(mapload)
	. = ..()
	air_contents = new(chamber_volume)
	air_contents.set_temperature(T20C)
	recalculate_max_moles()
	input_connector = new(loc, src, dir, CELL_VOLUME * 0.5, PIPING_LAYER_MIN)
	feed_connector = new(loc, src, dir, CELL_VOLUME * 0.5, OVERMAP_HNT_FEED_LAYER)
	exhaust_connector = new(loc, src, dir, CELL_VOLUME * 0.5, PIPING_LAYER_DEFAULT)
	if(mapload)
		fill_default_mix()
	init_fuel_injector_filter_defaults(src)
	update_linked_engines()
	register_context()
	RegisterSignal(src, COMSIG_ATOM_DIR_CHANGE, PROC_REF(on_dir_change))

/obj/machinery/overmap/fuel_injector/Destroy()
	QDEL_NULL(input_connector)
	QDEL_NULL(feed_connector)
	QDEL_NULL(exhaust_connector)
	linked_engines.Cut()
	QDEL_NULL(air_contents)
	return ..()

/obj/machinery/overmap/fuel_injector/Moved(atom/old_loc, movement_dir, forced, list/old_locs, momentum_change)
	. = ..()
	update_linked_engines()

/obj/machinery/overmap/fuel_injector/proc/on_dir_change(datum/source, old_dir, new_dir)
	SIGNAL_HANDLER
	update_linked_engines()

/obj/machinery/overmap/fuel_injector/proc/get_piped_engines()
	var/list/engines = list()
	var/datum/pipeline/feed_pipe = overmap_hnt_feed_pipeline(feed_connector)
	if(!feed_pipe)
		return engines
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(src)
	if(!port)
		return engines
	for(var/obj/machinery/power/shuttle_engine/overmap/engine in port.engine_list)
		if(overmap_hnt_feed_pipeline(engine.feed_connector) == feed_pipe)
			engines += engine
	return engines

/obj/machinery/overmap/fuel_injector/proc/link_adjacent_engines()
	for(var/direction in GLOB.cardinals)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine in get_step(get_turf(src), direction))
			if(engine.dir != dir)
				continue
			engine.set_linked_injector(src, FALSE)
			linked_engines += WEAKREF(engine)

/obj/machinery/overmap/fuel_injector/proc/update_linked_engines()
	for(var/datum/weakref/engine_ref as anything in linked_engines)
		var/obj/machinery/power/shuttle_engine/overmap/engine = engine_ref?.resolve()
		if(engine)
			engine.clear_injector_link(src)
	linked_engines.Cut()
	var/list/piped = get_piped_engines()
	if(length(piped))
		for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in piped)
			engine.set_linked_injector(src, TRUE)
			linked_engines += WEAKREF(engine)
	else
		link_adjacent_engines()

/obj/machinery/overmap/fuel_injector/proc/update_adjacent_engines()
	update_linked_engines()

/obj/machinery/overmap/fuel_injector/proc/recalculate_max_moles()
	max_moles = (max_operating_pressure * chamber_volume) / (R_IDEAL_GAS_EQUATION * T20C)

/obj/machinery/overmap/fuel_injector/proc/fill_default_mix()
	if(!air_contents)
		return
	var/total = (OVERMAP_FUEL_DEFAULT_PRESSURE * chamber_volume) / (R_IDEAL_GAS_EQUATION * T20C)
	air_contents.set_temperature(T20C)
	air_contents.remove(air_contents.total_moles())
	air_contents.adjust_gas(/datum/gas/plasma, total * OVERMAP_FUEL_PLASMA_RATIO)
	air_contents.adjust_gas(/datum/gas/oxygen, total * OVERMAP_FUEL_OXYGEN_RATIO)

/obj/machinery/overmap/fuel_injector/RefreshParts()
	. = ..()
	matter_bin_rating = 1
	micro_laser_rating = 1
	for(var/datum/stock_part/matter_bin/matter_bin in component_parts)
		matter_bin_rating = max(matter_bin_rating, matter_bin.tier)
	for(var/datum/stock_part/micro_laser/micro_laser in component_parts)
		micro_laser_rating = max(micro_laser_rating, micro_laser.tier)
	chamber_volume = TANK_STANDARD_VOLUME + (matter_bin_rating - 1) * 20
	if(air_contents)
		air_contents.volume = chamber_volume
	recalculate_max_moles()
	base_isp = 1 + 0.1 * (micro_laser_rating - 1)

/obj/machinery/overmap/fuel_injector/return_air()
	return air_contents

/obj/machinery/overmap/fuel_injector/proc/return_chamber_pressure()
	return air_contents?.return_pressure() || 0

/obj/machinery/overmap/fuel_injector/proc/return_chamber_temperature()
	return air_contents?.temperature || T20C

/obj/machinery/overmap/fuel_injector/proc/return_fuel()
	return get_stored_propellant_moles()

/obj/machinery/overmap/fuel_injector/proc/return_fuel_cap()
	return max_moles

/// Chamber and/or L2 feed have usable propellant (gauges / status pills).
/obj/machinery/overmap/fuel_injector/proc/has_propellant()
	return get_stored_propellant_moles() > 0.01

/// L2 manifold has moles ready for thrust (gates chemical/thermal burn vs hall-only).
/obj/machinery/overmap/fuel_injector/proc/has_feed_propellant()
	var/datum/gas_mixture/feed_air = get_feed_air()
	return (feed_air?.total_moles() || 0) > 0.01

/obj/machinery/overmap/fuel_injector/proc/get_feed_air()
	var/datum/pipeline/feed_pipe = overmap_hnt_feed_pipeline(feed_connector)
	if(!feed_pipe?.air || feed_pipe.air.volume <= 0)
		return null
	return feed_pipe.air

/obj/machinery/overmap/fuel_injector/proc/get_stored_propellant_moles()
	var/total = air_contents?.total_moles() || 0
	var/datum/gas_mixture/feed_air = get_feed_air()
	if(feed_air)
		total += feed_air.total_moles()
	return total

/obj/machinery/overmap/fuel_injector/proc/get_preheat_efficiency()
	return 1 + 0.1 * (micro_laser_rating - 1)

/obj/machinery/overmap/fuel_injector/process_atmos(seconds_per_tick)
	if(!is_operational || !air_contents)
		return
	link_rescan_counter++
	if(link_rescan_counter >= 20)
		link_rescan_counter = 0
		update_linked_engines()
	process_intake()
	process_preheat(seconds_per_tick || 0.5)
	process_chamber_reaction()
	process_exhaust_filter()
	process_feed_output()

/// Keep a lit chamber burning: react the mix every tick (same pattern as
/// portable atmospherics) so ignition self-sustains. Skipped while a burn
/// tick owns the mix via consuming.
/obj/machinery/overmap/fuel_injector/proc/process_chamber_reaction()
	if(consuming)
		return
	var/reacted = air_contents.react(src)
	if(burning != !!reacted)
		burning = !!reacted
		update_appearance()

/obj/machinery/overmap/fuel_injector/proc/process_intake()
	var/datum/pipeline/pipe = input_connector?.gas_connector?.parents?[1]
	// A connector with no pipes attached still gets a pipenet, but with air.volume = 0
	// (machine airs live in other_airs). remove_ratio() on it creates zero-volume
	// mixtures and stack-traces every tick, so bail until real pipe is attached.
	if(!pipe?.air || pipe.air.volume <= 0)
		return
	if(air_contents.return_pressure() >= max_operating_pressure)
		return
	var/transfer_ratio = min(MAX_TRANSFER_RATE / max(air_contents.volume, 1), 0.25)
	var/datum/gas_mixture/removed = pipe.air.remove_ratio(transfer_ratio)
	if(!removed?.total_moles())
		return
	var/datum/gas_mixture/rejected = new(removed.volume)
	for(var/gas_id in removed.gases.Copy())
		if(intake_filter[gas_id])
			continue
		var/moles = removed.gases[gas_id][MOLES]
		if(moles <= 0)
			continue
		rejected.adjust_gas(gas_id, moles)
		removed.adjust_gas(gas_id, -moles)
	if(rejected.total_moles())
		pipe.air.merge(rejected)
	if(removed.total_moles())
		air_contents.merge(removed)
	input_connector.gas_connector.update_parents()

/obj/machinery/overmap/fuel_injector/proc/process_exhaust_filter()
	var/datum/pipeline/exhaust_pipe = exhaust_connector?.gas_connector?.parents?[1]
	if(!exhaust_pipe?.air || exhaust_pipe.air.volume <= 0) // see process_intake() - don't vent into an unpiped (zero-volume) net
		return
	if(exhaust_pipe.air.return_pressure() >= MAX_OUTPUT_PRESSURE)
		return
	var/datum/gas_mixture/scrubbed = new(CELL_VOLUME)
	var/remaining_transfer = MAX_TRANSFER_RATE * 0.1
	for(var/gas_id in air_contents.gases)
		if(!scrub_filter[gas_id])
			continue
		var/moles = air_contents.gases[gas_id][MOLES]
		if(moles <= 0)
			continue
		var/transfer = min(moles, remaining_transfer)
		if(transfer <= 0)
			break
		air_contents.adjust_gas(gas_id, -transfer)
		scrubbed.adjust_gas(gas_id, transfer)
		remaining_transfer -= transfer
	if(!scrubbed.total_moles())
		return
	exhaust_pipe.air.merge(scrubbed)
	exhaust_connector.gas_connector.update_parents()

/// Continuous pressure-regulated push of post-scrub chamber mix onto the L2 feed manifold.
/obj/machinery/overmap/fuel_injector/proc/process_feed_output()
	if(consuming || !air_contents?.total_moles())
		return
	var/datum/pipeline/feed_pipe = overmap_hnt_feed_pipeline(feed_connector)
	if(!feed_pipe?.air || feed_pipe.air.volume <= 0)
		return
	var/chamber_pressure = air_contents.return_pressure()
	var/feed_pressure = feed_pipe.air.return_pressure()
	if(chamber_pressure <= feed_pressure + OVERMAP_FEED_MIN_DELTA_P)
		return
	var/to_transfer = min(OVERMAP_FEED_TRANSFER_RATE, air_contents.total_moles())
	if(to_transfer <= 0)
		return
	var/datum/gas_mixture/removed = air_contents.remove(to_transfer)
	if(!removed?.total_moles())
		return
	feed_pipe.air.merge(removed)
	feed_connector.gas_connector.update_parents()

/// Pull propellant from the L2 feed for thrust. Chemical bonus when the removed
/// mix is hot/reacting; otherwise thermal path (gas ISP only). Empty feed → (0, 0)
/// so HNT can fall through to hall-only.
/obj/machinery/overmap/fuel_injector/proc/consume_from_feed(requested_moles, power_fraction)
	if(requested_moles <= 0)
		return list(0, 0)
	var/datum/gas_mixture/feed_air = get_feed_air()
	if(!feed_air?.total_moles())
		return list(0, 0)
	consuming = TRUE
	var/to_remove = min(requested_moles, feed_air.total_moles())
	var/datum/gas_mixture/removed = feed_air.remove(to_remove)
	feed_connector.gas_connector.update_parents()
	if(!removed?.total_moles())
		consuming = FALSE
		return list(0, 0)

	// Optional thermal assist on cold expulsion (grid pays to superheat remaining demand).
	var/chemical_bonus = fuel_injector_estimate_chemical_bonus(removed)
	if(chemical_bonus <= 1 && power_fraction > 0)
		var/target_temp = min(OVERMAP_THERMAL_EXHAUST_TEMP, removed.temperature + 200)
		var/cp = removed.heat_capacity()
		if(cp > 0 && target_temp > removed.temperature)
			var/energy = cp * (target_temp - removed.temperature)
			use_energy(energy * clamp(power_fraction, 0.1, 1))
			removed.set_temperature(target_temp)

	var/effective_isp = base_isp * overmap_gas_isp_multiplier(removed) * chemical_bonus
	var/burn_fraction = min(removed.total_moles() / requested_moles, 1)
	consuming = FALSE
	update_appearance()
	return list(burn_fraction, effective_isp)

/obj/machinery/overmap/fuel_injector/proc/process_tick_burn(list/obj/machinery/power/shuttle_engine/overmap/engines, burn_pct)
	if(!length(engines) || consuming)
		return list()
	var/list/valid = list()
	var/total_moles = 0
	var/total_pf = 0
	for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in engines)
		if(!engine || engine.get_linked_injector() != src)
			continue
		if(!engine.enabled || !engine.thruster_active)
			continue
		var/power_fraction = engine.get_power_fraction()
		var/m_i = overmap_engine_propellant_share_moles(engine.thrust, power_fraction, burn_pct)
		if(m_i <= 0)
			continue
		valid += engine
		total_moles += m_i
		total_pf += power_fraction
	if(!length(valid) || total_moles <= 0 || !has_feed_propellant())
		return list()
	var/weighted_pf = total_pf / length(valid)
	var/list/burn_result = consume_from_feed(total_moles, weighted_pf)
	var/burn_fraction = burn_result[1]
	var/effective_isp = burn_result[2]
	if(burn_fraction <= 0 || effective_isp <= 0)
		return list()
	var/list/thrust_results = list()
	for(var/obj/machinery/power/shuttle_engine/overmap/engine as anything in valid)
		var/power_fraction = engine.get_power_fraction()
		var/thrust = engine.thrust * power_fraction * effective_isp * burn_fraction * (burn_pct / 100)
		engine.use_energy(engine.max_power_draw * power_fraction * (burn_pct / 100))
		engine.burning = TRUE
		thrust_results[engine] = thrust
	return thrust_results

/// Spark the chamber. If the mix is combustible this kicks it to reaction
/// temperature and lets the chemistry self-heat; if nothing reacts, the
/// temperature bump is reverted so sparking can't be used as free heating.
/obj/machinery/overmap/fuel_injector/proc/ignite_chamber(mob/user)
	if(consuming)
		if(user)
			balloon_alert(user, "chamber busy!")
		return FALSE
	if(!air_contents?.total_moles())
		if(user)
			balloon_alert(user, "chamber empty!")
		return FALSE
	use_energy(OVERMAP_IGNITE_SPARK_ENERGY)
	do_sparks(2, TRUE, src)
	var/original_temperature = air_contents.temperature
	if(air_contents.temperature < PLASMA_MINIMUM_BURN_TEMPERATURE)
		air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE)
	var/reacted = FALSE
	for(var/i in 1 to OVERMAP_REACT_ITERATIONS)
		if(!air_contents.react(src))
			break
		reacted = TRUE
	if(!reacted)
		air_contents.set_temperature(original_temperature)
		if(user)
			balloon_alert(user, "mixture won't ignite!")
		return FALSE
	playsound(src, 'sound/items/tools/welder.ogg', 40, TRUE)
	if(user)
		balloon_alert(user, "chamber ignited")
	update_appearance()
	return TRUE

/// Highest preheat setpoint the installed micro laser can hold.
/obj/machinery/overmap/fuel_injector/proc/get_preheat_setpoint_max()
	return OVERMAP_PREHEAT_SETPOINT_MAX(micro_laser_rating)

/// Glow-plug heating: walk the chamber toward the setpoint with bounded
/// per-tick power. Heat delivered scales with micro laser tier; the grid is
/// billed the delivered heat divided by preheat efficiency.
/obj/machinery/overmap/fuel_injector/proc/process_preheat(seconds_per_tick)
	if(!preheat_enabled || !air_contents?.total_moles())
		return
	var/setpoint = clamp(preheat_setpoint, T20C, get_preheat_setpoint_max())
	if(air_contents.temperature >= setpoint)
		return
	var/cp = air_contents.heat_capacity()
	if(cp <= 0)
		return
	var/max_energy = OVERMAP_PREHEAT_POWER_BASE * micro_laser_rating * seconds_per_tick
	var/needed_energy = cp * (setpoint - air_contents.temperature)
	var/applied = min(max_energy, needed_energy)
	if(applied <= 0)
		return
	use_energy(applied / get_preheat_efficiency())
	air_contents.set_temperature(air_contents.temperature + applied / cp)

/obj/machinery/overmap/fuel_injector/proc/can_flameout()
	if(consuming)
		return FALSE
	for(var/datum/weakref/engine_ref as anything in linked_engines)
		var/obj/machinery/power/shuttle_engine/overmap/engine = engine_ref?.resolve()
		if(!engine)
			continue
		if(engine.enabled || engine.burning)
			return FALSE
	return TRUE

/obj/machinery/overmap/fuel_injector/proc/get_flameout_release_turf()
	for(var/datum/weakref/engine_ref as anything in linked_engines)
		var/obj/machinery/power/shuttle_engine/overmap/engine = engine_ref?.resolve()
		if(!engine)
			continue
		var/turf/exhaust_turf = get_step(get_turf(engine), engine.dir)
		if(exhaust_turf)
			return exhaust_turf
	return get_step(src, dir)

/obj/machinery/overmap/fuel_injector/proc/do_flameout(mob/user)
	if(!can_flameout())
		balloon_alert(user, "linked engines must be off!")
		return
	var/turf/release_turf = get_flameout_release_turf()
	if(!release_turf || !air_contents?.total_moles())
		balloon_alert(user, "nothing to dump")
		return
	playsound(src, 'sound/effects/spray2.ogg', 50, TRUE)
	release_turf.assume_air(air_contents)
	air_contents.remove(air_contents.total_moles())
	air_contents.set_temperature(T20C)
	burning = FALSE
	update_appearance()
	balloon_alert(user, "flameout complete")

/obj/machinery/overmap/fuel_injector/proc/get_linked_ship_mass()
	var/obj/docking_port/mobile/port = SSshuttle.get_containing_shuttle(src)
	var/obj/structure/overmap/ship/simulated/ship = port?.current_ship
	if(!istype(ship))
		return list(0, TRUE)
	if(!ship.mass)
		ship.calculate_mass()
	return list(ship.mass || 0, FALSE)

/obj/machinery/overmap/fuel_injector/ui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "FuelInjector", name)
		ui.open()

/obj/machinery/overmap/fuel_injector/ui_static_data(mob/user)
	. = list()
	.["gas_metadata"] = overmap_propellant_gas_data()

/obj/machinery/overmap/fuel_injector/ui_data(mob/user)
	var/list/input_data = fuel_injector_pipeline_ui_data(input_connector, max_moles)
	var/list/feed_data = fuel_injector_pipeline_ui_data(feed_connector, max_moles)
	var/list/exhaust_data = fuel_injector_pipeline_ui_data(exhaust_connector)
	exhaust_data["max_pressure"] = MAX_OUTPUT_PRESSURE

	var/datum/pipeline/input_pipe = input_connector?.gas_connector?.parents?[1]
	var/intake_rejection = input_pipe?.air ? fuel_injector_intake_rejection_ratio(input_pipe.air, intake_filter) : 0

	var/list/ship_mass_data = get_linked_ship_mass()
	var/ship_mass = ship_mass_data[1]
	var/ship_mass_unknown = ship_mass_data[2]
	var/estimated_isp = fuel_injector_estimate_isp(src)
	var/datum/gas_mixture/isp_mix = get_feed_air() || air_contents
	var/gas_multiplier = overmap_gas_isp_multiplier(isp_mix)
	var/chemical_bonus = fuel_injector_estimate_chemical_bonus(isp_mix)
	var/power_fraction = fuel_injector_estimate_power_fraction(src)
	var/list/manifold = fuel_injector_manifold_share_stats(src)

	. = list(
		"input" = input_data,
		"feed" = feed_data,
		"chamber" = list(
			"connected" = TRUE,
			"pressure" = round(return_chamber_pressure(), 0.1),
			"temperature" = round(return_chamber_temperature(), 0.1),
			"total_moles" = round(return_fuel(), 0.1),
			"max_moles" = max_moles,
			"max_pressure" = max_operating_pressure,
			"burning" = burning,
			"consuming" = consuming,
			"gas_composition" = fuel_injector_gas_composition(air_contents),
		),
		"preheat" = list(
			"enabled" = preheat_enabled,
			"setpoint" = preheat_setpoint,
			"setpoint_min" = T20C,
			"setpoint_max" = get_preheat_setpoint_max(),
			"power_draw" = OVERMAP_PREHEAT_POWER_BASE * micro_laser_rating / get_preheat_efficiency(),
			"ignition_temp" = PLASMA_MINIMUM_BURN_TEMPERATURE,
		),
		"exhaust" = exhaust_data,
		"filters" = list(
			"intake" = fuel_injector_filter_entries(intake_filter),
			"scrub" = fuel_injector_filter_entries(scrub_filter),
			"intake_rejection_ratio" = intake_rejection,
			"scrub_eligible_ratio" = fuel_injector_scrub_eligible_ratio(air_contents, scrub_filter),
		),
		"performance" = list(
			"estimated_isp" = round(estimated_isp, 3),
			"thrust_efficiency" = round(min(estimated_isp / FUEL_INJECTOR_ISP_NOMINAL_MAX, 1), 3),
			"delta_v" = ship_mass_unknown ? 0 : round(fuel_injector_estimate_delta_v(src, ship_mass), 2),
			"base_isp" = base_isp,
			"gas_multiplier" = round(gas_multiplier, 3),
			"chemical_bonus" = chemical_bonus,
			"power_fraction" = round(power_fraction, 3),
			"linked_engines" = length(linked_engines),
			"piped_engines" = manifold["piped_engines"],
			"adjacent_engines" = manifold["adjacent_engines"],
			"link_mode" = manifold["piped_engines"] ? "piped" : (manifold["adjacent_engines"] ? "adjacent" : "none"),
			"active_share_count" = manifold["active_share_count"],
			"per_engine_moles" = round(manifold["per_engine_moles"], 3),
			"total_tick_moles" = round(manifold["total_tick_moles"], 3),
			"feed_connected" = manifold["feed_connected"],
			"ship_mass" = ship_mass,
			"ship_mass_unknown" = ship_mass_unknown,
		),
		"status_pills" = fuel_injector_derive_chamber_status(src),
		"tank" = fuel_tank ? list(
			"installed" = TRUE,
			"name" = fuel_tank.name,
			"moles" = round(fuel_tank.air_contents?.total_moles() || 0, 0.1),
		) : null,
		"can_flameout" = can_flameout(),
		"parts" = list(
			"matter_bin_rating" = matter_bin_rating,
			"micro_laser_rating" = micro_laser_rating,
			"chamber_volume" = chamber_volume,
		),
	)

/obj/machinery/overmap/fuel_injector/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	. = ..()
	if(.)
		return
	switch(action)
		if("toggle_intake_filter")
			var/gas_path = gas_id2path(params["gas_id"])
			if(!gas_path || !ispath(gas_path, /datum/gas))
				return
			intake_filter[gas_path] = !intake_filter[gas_path]
			. = TRUE
		if("toggle_scrub_filter")
			var/gas_path = gas_id2path(params["gas_id"])
			if(!gas_path || !ispath(gas_path, /datum/gas))
				return
			scrub_filter[gas_path] = !scrub_filter[gas_path]
			. = TRUE
		if("filter_preset")
			apply_fuel_injector_filter_preset(src, params["preset"])
			. = TRUE
		if("flameout")
			if(!can_flameout())
				return
			var/mob/user = ui.user
			if(!do_after(user, 2 SECONDS, target = src))
				return
			do_flameout(user)
			. = TRUE
		if("toggle_preheat")
			preheat_enabled = !preheat_enabled
			. = TRUE
		if("set_preheat_target")
			var/target = text2num(params["target"])
			if(isnull(target))
				return
			preheat_setpoint = clamp(target, T20C, get_preheat_setpoint_max())
			. = TRUE
		if("ignite")
			ignite_chamber(ui.user)
			. = TRUE

/obj/machinery/overmap/fuel_injector/examine(mob/user)
	. = ..()
	. += span_notice("Fuel input: piping layer [PIPING_LAYER_MIN]. Propellant feed: piping layer [OVERMAP_HNT_FEED_LAYER]. Exhaust filter: piping layer [PIPING_LAYER_DEFAULT].")
	. += span_notice("Use to open the fuel processor interface.")
	. += span_notice("A <i>screwdriver</i> [panel_open ? "closes" : "opens"] the maintenance panel. With the panel open, a <i>wrench</i> rotates it, <i>right-click wrench</i> [anchored ? "unanchors" : "anchors"] it, and a <i>crowbar</i> deconstructs it.")
	if(!can_flameout())
		. += span_notice("Linked engine must be off before flameout.")
	else
		. += span_notice("Alt-click to dump the chamber (flameout) when engines are off.")
	if(air_contents?.total_moles())
		. += span_notice("Chamber: [round(air_contents.total_moles(), 0.1)] mol, [round(air_contents.return_pressure(), 0.1)] kPa, [round(air_contents.temperature, 0.1)] K.")
	. += span_notice("The chamber preheater is [preheat_enabled ? "holding [round(preheat_setpoint)] K" : "off"]. Combustible mixes can be lit with the igniter from the interface.")

/obj/machinery/overmap/fuel_injector/update_icon_state()
	if(machine_stat & BROKEN)
		icon_state = "machine-broken"
	else
		icon_state = "machine"
	return ..()

/obj/machinery/overmap/fuel_injector/update_overlays()
	. = ..()
	if(panel_open)
		. += mutable_appearance(icon, "machine-panel")
	if(!air_contents?.total_moles())
		. += mutable_appearance(icon, "machine-cannister_empty")
	else
		. += mutable_appearance(icon, "machine-cannister_fuel")
	if(burning)
		. += mutable_appearance(icon, "machine-screen_active")
	else
		. += mutable_appearance(icon, "machine-screen_idle")

/obj/machinery/overmap/fuel_injector/attackby(obj/item/attacking_item, mob/user, params)
	if(istype(attacking_item, /obj/item/tank))
		if(fuel_tank)
			to_chat(user, span_warning("Remove the existing tank first."))
			return
		if(!user.transferItemToLoc(attacking_item, src))
			return
		fuel_tank = attacking_item
		if(fuel_tank.air_contents?.total_moles())
			air_contents.merge(fuel_tank.air_contents.copy())
			fuel_tank.air_contents.remove(fuel_tank.air_contents.total_moles())
		balloon_alert(user, "tank connected")
		update_appearance()
		return
	return ..()

/obj/machinery/overmap/fuel_injector/screwdriver_act(mob/living/user, obj/item/tool)
	return default_deconstruction_screwdriver(user, tool)

/obj/machinery/overmap/fuel_injector/crowbar_act(mob/living/user, obj/item/tool)
	return default_deconstruction_crowbar(user, tool)

/// Primary wrench rotates the injector (and its propellant connectors) while the panel is open.
/obj/machinery/overmap/fuel_injector/wrench_act(mob/living/user, obj/item/tool)
	return default_change_direction_wrench(user, tool)

/// Secondary (right-click) wrench anchors/unanchors, mirroring atmos machines.
/obj/machinery/overmap/fuel_injector/wrench_act_secondary(mob/living/user, obj/item/tool)
	if(!panel_open)
		balloon_alert(user, "open panel!")
		return ITEM_INTERACT_SUCCESS
	if(default_unfasten_wrench(user, tool) == SUCCESSFUL_UNFASTEN)
		update_linked_engines()
	return ITEM_INTERACT_SUCCESS

/obj/machinery/overmap/fuel_injector/add_context(atom/source, list/context, obj/item/held_item, mob/living/user)
	if(isnull(held_item))
		return NONE
	switch(held_item.tool_behaviour)
		if(TOOL_SCREWDRIVER)
			context[SCREENTIP_CONTEXT_LMB] = "[panel_open ? "Close" : "Open"] maintenance panel"
			return CONTEXTUAL_SCREENTIP_SET
		if(TOOL_WRENCH)
			context[SCREENTIP_CONTEXT_LMB] = "Rotate"
			context[SCREENTIP_CONTEXT_RMB] = "[anchored ? "Unanchor" : "Anchor"]"
			return CONTEXTUAL_SCREENTIP_SET
		if(TOOL_CROWBAR)
			if(panel_open)
				context[SCREENTIP_CONTEXT_LMB] = "Deconstruct"
				return CONTEXTUAL_SCREENTIP_SET
	return NONE

/obj/machinery/overmap/fuel_injector/click_alt(mob/user)
	if(!can_flameout())
		return CLICK_ACTION_BLOCKING
	if(!do_after(user, 2 SECONDS, target = src))
		return CLICK_ACTION_BLOCKING
	do_flameout(user)
	return CLICK_ACTION_SUCCESS

/obj/machinery/overmap/fuel_injector/on_deconstruction(disassembled)
	if(fuel_tank)
		fuel_tank.forceMove(get_turf(src))
		fuel_tank = null
	if(air_contents?.total_moles())
		var/turf/local = get_turf(src)
		local?.assume_air(air_contents)
	return ..()
