// MODULE ID: OVERMAP
// Hybrid propellant processor: any atmos mix, LINDA chemical burn + thermal expulsion.

/obj/machinery/overmap/fuel_injector
	name = "overmap fuel injector"
	desc = "Processes piped or tanked propellant for linked overmap thrusters."
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
	var/list/datum/weakref/linked_engines = list()

	var/obj/item/tank/fuel_tank
	var/chamber_volume = TANK_STANDARD_VOLUME
	var/max_moles = 0
	var/base_isp = 1
	var/micro_laser_rating = 1
	var/matter_bin_rating = 1
	var/burning = FALSE
	var/consuming = FALSE
	var/max_operating_pressure = OVERMAP_FUEL_DEFAULT_PRESSURE

/obj/machinery/overmap/fuel_injector/Initialize(mapload)
	. = ..()
	air_contents = new(chamber_volume)
	air_contents.set_temperature(T20C)
	recalculate_max_moles()
	input_connector = new(loc, src, dir, CELL_VOLUME * 0.5, PIPING_LAYER_MIN)
	exhaust_connector = new(loc, src, dir, CELL_VOLUME * 0.5, PIPING_LAYER_DEFAULT)
	if(mapload)
		fill_default_mix()
	update_adjacent_engines()
	RegisterSignal(src, COMSIG_ATOM_DIR_CHANGE, PROC_REF(on_dir_change))

/obj/machinery/overmap/fuel_injector/Destroy()
	QDEL_NULL(input_connector)
	QDEL_NULL(exhaust_connector)
	linked_engines.Cut()
	QDEL_NULL(air_contents)
	return ..()

/obj/machinery/overmap/fuel_injector/Moved(atom/old_loc, movement_dir, forced, list/old_locs, momentum_change)
	. = ..()
	update_adjacent_engines()

/obj/machinery/overmap/fuel_injector/proc/on_dir_change(datum/source, old_dir, new_dir)
	SIGNAL_HANDLER
	update_adjacent_engines()

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
	return air_contents?.total_moles() || 0

/obj/machinery/overmap/fuel_injector/proc/return_fuel_cap()
	return max_moles

/obj/machinery/overmap/fuel_injector/proc/has_propellant()
	return (air_contents?.total_moles() || 0) > 0.01

/obj/machinery/overmap/fuel_injector/proc/get_preheat_efficiency()
	return 1 + 0.1 * (micro_laser_rating - 1)

/obj/machinery/overmap/fuel_injector/proc/update_adjacent_engines()
	for(var/datum/weakref/engine_ref as anything in linked_engines)
		var/obj/machinery/power/shuttle_engine/overmap/engine = engine_ref?.resolve()
		if(engine)
			engine.clear_injector_link(src)
	linked_engines.Cut()
	for(var/direction in GLOB.cardinals)
		for(var/obj/machinery/power/shuttle_engine/overmap/engine in get_step(get_turf(src), direction))
			if(engine.dir != dir)
				continue
			engine.set_linked_injector(src)
			linked_engines += WEAKREF(engine)

/obj/machinery/overmap/fuel_injector/process_atmos()
	if(!is_operational || !air_contents)
		return
	process_intake()
	process_exhaust_filter()

/obj/machinery/overmap/fuel_injector/proc/process_intake()
	var/datum/pipeline/pipe = input_connector?.gas_connector?.parents?[1]
	if(!pipe?.air)
		return
	if(air_contents.return_pressure() >= max_operating_pressure)
		return
	var/transfer_ratio = min(MAX_TRANSFER_RATE / max(air_contents.volume, 1), 0.25)
	var/datum/gas_mixture/removed = pipe.air.remove_ratio(transfer_ratio)
	if(!removed?.total_moles())
		return
	air_contents.merge(removed)
	input_connector.gas_connector.update_parents()

/obj/machinery/overmap/fuel_injector/proc/process_exhaust_filter()
	var/datum/pipeline/exhaust_pipe = exhaust_connector?.gas_connector?.parents?[1]
	if(!exhaust_pipe?.air)
		return
	if(exhaust_pipe.air.return_pressure() >= MAX_OUTPUT_PRESSURE)
		return
	var/datum/gas_mixture/scrubbed = new(CELL_VOLUME)
	var/remaining_transfer = MAX_TRANSFER_RATE * 0.1
	for(var/gas_id in air_contents.gases)
		if(!overmap_should_scrub_gas(gas_id))
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

/obj/machinery/overmap/fuel_injector/proc/consume_for_burn(requested_moles, power_fraction)
	if(!requested_moles || !has_propellant())
		return list(0, 0)
	consuming = TRUE
	var/list/before_moles = list()
	for(var/gas_id in air_contents.gases)
		before_moles[gas_id] = air_contents.gases[gas_id][MOLES]

	if(air_contents.temperature < PLASMA_MINIMUM_BURN_TEMPERATURE)
		apply_preheat()

	var/chemical_bonus = 1
	var/reacted = FALSE
	for(var/i in 1 to OVERMAP_REACT_ITERATIONS)
		if(!air_contents.react(src))
			break
		reacted = TRUE
	if(reacted)
		chemical_bonus = OVERMAP_CHEMICAL_ISP_BONUS

	var/n_consumed = 0
	for(var/gas_id in before_moles)
		var/current = air_contents.has_gas(gas_id) ? air_contents.gases[gas_id][MOLES] : 0
		var/lost = before_moles[gas_id] - current
		if(lost > 0)
			n_consumed += lost
	n_consumed = min(n_consumed, requested_moles)

	var/n_thermal = max(0, requested_moles - n_consumed)
	if(n_thermal > 0)
		n_consumed += remove_thermal_moles(n_thermal, power_fraction)

	var/burn_fraction = min(n_consumed / requested_moles, 1)
	var/datum/gas_mixture/expelled = new(CELL_VOLUME)
	for(var/gas_id in before_moles)
		var/current = air_contents.has_gas(gas_id) ? air_contents.gases[gas_id][MOLES] : 0
		var/lost = before_moles[gas_id] - current
		if(lost > 0)
			expelled.adjust_gas(gas_id, lost)

	var/effective_isp = base_isp * clamp(power_fraction, 0, 1) * overmap_gas_isp_multiplier(expelled) * chemical_bonus
	consuming = FALSE
	burning = burn_fraction > 0
	update_appearance()
	return list(burn_fraction, effective_isp)

/obj/machinery/overmap/fuel_injector/proc/apply_preheat()
	var/target = PLASMA_MINIMUM_BURN_TEMPERATURE
	if(air_contents.temperature >= target)
		return
	var/cp = air_contents.heat_capacity()
	if(cp <= 0)
		return
	var/energy = cp * (target - air_contents.temperature)
	use_energy(energy / get_preheat_efficiency())
	air_contents.set_temperature(target)

/obj/machinery/overmap/fuel_injector/proc/remove_thermal_moles(amount, power_fraction)
	if(amount <= 0 || !air_contents.total_moles())
		return 0
	var/total = air_contents.total_moles()
	var/to_remove = min(amount, total)
	var/target_temp = min(OVERMAP_THERMAL_EXHAUST_TEMP, air_contents.temperature + 200)
	var/cp = air_contents.heat_capacity()
	if(cp > 0)
		var/energy = cp * max(target_temp - air_contents.temperature, 0) * (to_remove / total)
		use_energy(energy * clamp(power_fraction, 0.1, 1))
		air_contents.set_temperature(target_temp)
	var/datum/gas_mixture/removed = air_contents.remove(to_remove)
	return removed?.total_moles() || 0

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

/obj/machinery/overmap/fuel_injector/proc/do_flameout(mob/user)
	if(!can_flameout())
		balloon_alert(user, "linked engines must be off!")
		return
	var/turf/release_turf = get_step(src, dir)
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

/obj/machinery/overmap/fuel_injector/examine(mob/user)
	. = ..()
	. += span_notice("Fuel input: piping layer [PIPING_LAYER_MIN]. Exhaust filter: piping layer [PIPING_LAYER_DEFAULT].")
	if(!can_flameout())
		. += span_notice("Linked engine must be off before flameout.")
	else
		. += span_notice("Alt-click to dump the chamber (flameout) when engines are off.")
	if(air_contents?.total_moles())
		. += span_notice("Chamber: [round(air_contents.total_moles(), 0.1)] mol, [round(air_contents.return_pressure(), 0.1)] kPa, [round(air_contents.temperature, 0.1)] K.")

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
