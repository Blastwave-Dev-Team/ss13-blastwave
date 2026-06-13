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
