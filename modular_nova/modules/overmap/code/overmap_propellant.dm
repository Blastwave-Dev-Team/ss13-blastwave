// MODULE ID: OVERMAP
// Propellant ISP lookup and exhaust-filter helpers for the fuel injector.

GLOBAL_LIST_INIT(overmap_propellant_isp, list(
	/datum/gas/nitrogen = 1.00,
	/datum/gas/oxygen = 0.90,
	/datum/gas/plasma = 0.70,
	/datum/gas/carbon_dioxide = 0.75,
	/datum/gas/water_vapor = 1.10,
	/datum/gas/hydrogen = 3.50,
	/datum/gas/helium = 2.50,
	/datum/gas/tritium = 2.00,
	/datum/gas/nitrium = 1.40,
	/datum/gas/pluoxium = 0.85,
	/datum/gas/freon = 0.50,
	/datum/gas/hypernoblium = 0.00,
	/datum/gas/bz = 0.00,
	/datum/gas/miasma = 0.00,
	/datum/gas/halon = 0.00,
	/datum/gas/antinoblium = 0.00,
))

/// Approximate molar mass (g/mol) for sqrt(28/MW) ISP fallback.
/proc/overmap_gas_effective_mw(gas_id)
	var/static/list/mw_lut = list(
		/datum/gas/nitrogen = 28,
		/datum/gas/oxygen = 32,
		/datum/gas/plasma = 40,
		/datum/gas/carbon_dioxide = 44,
		/datum/gas/water_vapor = 18,
		/datum/gas/hydrogen = 2,
		/datum/gas/helium = 4,
		/datum/gas/tritium = 3,
	)
	if(gas_id in mw_lut)
		return mw_lut[gas_id]
	return 28

/proc/overmap_gas_isp_mult(gas_id)
	var/mult = GLOB.overmap_propellant_isp[gas_id]
	if(isnull(mult))
		mult = sqrt(28 / overmap_gas_effective_mw(gas_id))
	return mult

/proc/overmap_should_scrub_gas(gas_id)
	return overmap_gas_isp_mult(gas_id) <= OVERMAP_EXHAUST_ISP_THRESHOLD

/proc/overmap_gas_isp_multiplier(datum/gas_mixture/mix)
	if(!mix || !mix.total_moles())
		return 1
	var/weighted = 0
	var/total = 0
	for(var/gas_id in mix.gases)
		var/list/gas_data = mix.gases[gas_id]
		var/moles = gas_data[MOLES]
		if(moles <= 0)
			continue
		weighted += moles * overmap_gas_isp_mult(gas_id)
		total += moles
	return total > 0 ? weighted / total : 1

/proc/init_fuel_injector_filter_defaults(obj/machinery/overmap/fuel_injector/injector)
	if(!injector)
		return
	injector.intake_filter = list()
	injector.scrub_filter = list()
	for(var/gas_path in GLOB.meta_gas_info)
		var/isp = overmap_gas_isp_mult(gas_path)
		injector.intake_filter[gas_path] = isp > 0
		injector.scrub_filter[gas_path] = isp <= OVERMAP_EXHAUST_ISP_THRESHOLD
	injector.scrub_filter[/datum/gas/carbon_dioxide] = TRUE

/proc/apply_fuel_injector_filter_preset(obj/machinery/overmap/fuel_injector/injector, preset_id)
	if(!injector)
		return
	switch(preset_id)
		if("intake_propellants")
			for(var/gas_path in GLOB.meta_gas_info)
				injector.intake_filter[gas_path] = overmap_gas_isp_mult(gas_path) >= 0.70
		if("intake_all")
			for(var/gas_path in GLOB.meta_gas_info)
				injector.intake_filter[gas_path] = TRUE
		if("scrub_auto")
			for(var/gas_path in GLOB.meta_gas_info)
				injector.scrub_filter[gas_path] = overmap_gas_isp_mult(gas_path) <= OVERMAP_EXHAUST_ISP_THRESHOLD
			injector.scrub_filter[/datum/gas/carbon_dioxide] = TRUE
		if("scrub_burn_products")
			for(var/gas_path in GLOB.meta_gas_info)
				injector.scrub_filter[gas_path] = FALSE
			injector.scrub_filter[/datum/gas/carbon_dioxide] = TRUE
			injector.scrub_filter[/datum/gas/water_vapor] = TRUE
			injector.scrub_filter[/datum/gas/nitrogen] = TRUE

/proc/fuel_injector_filter_entries(list/filter_map)
	var/list/entries = list()
	for(var/gas_path in GLOB.meta_gas_info)
		var/list/gas = GLOB.meta_gas_info[gas_path]
		entries += list(list(
			"gasId" = gas[META_GAS_ID],
			"gasName" = gas[META_GAS_NAME],
			"enabled" = filter_map[gas_path] ? TRUE : FALSE,
		))
	return entries

/proc/gas_mixture_mole_count(datum/gas_mixture/mix, gas_id)
	if(!mix?.gases[gas_id])
		return 0
	return mix.gases[gas_id][MOLES]

/proc/fuel_injector_gas_composition(datum/gas_mixture/mix)
	var/list/composition = list()
	for(var/gas_path in GLOB.meta_gas_info)
		var/list/gas = GLOB.meta_gas_info[gas_path]
		composition[gas[META_GAS_ID]] = 0
	if(!mix)
		return composition
	var/total = mix.total_moles()
	if(total <= 0)
		return composition
	for(var/gas_path in GLOB.meta_gas_info)
		var/list/gas = GLOB.meta_gas_info[gas_path]
		composition[gas[META_GAS_ID]] = gas_mixture_mole_count(mix, gas_path) / total
	return composition

/proc/fuel_injector_intake_rejection_ratio(datum/gas_mixture/mix, list/intake_filter)
	if(!mix?.total_moles())
		return 0
	var/allowed = 0
	for(var/gas_id in mix.gases)
		if(intake_filter[gas_id])
			allowed += mix.gases[gas_id][MOLES]
	return 1 - (allowed / mix.total_moles())

/proc/fuel_injector_scrub_eligible_ratio(datum/gas_mixture/mix, list/scrub_filter)
	if(!mix?.total_moles())
		return 0
	var/scrubbed = 0
	for(var/gas_id in mix.gases)
		if(scrub_filter[gas_id])
			scrubbed += mix.gases[gas_id][MOLES]
	return scrubbed / mix.total_moles()

/proc/fuel_injector_estimate_chemical_bonus(datum/gas_mixture/mix)
	if(!mix?.total_moles() || mix.temperature < PLASMA_MINIMUM_BURN_TEMPERATURE)
		return 1
	var/total = mix.total_moles()
	var/plasma_frac = gas_mixture_mole_count(mix, /datum/gas/plasma) / total
	var/oxygen_frac = gas_mixture_mole_count(mix, /datum/gas/oxygen) / total
	if(plasma_frac > 0.05 && oxygen_frac > 0.05)
		return OVERMAP_CHEMICAL_ISP_BONUS
	return 1

/proc/overmap_hnt_feed_pipeline(datum/gas_machine_connector/feed_connector)
	return feed_connector?.gas_connector?.parents?[1]

/proc/overmap_engine_propellant_share_moles(thrust, power_fraction, burn_pct)
	var/denom = OVERMAP_G0 * OVERMAP_PROP_MOLES_PER_THRUST
	if(denom <= 0)
		return 0
	return (thrust * clamp(power_fraction, 0, 1) * (burn_pct / 100)) / denom

/proc/fuel_injector_count_active_share_engines(obj/machinery/overmap/fuel_injector/injector)
	if(!injector)
		return 0
	var/count = 0
	for(var/datum/weakref/engine_ref as anything in injector.linked_engines)
		var/obj/machinery/power/shuttle_engine/overmap/engine = engine_ref?.resolve()
		if(!engine || engine.get_linked_injector() != injector)
			continue
		if(!engine.enabled || !engine.thruster_active)
			continue
		count++
	return count

/proc/fuel_injector_manifold_share_stats(obj/machinery/overmap/fuel_injector/injector, burn_pct = 100)
	var/list/stats = list(
		"piped_engines" = 0,
		"adjacent_engines" = 0,
		"active_share_count" = 0,
		"per_engine_moles" = 0,
		"total_tick_moles" = 0,
		"feed_connected" = FALSE,
	)
	if(!injector)
		return stats
	stats["feed_connected"] = !!overmap_hnt_feed_pipeline(injector.feed_connector)
	for(var/datum/weakref/engine_ref as anything in injector.linked_engines)
		var/obj/machinery/power/shuttle_engine/overmap/engine = engine_ref?.resolve()
		if(!engine)
			continue
		if(engine.link_via_pipe)
			stats["piped_engines"]++
		else
			stats["adjacent_engines"]++
		if(!engine.enabled || !engine.thruster_active)
			continue
		stats["active_share_count"]++
		var/m_i = overmap_engine_propellant_share_moles(engine.thrust, engine.get_power_fraction(), burn_pct)
		stats["total_tick_moles"] += m_i
		if(!stats["per_engine_moles"] && m_i > 0)
			stats["per_engine_moles"] = m_i
	if(stats["active_share_count"] > 1 && stats["per_engine_moles"])
		stats["per_engine_moles"] = stats["total_tick_moles"] / stats["active_share_count"]
	return stats

/proc/fuel_injector_estimate_power_fraction(obj/machinery/overmap/fuel_injector/injector)
	if(!length(injector?.linked_engines))
		return 1
	var/total = 0
	var/count = 0
	for(var/datum/weakref/engine_ref as anything in injector.linked_engines)
		var/obj/machinery/power/shuttle_engine/overmap/engine = engine_ref?.resolve()
		if(!engine || !engine.enabled || !engine.thruster_active)
			continue
		total += engine.get_power_fraction()
		count++
	return count ? total / count : 1

/proc/fuel_injector_estimate_isp(obj/machinery/overmap/fuel_injector/injector)
	if(!injector)
		return 0
	// Prefer L2 feed; fall back to chamber. Empty feed mix is non-null — check moles.
	var/datum/gas_mixture/mix = injector.get_feed_air()
	if(!mix?.total_moles())
		mix = injector.air_contents
	if(!mix?.total_moles())
		return 0
	var/gas_multiplier = overmap_gas_isp_multiplier(mix)
	var/chemical_bonus = fuel_injector_estimate_chemical_bonus(mix)
	return injector.base_isp * gas_multiplier * chemical_bonus

/proc/fuel_injector_estimate_delta_v(obj/machinery/overmap/fuel_injector/injector, ship_mass)
	if(!ship_mass || !injector?.has_propellant())
		return 0
	var/isp = fuel_injector_estimate_isp(injector)
	if(isp <= 0)
		return 0
	var/propellant = injector.get_stored_propellant_moles() / OVERMAP_PROP_MOLES_PER_THRUST
	if(propellant <= 0)
		return 0
	return isp * OVERMAP_G0 * log((ship_mass + propellant) / ship_mass)

/proc/fuel_injector_derive_chamber_status(obj/machinery/overmap/fuel_injector/injector)
	var/list/pills = list()
	if(!injector?.air_contents)
		return pills

	var/reaction_active = injector.burning || injector.consuming
	if(!reaction_active && injector.air_contents.total_moles() > 0 && injector.air_contents.temperature >= PLASMA_MINIMUM_BURN_TEMPERATURE)
		var/total = injector.air_contents.total_moles()
		var/plasma_frac = gas_mixture_mole_count(injector.air_contents, /datum/gas/plasma) / total
		var/oxygen_frac = gas_mixture_mole_count(injector.air_contents, /datum/gas/oxygen) / total
		if(plasma_frac > 0.05 && oxygen_frac > 0.05)
			reaction_active = TRUE

	if(reaction_active)
		pills += "Reaction Active"
	else if(injector.has_propellant())
		pills += "Thermal Only"

	if(injector.return_chamber_pressure() > injector.max_operating_pressure)
		pills += "Pressure Relief"
	else if(injector.return_chamber_pressure() >= injector.max_operating_pressure * 0.95)
		var/scrub_ratio = fuel_injector_scrub_eligible_ratio(injector.air_contents, injector.scrub_filter)
		if(scrub_ratio < 0.05)
			pills += "Scrub Stalled"

	var/datum/pipeline/exhaust_pipe = injector.exhaust_connector?.gas_connector?.parents?[1]
	if(exhaust_pipe?.air?.return_pressure() >= MAX_OUTPUT_PRESSURE)
		pills += "Exhaust Blocked"

	return pills

/proc/overmap_propellant_gas_data()
	var/list/data = list()
	for(var/gas_path in GLOB.meta_gas_info)
		var/list/gas = GLOB.meta_gas_info[gas_path]
		var/isp = overmap_gas_isp_mult(gas_path)
		data[gas[META_GAS_ID]] = list(
			"isp_mult" = isp,
			"scrub_default" = isp <= OVERMAP_EXHAUST_ISP_THRESHOLD,
		)
	return data

/proc/fuel_injector_pipeline_ui_data(datum/gas_machine_connector/connector, max_moles_override = 0)
	var/list/data = list(
		"connected" = FALSE,
		"pressure" = 0,
		"temperature" = 0,
		"total_moles" = 0,
		"max_moles" = max_moles_override,
		"gas_composition" = list(),
	)
	var/datum/pipeline/pipe = connector?.gas_connector?.parents?[1]
	if(!pipe?.air)
		return data
	data["connected"] = TRUE
	data["pressure"] = round(pipe.air.return_pressure(), 0.1)
	data["temperature"] = round(pipe.air.temperature, 0.1)
	data["total_moles"] = round(pipe.air.total_moles(), 0.1)
	data["gas_composition"] = fuel_injector_gas_composition(pipe.air)
	return data
