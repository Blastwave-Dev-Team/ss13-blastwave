// MODULE ID: OVERMAP
// Continuous L2 propellant feed: chamber → scrub → L2 push; engines pull from L2.
// Layout (injector facing SOUTH):
//
//   [fuel can+L1 connector]  [injector]  .  .
//            W                  C
//   [L1 pipe SW] [L1+L2+L3 S] [L3 volpump E] [exhaust can+L3 connector]
//                     |
//                [HNT engine S]

#define OVERMAP_FUEL_TEST_TICKS 40
#define OVERMAP_FUEL_TEST_PRESSURE 3500 // kPa, > 3000 as requested
#define OVERMAP_FUEL_TEST_FEED_MOLES 100
#define OVERMAP_FUEL_TEST_THRUST_TOLERANCE 0.05

/datum/unit_test/overmap_fuel_injector
	abstract_type = /datum/unit_test/overmap_fuel_injector
	priority = TEST_LONGER

/datum/unit_test/overmap_fuel_injector/Destroy()
	// Docking ports soft-qdel with QDEL_HINT_LETMELIVE. Force-delete any still
	// alive in allocated before the parent turf sweep soft-qdels them again.
	// Copy: deleting while iterating allocated can skip later ports.
	for(var/obj/docking_port/port in allocated.Copy())
		if(!QDELETED(port))
			qdel(port, force = TRUE)
	return ..()

/datum/unit_test/overmap_fuel_injector/proc/flush_atmos_rebuilds()
	// Unit tests can trip MC_TICK_CHECK inside process_rebuilds and leave pipes
	// without parents. Mirror SSair.setup_pipenets with blocking builds instead.
	var/safety = 200
	while(safety-- > 0 && length(SSair.rebuild_queue))
		var/obj/machinery/atmospherics/remake = SSair.rebuild_queue[SSair.rebuild_queue.len]
		SSair.rebuild_queue.len--
		if(QDELETED(remake))
			continue
		remake.rebuilding = FALSE
		for(var/datum/pipeline/build_off as anything in remake.get_rebuild_targets())
			build_off.build_pipeline_blocking(remake)
	SSair.expansion_queue.Cut()

/datum/unit_test/overmap_fuel_injector/proc/init_atmos_devices(list/obj/machinery/atmospherics/devices)
	for(var/obj/machinery/atmospherics/device as anything in devices)
		if(QDELETED(device))
			continue
		device.atmos_init()
		SSair.add_to_rebuild_queue(device)
	flush_atmos_rebuilds()

/datum/unit_test/overmap_fuel_injector/proc/format_mix(datum/gas_mixture/mix)
	if(!mix)
		return "null"
	var/list/parts = list()
	for(var/gas_path in mix.gases)
		var/moles = mix.gases[gas_path][MOLES]
		if(moles <= 0.001)
			continue
		var/list/meta = GLOB.meta_gas_info[gas_path]
		parts += "[meta ? meta[META_GAS_ID] : gas_path]=[round(moles, 0.01)]"
	return "P=[round(mix.return_pressure(), 0.1)]kPa T=[round(mix.temperature, 0.1)]K n=[round(mix.total_moles(), 0.01)] {[parts.Join(", ")]}"

/datum/unit_test/overmap_fuel_injector/proc/pipeline_air(datum/gas_machine_connector/connector) as /datum/gas_mixture
	return connector?.gas_connector?.parents?[1]?.air

/datum/unit_test/overmap_fuel_injector/proc/fill_canister_mix(obj/machinery/portable_atmospherics/canister/canister, plasma_frac, oxygen_frac, pressure_kpa, temperature = T20C)
	var/total_moles = (pressure_kpa * canister.air_contents.volume) / (R_IDEAL_GAS_EQUATION * temperature)
	canister.air_contents.set_temperature(temperature)
	canister.air_contents.remove(canister.air_contents.total_moles())
	canister.air_contents.adjust_gas(/datum/gas/plasma, total_moles * plasma_frac)
	canister.air_contents.adjust_gas(/datum/gas/oxygen, total_moles * oxygen_frac)

/// Area APC + infinite megacell + cable run so the HNT sits on a live powernet.
/// Returns the APC; call refresh_grid_power() before burns (SSmachines clears avail).
/datum/unit_test/overmap_fuel_injector/proc/setup_engine_grid_power(obj/machinery/power/shuttle_engine/overmap/engine, list/turf/cable_turfs)
	var/turf/apc_turf = cable_turfs[1]
	var/area/test_area = apc_turf.loc
	TEST_ASSERT(istype(test_area), "Expected an area on the APC turf.")

	var/obj/machinery/power/apc/apc = allocate(/obj/machinery/power/apc, apc_turf)
	apc.has_electronics = APC_ELECTRONICS_SECURED
	apc.opened = APC_COVER_CLOSED
	apc.set_machine_stat(apc.machine_stat & ~MAINT)
	apc.operating = TRUE
	apc.equipment = APC_CHANNEL_AUTO_ON
	apc.lighting = APC_CHANNEL_AUTO_ON
	apc.environ = APC_CHANNEL_AUTO_ON
	QDEL_NULL(apc.cell)
	apc.cell = allocate(/obj/item/stock_parts/power_store/battery/infinite, apc)
	apc.cell_type = /obj/item/stock_parts/power_store/battery/infinite
	apc.make_terminal()
	apc.update()
	apc.update_area_power_usage(TRUE)

	for(var/turf/cable_turf as anything in cable_turfs)
		var/obj/structure/cable/existing = cable_turf.get_cable_node(CABLE_LAYER_2)
		if(!existing)
			allocate(/obj/structure/cable, cable_turf)

	// allocate() skips cable-coil place_turf(), so build/merge powernets by hand.
	for(var/turf/cable_turf as anything in cable_turfs)
		var/obj/structure/cable/wire = cable_turf.get_cable_node(CABLE_LAYER_2)
		if(!wire)
			continue
		wire.connect_cable(TRUE)
		if(!wire.powernet)
			var/datum/powernet/new_net = new /datum/powernet()
			new_net.add_cable(wire)
		for(var/direction in GLOB.cardinals)
			wire.mergeConnectedNetworks(direction)
		wire.mergeConnectedNetworksOnTurf()

	apc.terminal.connect_to_network()
	TEST_ASSERT(engine.connect_to_network(), "HNT engine failed to connect to the APC cable powernet.")
	TEST_ASSERT(engine.powernet, "HNT engine has no powernet after connect_to_network.")
	TEST_ASSERT(apc.terminal.powernet == engine.powernet, "APC terminal and engine should share one powernet.")

	engine.enabled = TRUE
	// refresh before update_engine: HNT stays thruster_active only when
	// propellant OR get_power_fraction() > 0, and avail starts at 0.
	refresh_grid_power(apc)
	TEST_ASSERT(engine.update_engine(), "HNT engine failed to activate after grid power setup.")
	TEST_ASSERT(engine.thruster_active, "HNT thruster_active should be TRUE after grid power setup.")
	TEST_ASSERT(engine.get_power_fraction() > 0, "Engine power fraction should be > 0 after grid setup (got [engine.get_power_fraction()]).")
	return apc

/// Top up grid avail from the APC cell. Powernet.avail is wiped by power processing.
/datum/unit_test/overmap_fuel_injector/proc/refresh_grid_power(obj/machinery/power/apc/apc)
	if(QDELETED(apc?.terminal?.powernet) || QDELETED(apc.cell))
		return
	// Infinite megacell: keep a generous surplus for HNT max_power_draw.
	apc.terminal.powernet.avail = max(apc.terminal.powernet.avail, 500 KILO JOULES)
	apc.terminal.powernet.load = 0

/// Expected single-engine thrust for a known L2 mix at full power (mirrors process_tick_burn).
/datum/unit_test/overmap_fuel_injector/proc/expected_feed_thrust(obj/machinery/overmap/fuel_injector/injector, obj/machinery/power/shuttle_engine/overmap/engine, datum/gas_mixture/feed_sample, feed_moles, burn_pct = 100, power_fraction = 1)
	var/gas_mult = overmap_gas_isp_multiplier(feed_sample)
	var/chem_bonus = fuel_injector_estimate_chemical_bonus(feed_sample)
	var/effective_isp = injector.base_isp * gas_mult * chem_bonus
	if(effective_isp <= 0)
		return 0
	var/requested = overmap_engine_propellant_share_moles(engine.thrust, power_fraction, burn_pct)
	if(requested <= 0)
		return 0
	var/burn_fraction = min(feed_moles / requested, 1)
	return engine.thrust * power_fraction * effective_isp * burn_fraction * (burn_pct / 100)

/datum/unit_test/overmap_fuel_injector/proc/assert_thrust_near(actual, expected, label)
	var/delta = abs(actual - expected)
	var/limit = max(OVERMAP_FUEL_TEST_THRUST_TOLERANCE, abs(expected) * 0.02)
	TEST_ASSERT(delta <= limit, "[label]: thrust=[round(actual, 0.001)] expected=[round(expected, 0.001)] (Δ=[round(delta, 0.001)]).")

/// Replace L2 pipeline contents with an exact mix (moles + temperature).
/datum/unit_test/overmap_fuel_injector/proc/set_feed_mix(obj/machinery/overmap/fuel_injector/injector, list/gas_fractions, temperature, total_moles = OVERMAP_FUEL_TEST_FEED_MOLES)
	var/datum/gas_mixture/feed_air = pipeline_air(injector.feed_connector)
	TEST_ASSERT(feed_air, "L2 feed pipeline air missing.")
	feed_air.remove(feed_air.total_moles())
	feed_air.set_temperature(temperature)
	for(var/gas_path in gas_fractions)
		feed_air.adjust_gas(gas_path, total_moles * gas_fractions[gas_path])
	injector.feed_connector.gas_connector.update_parents()
	return feed_air

/// Minimal L2 injector ↔ HNT layout plus mobile port + simulated ship (FLYING).
/// Returns assoc: injector, engine, apc, port, ship, turfs used for cables.
/datum/unit_test/overmap_fuel_injector/proc/build_ship_thrust_fixture()
	var/turf/injector_turf = locate(
		run_loc_floor_bottom_left.x + 1,
		run_loc_floor_bottom_left.y + 2,
		run_loc_floor_bottom_left.z,
	)
	TEST_ASSERT(injector_turf, "Failed to locate injector turf inside the unit test room.")
	var/turf/south_turf = get_step(injector_turf, SOUTH)
	var/turf/engine_turf = get_step(south_turf, SOUTH)
	for(var/turf/needed as anything in list(south_turf, engine_turf))
		TEST_ASSERT(isfloorturf(needed), "Expected floor turf at [needed?.x],[needed?.y] for ship thrust fixture.")

	var/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer2/feed_pipe = allocate(/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer2, south_turf)

	var/obj/machinery/overmap/fuel_injector/injector = allocate(/obj/machinery/overmap/fuel_injector, injector_turf)
	injector.setDir(SOUTH)
	injector.use_power = NO_POWER_USE
	injector.preheat_enabled = FALSE

	var/obj/machinery/power/shuttle_engine/overmap/standard/engine = allocate(/obj/machinery/power/shuttle_engine/overmap/standard, engine_turf)
	engine.setDir(SOUTH)
	engine.use_power = NO_POWER_USE

	var/obj/machinery/power/apc/grid_apc = setup_engine_grid_power(engine, list(injector_turf, south_turf, engine_turf))

	init_atmos_devices(list(
		feed_pipe,
		injector.feed_connector.gas_connector,
		engine.feed_connector.gas_connector,
	))

	TEST_ASSERT(overmap_hnt_feed_pipeline(injector.feed_connector) == overmap_hnt_feed_pipeline(engine.feed_connector), "Injector and HNT engine should share the L2 feed pipeline.")

	engine.scan_for_injector()
	TEST_ASSERT(engine.get_linked_injector() == injector, "HNT engine failed to link to the fuel injector.")

	var/area/hull_area = get_area(injector_turf)
	var/obj/docking_port/mobile/port = allocate(/obj/docking_port/mobile, injector_turf, list(hull_area))
	port.name = "Fuel Mix Test Shuttle"
	port.shuttle_id = "overmap_fuel_mix_test"
	port.width = 3
	port.height = 3
	port.dwidth = 1
	port.dheight = 1
	engine.connect_to_shuttle(FALSE, port)
	TEST_ASSERT(engine in port.engine_list, "HNT should be registered on the mobile port engine_list.")

	// Test Z is not an overmap/reserved level, so setup_shuttle_ship() no-ops.
	var/obj/structure/overmap/ship/simulated/ship = allocate(/obj/structure/overmap/ship/simulated, injector_turf, port.shuttle_id, port)
	port.current_ship = ship
	ship.state = OVERMAP_SHIP_FLYING
	ship.calculate_mass()
	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.update_engine(), "HNT should activate on the simulated ship fixture.")
	ship.refresh_engines()

	return list(
		"injector" = injector,
		"engine" = engine,
		"apc" = grid_apc,
		"port" = port,
		"ship" = ship,
	)

/// Docking ports soft-qdel with QDEL_HINT_LETMELIVE; force-delete so later
/// unit-test turf sweeps don't keep hitting a zombie port.
/datum/unit_test/overmap_fuel_injector/proc/teardown_ship_thrust_fixture(list/fixture)
	var/obj/structure/overmap/ship/simulated/ship = fixture["ship"]
	var/obj/docking_port/mobile/port = fixture["port"]
	if(!QDELETED(ship))
		if(port?.current_ship == ship)
			port.current_ship = null
		ship.shuttle = null
		qdel(ship)
	if(!QDELETED(port))
		qdel(port, force = TRUE)

// ---------------------------------------------------------------------------
// Full L1→chamber→L2 burn cycle (integration)
// ---------------------------------------------------------------------------

/datum/unit_test/overmap_fuel_injector/burn_cycle

/datum/unit_test/overmap_fuel_injector/burn_cycle/Run()
	var/turf/injector_turf = locate(
		run_loc_floor_bottom_left.x + 1,
		run_loc_floor_bottom_left.y + 2,
		run_loc_floor_bottom_left.z,
	)
	TEST_ASSERT(injector_turf, "Failed to locate injector turf inside the unit test room.")
	var/turf/west_turf = get_step(injector_turf, WEST)
	var/turf/south_turf = get_step(injector_turf, SOUTH)
	var/turf/southwest_turf = get_step(south_turf, WEST)
	var/turf/engine_turf = get_step(south_turf, SOUTH)
	var/turf/pump_turf = get_step(south_turf, EAST)
	var/turf/exhaust_turf = get_step(pump_turf, EAST)
	for(var/turf/needed as anything in list(west_turf, south_turf, southwest_turf, engine_turf, pump_turf, exhaust_turf))
		TEST_ASSERT(isfloorturf(needed), "Expected floor turf at [needed?.x],[needed?.y] for fuel injector layout.")

	var/obj/machinery/atmospherics/components/unary/portables_connector/fuel_port = allocate(/obj/machinery/atmospherics/components/unary/portables_connector, west_turf)
	fuel_port.setDir(SOUTH)
	fuel_port.set_init_directions()
	fuel_port.set_piping_layer(PIPING_LAYER_MIN)

	var/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer1/fuel_pipe_south = allocate(/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer1, south_turf)
	var/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer1/fuel_pipe_sw = allocate(/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer1, southwest_turf)

	var/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer2/feed_pipe = allocate(/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer2, south_turf)

	var/obj/machinery/atmospherics/pipe/smart/simple/general/visible/exhaust_pipe = allocate(/obj/machinery/atmospherics/pipe/smart/simple/general/visible, south_turf)
	var/obj/machinery/atmospherics/components/binary/volume_pump/on/exhaust_pump = allocate(/obj/machinery/atmospherics/components/binary/volume_pump/on, pump_turf)
	exhaust_pump.setDir(EAST)
	exhaust_pump.set_init_directions()
	exhaust_pump.set_piping_layer(PIPING_LAYER_DEFAULT)
	exhaust_pump.use_power = NO_POWER_USE

	var/obj/machinery/atmospherics/components/unary/portables_connector/exhaust_port = allocate(/obj/machinery/atmospherics/components/unary/portables_connector, exhaust_turf)
	exhaust_port.setDir(WEST)
	exhaust_port.set_init_directions()
	exhaust_port.set_piping_layer(PIPING_LAYER_DEFAULT)

	var/obj/machinery/overmap/fuel_injector/injector = allocate(/obj/machinery/overmap/fuel_injector, injector_turf)
	injector.setDir(SOUTH)
	injector.use_power = NO_POWER_USE
	injector.preheat_enabled = FALSE
	injector.preheat_setpoint = 500

	var/obj/machinery/power/shuttle_engine/overmap/standard/engine = allocate(/obj/machinery/power/shuttle_engine/overmap/standard, engine_turf)
	engine.setDir(SOUTH)
	engine.use_power = NO_POWER_USE

	var/obj/machinery/power/apc/grid_apc = setup_engine_grid_power(engine, list(injector_turf, south_turf, engine_turf))
	log_test("GRID power_fraction=[engine.get_power_fraction()] avail=[engine.powernet.avail]")

	var/list/atmos_devices = list(
		fuel_port,
		fuel_pipe_south,
		fuel_pipe_sw,
		feed_pipe,
		exhaust_pipe,
		exhaust_pump,
		exhaust_port,
		injector.input_connector.gas_connector,
		injector.feed_connector.gas_connector,
		injector.exhaust_connector.gas_connector,
		engine.feed_connector.gas_connector,
	)
	init_atmos_devices(atmos_devices)

	TEST_ASSERT(injector.input_connector.gas_connector.parents?[1], "Injector L1 input failed to join a pipenet.")
	TEST_ASSERT(injector.feed_connector.gas_connector.parents?[1], "Injector L2 feed failed to join a pipenet.")
	TEST_ASSERT(injector.exhaust_connector.gas_connector.parents?[1], "Injector L3 exhaust failed to join a pipenet.")
	TEST_ASSERT(overmap_hnt_feed_pipeline(injector.feed_connector) == overmap_hnt_feed_pipeline(engine.feed_connector), "Injector and HNT engine should share the L2 feed pipeline.")

	engine.scan_for_injector()
	TEST_ASSERT(engine.get_linked_injector() == injector, "HNT engine failed to link to the fuel injector via L2 / area scan.")
	TEST_ASSERT(engine.link_via_pipe, "HNT engine should report a piped injector link.")

	var/obj/machinery/portable_atmospherics/canister/fuel_can = allocate(/obj/machinery/portable_atmospherics/canister, west_turf)
	fill_canister_mix(fuel_can, 0.9, 0.1, OVERMAP_FUEL_TEST_PRESSURE, T20C)
	TEST_ASSERT(fuel_can.air_contents.return_pressure() > 3000, "Fuel canister pressure should exceed 3000 kPa before connect.")
	TEST_ASSERT(fuel_can.connect(fuel_port), "Fuel canister failed to connect to the L1 port.")

	var/obj/machinery/portable_atmospherics/canister/exhaust_can = allocate(/obj/machinery/portable_atmospherics/canister, exhaust_turf)
	TEST_ASSERT(exhaust_can.connect(exhaust_port), "Exhaust canister failed to connect to the L3 port.")

	var/warmup_ticks = 0
	while(warmup_ticks++ < 20 && injector.air_contents.total_moles() < 1)
		injector.process_atmos(0.5)
		fuel_port.process_atmos()

	TEST_ASSERT(injector.air_contents.total_moles() > 0.1, "Injector chamber did not intake fuel from the L1 canister.")
	log_test("POST-INTAKE chamber: [format_mix(injector.air_contents)]")
	log_test("POST-INTAKE L2 feed: [format_mix(pipeline_air(injector.feed_connector))]")

	injector.preheat_enabled = TRUE
	injector.preheat_setpoint = 500
	var/preheat_ticks = 0
	while(preheat_ticks++ < 200 && injector.air_contents.temperature < 500)
		injector.process_atmos(0.5)
		fuel_port.process_atmos()
		exhaust_pump.process_atmos()

	TEST_ASSERT(injector.air_contents.temperature >= 499, "Preheat failed to reach 500 K (got [injector.air_contents.temperature]).")
	TEST_ASSERT(injector.ignite_chamber(), "Ignition should succeed for a 90/10 plasma/O2 mix at >=500 K.")
	log_test("POST-IGNITE chamber: [format_mix(injector.air_contents)] burning=[injector.burning]")

	// Let feed pressurize from the hot chamber before thrusting.
	for(var/i in 1 to 10)
		injector.process_atmos(0.5)
	TEST_ASSERT(injector.has_feed_propellant(), "L2 feed should receive propellant after chamber push ticks.")
	log_test("POST-FEED-PUSH L2: [format_mix(pipeline_air(injector.feed_connector))]")

	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.update_engine(), "HNT should stay active once L2 is pressurized.")
	TEST_ASSERT(engine.thruster_active, "HNT thruster_active required for process_tick_burn.")

	var/start_chamber_moles = injector.air_contents.total_moles()
	var/start_fuel_moles = fuel_can.air_contents.total_moles()
	var/start_feed_moles = pipeline_air(injector.feed_connector).total_moles()
	var/peak_temp = injector.air_contents.temperature
	var/peak_pressure = injector.air_contents.return_pressure()
	var/peak_isp = 0
	var/total_thrust = 0

	for(var/tick in 1 to OVERMAP_FUEL_TEST_TICKS)
		injector.process_atmos(0.5)
		fuel_port.process_atmos()
		exhaust_pump.process_atmos()
		exhaust_port.process_atmos()
		refresh_grid_power(grid_apc)

		var/list/thrust_map = injector.process_tick_burn(list(engine), 100)
		var/tick_thrust = thrust_map[engine] || 0
		total_thrust += tick_thrust

		var/isp = fuel_injector_estimate_isp(injector)
		peak_temp = max(peak_temp, injector.air_contents.temperature)
		peak_pressure = max(peak_pressure, injector.air_contents.return_pressure())
		peak_isp = max(peak_isp, isp)

		if(tick == 1 || tick == OVERMAP_FUEL_TEST_TICKS || tick % 5 == 0)
			log_test("TICK [tick]: CHAMBER [format_mix(injector.air_contents)] burning=[injector.burning]")
			log_test("TICK [tick]: L2_FEED [format_mix(pipeline_air(injector.feed_connector))] isp=[round(isp, 0.001)] chem=[fuel_injector_estimate_chemical_bonus(pipeline_air(injector.feed_connector) || injector.air_contents)] thrust=[round(tick_thrust, 0.01)]")
			log_test("TICK [tick]: FUEL_CAN [format_mix(fuel_can.air_contents)]")

	var/delta_chamber = start_chamber_moles - injector.air_contents.total_moles()
	var/delta_fuel = start_fuel_moles - fuel_can.air_contents.total_moles()
	var/end_feed_moles = pipeline_air(injector.feed_connector)?.total_moles() || 0
	log_test("SUMMARY peak_T=[round(peak_temp, 0.1)]K peak_P=[round(peak_pressure, 0.1)]kPa peak_isp=[round(peak_isp, 0.001)] total_thrust=[round(total_thrust, 0.01)]")
	log_test("SUMMARY delta_chamber=[round(delta_chamber, 0.01)] delta_fuel_can=[round(delta_fuel, 0.01)] feed_start=[round(start_feed_moles, 0.01)] feed_end=[round(end_feed_moles, 0.01)]")

	TEST_ASSERT(total_thrust > 0, "Hot ignited burn should produce thrust from L2 feed.")
	TEST_ASSERT(peak_isp > engine.hall_only_efficiency, "Hot path ISP should exceed hall-only efficiency (got [peak_isp]).")
	TEST_ASSERT(delta_fuel > 0 || delta_chamber > 0.01 || end_feed_moles < start_feed_moles, "Expected continuous mole movement under load.")

	// --- Thermal path: cold inert feed still consumes moles with gas ISP, not hall-only ---
	var/datum/gas_mixture/feed_air = pipeline_air(injector.feed_connector)
	feed_air.remove(feed_air.total_moles())
	feed_air.set_temperature(T20C)
	feed_air.adjust_gas(/datum/gas/nitrogen, 20)
	injector.feed_connector.gas_connector.update_parents()
	injector.burning = FALSE

	var/feed_before = feed_air.total_moles()
	var/list/thermal_result = injector.consume_from_feed(5, 1)
	var/thermal_fraction = thermal_result[1]
	var/thermal_isp = thermal_result[2]
	var/feed_after = pipeline_air(injector.feed_connector).total_moles()
	log_test("THERMAL consume fraction=[thermal_fraction] isp=[round(thermal_isp, 0.001)] feed [round(feed_before, 0.01)] → [round(feed_after, 0.01)]")
	TEST_ASSERT(thermal_fraction > 0, "Cold thermal path should consume L2 moles.")
	TEST_ASSERT(feed_after < feed_before, "Cold thermal path should reduce L2 moles.")
	TEST_ASSERT(thermal_isp > engine.hall_only_efficiency, "Thermal gas ISP should not be capped at hall-only ([thermal_isp]).")
	var/datum/gas_mixture/cold_sample = new(CELL_VOLUME)
	cold_sample.set_temperature(T20C)
	cold_sample.adjust_gas(/datum/gas/nitrogen, 1)
	TEST_ASSERT(fuel_injector_estimate_chemical_bonus(cold_sample) <= 1, "Cold N2 should not get chemical bonus.")

	// --- Hall-only: empty L2 and empty chamber ---
	feed_air = pipeline_air(injector.feed_connector)
	feed_air.remove(feed_air.total_moles())
	injector.air_contents.remove(injector.air_contents.total_moles())
	injector.feed_connector.gas_connector.update_parents()
	TEST_ASSERT(!injector.has_feed_propellant(), "Feed should be empty for hall-only check.")
	TEST_ASSERT(!injector.has_propellant(), "Chamber+feed should be empty for hall-only check.")

	refresh_grid_power(grid_apc)
	var/hall_thrust = engine.burn_engine(100, skip_engine_update = TRUE)
	log_test("HALL-ONLY thrust=[round(hall_thrust, 0.01)] expected_cap=[round(engine.thrust * engine.hall_only_efficiency, 0.01)]")
	TEST_ASSERT(hall_thrust > 0, "Dry HNT should produce hall-only thrust.")
	TEST_ASSERT(hall_thrust <= engine.thrust * engine.hall_only_efficiency + 0.01, "Hall-only thrust should be capped at 15% of rated.")

// ---------------------------------------------------------------------------
// Simulated ship: mix matrix → expected thrust via process_engine_fuel_burns
// ---------------------------------------------------------------------------

/datum/unit_test/overmap_fuel_injector/ship_mix_thrust

/datum/unit_test/overmap_fuel_injector/ship_mix_thrust/Run()
	var/list/fixture = build_ship_thrust_fixture()
	var/obj/machinery/overmap/fuel_injector/injector = fixture["injector"]
	var/obj/machinery/power/shuttle_engine/overmap/standard/engine = fixture["engine"]
	var/obj/machinery/power/apc/grid_apc = fixture["apc"]
	var/obj/structure/overmap/ship/simulated/ship = fixture["ship"]

	TEST_ASSERT(ship.state == OVERMAP_SHIP_FLYING, "Simulated ship must be FLYING for burn_engines.")
	TEST_ASSERT(ship.shuttle, "Simulated ship must bind the mobile port.")
	TEST_ASSERT(length(ship.shuttle.engine_list), "Simulated ship shuttle must list the HNT engine.")

	var/datum/gas_mixture/feed_air
	var/cold_n2_thrust = 0
	var/cold_plasma_o2_thrust = 0

	// Cases: list(name, temperature, gas_fractions assoc, expect_chem_bonus, expect_zero_isp)
	var/list/mix_cases = list(
		list("cold_n2", T20C, list(/datum/gas/nitrogen = 1), FALSE, FALSE),
		list("cold_h2", T20C, list(/datum/gas/hydrogen = 1), FALSE, FALSE),
		list("cold_he", T20C, list(/datum/gas/helium = 1), FALSE, FALSE),
		list("cold_freon", T20C, list(/datum/gas/freon = 1), FALSE, FALSE),
		list("cold_plasma_o2", T20C, list(/datum/gas/plasma = 0.6, /datum/gas/oxygen = 0.4), FALSE, FALSE),
		list("hot_plasma_o2", PLASMA_MINIMUM_BURN_TEMPERATURE + 50, list(/datum/gas/plasma = 0.6, /datum/gas/oxygen = 0.4), TRUE, FALSE),
		list("hypernoblium", T20C, list(/datum/gas/hypernoblium = 1), FALSE, TRUE),
	)

	for(var/list/case as anything in mix_cases)
		var/case_name = case[1]
		var/temperature = case[2]
		var/list/gas_fractions = case[3]
		var/expect_chem = case[4]
		var/expect_zero_isp = case[5]

		injector.air_contents.remove(injector.air_contents.total_moles())
		injector.burning = FALSE
		feed_air = set_feed_mix(injector, gas_fractions, temperature, OVERMAP_FUEL_TEST_FEED_MOLES)
		var/feed_moles = feed_air.total_moles()

		var/datum/gas_mixture/sample = new(CELL_VOLUME)
		sample.set_temperature(temperature)
		for(var/gas_path in gas_fractions)
			sample.adjust_gas(gas_path, gas_fractions[gas_path])

		var/chem_bonus = fuel_injector_estimate_chemical_bonus(sample)
		if(expect_chem)
			TEST_ASSERT(chem_bonus > 1, "[case_name]: expected chemical ISP bonus.")
		else
			TEST_ASSERT(chem_bonus <= 1, "[case_name]: should not get chemical ISP bonus (got [chem_bonus]).")

		var/expected = expected_feed_thrust(injector, engine, sample, feed_moles, 100, 1)
		if(expect_zero_isp)
			TEST_ASSERT(expected <= 0, "[case_name]: zero-ISP mix should predict no feed thrust.")

		refresh_grid_power(grid_apc)
		TEST_ASSERT(engine.update_engine(), "[case_name]: engine should stay active with feed propellant or power.")
		var/list/thrust_map = ship.process_engine_fuel_burns(100)
		var/actual = thrust_map[engine] || 0
		var/feed_after = pipeline_air(injector.feed_connector)?.total_moles() || 0

		log_test("MIX [case_name]: [format_mix(pipeline_air(injector.feed_connector))] chem=[chem_bonus] expected=[round(expected, 0.001)] actual=[round(actual, 0.001)] feed [round(feed_moles, 0.01)]→[round(feed_after, 0.01)]")

		if(expect_zero_isp)
			// consume_from_feed still pulls moles; process_tick_burn discards zero-ISP results.
			TEST_ASSERT(actual <= 0, "[case_name]: zero-ISP mix should produce no ship feed thrust.")
			TEST_ASSERT(feed_after < feed_moles, "[case_name]: zero-ISP mix still consumes L2 before ISP gate.")
		else
			assert_thrust_near(actual, expected, case_name)
			TEST_ASSERT(feed_after < feed_moles, "[case_name]: ship burn should consume L2 moles.")
			TEST_ASSERT(actual > engine.thrust * engine.hall_only_efficiency, "[case_name]: feed thrust should exceed hall-only cap.")

		if(case_name == "cold_n2")
			cold_n2_thrust = actual
		else if(case_name == "cold_h2")
			TEST_ASSERT(actual > cold_n2_thrust, "cold_h2 thrust should exceed cold_n2.")
		else if(case_name == "cold_plasma_o2")
			cold_plasma_o2_thrust = actual
		else if(case_name == "hot_plasma_o2")
			TEST_ASSERT(actual > cold_plasma_o2_thrust, "hot_plasma_o2 should exceed cold_plasma_o2.")

	// Chamber-only wait: gas in chamber, empty L2 → no hall-only, no feed burn.
	feed_air = pipeline_air(injector.feed_connector)
	feed_air.remove(feed_air.total_moles())
	injector.feed_connector.gas_connector.update_parents()
	injector.air_contents.remove(injector.air_contents.total_moles())
	injector.air_contents.set_temperature(T20C)
	injector.air_contents.adjust_gas(/datum/gas/nitrogen, 20)
	TEST_ASSERT(injector.has_propellant(), "Chamber should report propellant for wait-state.")
	TEST_ASSERT(!injector.has_feed_propellant(), "L2 must be empty for chamber-wait.")
	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.update_engine(), "Chamber propellant should keep HNT active.")
	var/list/wait_map = ship.process_engine_fuel_burns(100)
	TEST_ASSERT(!length(wait_map), "Chamber-only should not batch through process_engine_fuel_burns.")
	var/wait_thrust = engine.burn_engine(100, skip_engine_update = TRUE)
	TEST_ASSERT(wait_thrust <= 0, "Chamber-only HNT must wait (0 thrust), not fall through to hall-only.")

	// Hall-only via ship.burn_engines with dry injector.
	injector.air_contents.remove(injector.air_contents.total_moles())
	TEST_ASSERT(!injector.has_propellant(), "Injector must be fully dry for hall-only.")
	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.update_engine(), "Grid power should keep dry HNT active for hall-only.")
	var/expected_hall = engine.thrust * engine.hall_only_efficiency
	ship.burn_engines(null, 100)
	log_test("SHIP HALL-ONLY est_thrust=[round(ship.est_thrust, 0.001)] expected=[round(expected_hall, 0.001)]")
	assert_thrust_near(ship.est_thrust, expected_hall, "ship_hall_only")

	teardown_ship_thrust_fixture(fixture)

#undef OVERMAP_FUEL_TEST_TICKS
#undef OVERMAP_FUEL_TEST_PRESSURE
#undef OVERMAP_FUEL_TEST_FEED_MOLES
#undef OVERMAP_FUEL_TEST_THRUST_TOLERANCE
