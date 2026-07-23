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

/// Expected single-engine thrust for a known L2 mix at full power (mirrors process_tick_burn at dt=1).
/datum/unit_test/overmap_fuel_injector/proc/expected_feed_thrust(obj/machinery/overmap/fuel_injector/injector, obj/machinery/power/shuttle_engine/overmap/engine, datum/gas_mixture/feed_sample, feed_moles, throttle = 1, power_fraction = 1)
	var/gas_mult = overmap_gas_isp_multiplier(feed_sample)
	var/chem_bonus = fuel_injector_estimate_chemical_bonus(feed_sample)
	var/effective_isp = injector.base_isp * gas_mult * chem_bonus
	if(effective_isp <= 0)
		return 0
	var/mol_s = overmap_engine_propellant_mol_s(engine.thrust, power_fraction)
	var/requested = mol_s * throttle
	if(requested <= 0)
		return 0
	var/burn_fraction = min(feed_moles / requested, 1)
	return engine.thrust * power_fraction * effective_isp * burn_fraction * throttle

/datum/unit_test/overmap_fuel_injector/proc/full_demand_moles(obj/machinery/power/shuttle_engine/overmap/engine, power_fraction = 1)
	return overmap_engine_propellant_mol_s(engine.thrust, power_fraction)

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

	var/list/ship_bits = attach_simulated_ship(injector_turf, engine, "overmap_fuel_mix_test", "Fuel Mix Test Shuttle")
	var/obj/docking_port/mobile/port = ship_bits["port"]
	var/obj/structure/overmap/ship/simulated/ship = ship_bits["ship"]
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

/// Bind a mobile port + simulated ship so ship_wants_thrust() can see commanded throttle.
/datum/unit_test/overmap_fuel_injector/proc/attach_simulated_ship(turf/anchor_turf, obj/machinery/power/shuttle_engine/overmap/engine, shuttle_id, port_name)
	var/area/hull_area = get_area(anchor_turf)
	var/obj/docking_port/mobile/port = allocate(/obj/docking_port/mobile, anchor_turf, list(hull_area))
	port.name = port_name
	port.shuttle_id = shuttle_id
	port.width = 5
	port.height = 5
	port.dwidth = 2
	port.dheight = 2
	engine.connect_to_shuttle(FALSE, port)
	TEST_ASSERT(engine in port.engine_list, "HNT should be registered on the mobile port engine_list.")
	TEST_ASSERT(engine.connected_ship == port, "HNT connected_ship should match the test port.")

	// Test Z is not an overmap/reserved level, so setup_shuttle_ship() no-ops.
	var/obj/structure/overmap/ship/simulated/ship = allocate(/obj/structure/overmap/ship/simulated, anchor_turf, port.shuttle_id, port)
	port.current_ship = ship
	ship.state = OVERMAP_SHIP_FLYING
	ship.calculate_mass()
	return list("port" = port, "ship" = ship)

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

	var/list/ship_bits = attach_simulated_ship(injector_turf, engine, "overmap_fuel_burn_cycle", "Fuel Burn Cycle Shuttle")
	var/obj/structure/overmap/ship/simulated/ship = ship_bits["ship"]
	// process_tick_burn gates on ship_wants_thrust(); command full throttle for the hot path.
	ship.desired_throttle = 1

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

		var/list/thrust_map = injector.process_tick_burn(list(engine), full_demand_moles(engine), 1)
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
	ship.desired_throttle = 1
	var/hall_thrust = engine.burn_engine(100, skip_engine_update = TRUE)
	log_test("HALL-ONLY thrust=[round(hall_thrust, 0.01)] expected_cap=[round(engine.thrust * engine.hall_only_efficiency, 0.01)]")
	TEST_ASSERT(hall_thrust > 0, "Dry HNT should produce hall-only thrust.")
	TEST_ASSERT(hall_thrust <= engine.thrust * engine.hall_only_efficiency + 0.01, "Hall-only thrust should be capped at 15% of rated.")

	teardown_ship_thrust_fixture(list("ship" = ship, "port" = ship_bits["port"]))

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

	// process_tick_burn / burn_engine gate on commanded throttle.
	ship.desired_throttle = 1

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

		var/expected = expected_feed_thrust(injector, engine, sample, feed_moles, 1, 1)
		if(expect_zero_isp)
			TEST_ASSERT(expected <= 0, "[case_name]: zero-ISP mix should predict no feed thrust.")

		refresh_grid_power(grid_apc)
		TEST_ASSERT(engine.update_engine(), "[case_name]: engine should stay active with feed propellant or power.")
		var/demand = full_demand_moles(engine)
		var/list/thrust_map = ship.process_engine_fuel_burns(demand, 1)
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
	var/list/wait_map = ship.process_engine_fuel_burns(full_demand_moles(engine), 1)
	TEST_ASSERT(!length(wait_map), "Chamber-only should not batch through process_engine_fuel_burns.")
	var/wait_thrust = engine.burn_engine(100, skip_engine_update = TRUE)
	TEST_ASSERT(wait_thrust <= 0, "Chamber-only HNT must wait (0 thrust), not fall through to hall-only.")

	// Hall-only via ship.burn_engines with dry injector (null dir is all-stop, not burn).
	injector.air_contents.remove(injector.air_contents.total_moles())
	TEST_ASSERT(!injector.has_propellant(), "Injector must be fully dry for hall-only.")
	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.update_engine(), "Grid power should keep dry HNT active for hall-only.")
	var/expected_hall = engine.thrust * engine.hall_only_efficiency
	ship.burn_engines(NORTH, 100)
	log_test("SHIP HALL-ONLY est_thrust=[round(ship.est_thrust, 0.001)] expected=[round(expected_hall, 0.001)]")
	assert_thrust_near(ship.est_thrust, expected_hall, "ship_hall_only")

	teardown_ship_thrust_fixture(fixture)

// ---------------------------------------------------------------------------
// Performance metrics: ISP / Δv / UI payload / engine-link dedupe
// ---------------------------------------------------------------------------

/datum/unit_test/overmap_fuel_injector/performance_metrics

/datum/unit_test/overmap_fuel_injector/performance_metrics/Run()
	var/list/fixture = build_ship_thrust_fixture()
	var/obj/machinery/overmap/fuel_injector/injector = fixture["injector"]
	var/obj/machinery/power/shuttle_engine/overmap/standard/engine = fixture["engine"]
	var/obj/machinery/power/apc/grid_apc = fixture["apc"]
	var/obj/structure/overmap/ship/simulated/ship = fixture["ship"]

	// Cold N2 on L2: known gas_mult = 1.0, no chemical bonus.
	set_feed_mix(injector, list(/datum/gas/nitrogen = 1), T20C, OVERMAP_FUEL_TEST_FEED_MOLES)
	injector.air_contents.remove(injector.air_contents.total_moles())
	injector.burning = FALSE

	var/expected_isp = injector.base_isp * overmap_gas_isp_mult(/datum/gas/nitrogen)
	var/isp = fuel_injector_estimate_isp(injector)
	TEST_ASSERT(abs(isp - expected_isp) < 0.001, "N2 ISP should be base×gas_mult ([expected_isp]), got [isp].")
	TEST_ASSERT(isp > 0, "N2 ISP estimate must be non-zero.")

	// ISP is propellant-only — must not collapse when grid surplus is zero.
	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.get_power_fraction() > 0, "Grid surplus required before zeroing avail.")
	var/isp_with_power = fuel_injector_estimate_isp(injector)
	engine.powernet.avail = 0
	engine.powernet.load = 999 KILO JOULES
	TEST_ASSERT(engine.get_power_fraction() <= 0, "Power fraction should be 0 with no surplus.")
	var/isp_without_power = fuel_injector_estimate_isp(injector)
	TEST_ASSERT(abs(isp_with_power - isp_without_power) < 0.001, "ISP estimate must ignore engine power fraction ([isp_with_power] vs [isp_without_power]).")
	refresh_grid_power(grid_apc)

	// Empty L2, chamber-only fallback.
	var/datum/gas_mixture/feed_air = pipeline_air(injector.feed_connector)
	feed_air.remove(feed_air.total_moles())
	injector.feed_connector.gas_connector.update_parents()
	injector.air_contents.set_temperature(T20C)
	injector.air_contents.adjust_gas(/datum/gas/hydrogen, 10)
	var/chamber_isp = fuel_injector_estimate_isp(injector)
	var/expected_h2 = injector.base_isp * overmap_gas_isp_mult(/datum/gas/hydrogen)
	TEST_ASSERT(abs(chamber_isp - expected_h2) < 0.001, "Chamber-only ISP fallback should use H2 mult ([expected_h2]), got [chamber_isp].")

	// Δv uses moles / OVERMAP_PROP_MOLES_PER_THRUST (not ×).
	if(!ship.mass)
		ship.calculate_mass()
	var/ship_mass = ship.mass
	TEST_ASSERT(ship_mass > 0, "Ship mass required for Δv checks.")
	var/stored = injector.get_stored_propellant_moles()
	var/propellant_mass = stored / OVERMAP_PROP_MOLES_PER_THRUST
	var/expected_dv = chamber_isp * OVERMAP_G0 * log((ship_mass + propellant_mass) / ship_mass)
	var/actual_dv = fuel_injector_estimate_delta_v(injector, ship_mass)
	TEST_ASSERT(abs(actual_dv - expected_dv) < 0.01, "Δv mismatch: got [actual_dv] expected [expected_dv] (stored=[stored] mass=[ship_mass]).")
	TEST_ASSERT(actual_dv > 0, "Δv for chamber H2 should be positive.")

	// Wrong conversion (multiply) underflows vs divide — guards the regression.
	var/wrong_propellant = stored * OVERMAP_PROP_MOLES_PER_THRUST
	var/wrong_dv = chamber_isp * OVERMAP_G0 * log((ship_mass + wrong_propellant) / ship_mass)
	TEST_ASSERT(actual_dv > wrong_dv * 2, "Δv (moles/PROP) should greatly exceed the old moles×PROP underflow ([actual_dv] vs [wrong_dv]).")
	// Zero-ISP mix → zero Δv.
	set_feed_mix(injector, list(/datum/gas/hypernoblium = 1), T20C, 20)
	injector.air_contents.remove(injector.air_contents.total_moles())
	TEST_ASSERT(fuel_injector_estimate_isp(injector) <= 0, "Hypernoblium ISP should be 0.")
	TEST_ASSERT(fuel_injector_estimate_delta_v(injector, ship_mass) <= 0, "Zero ISP should yield zero Δv.")

	// Restore a fractional-ISP mix and assert UI payload survives BYOND round(A, B).
	set_feed_mix(injector, list(/datum/gas/plasma = 0.6, /datum/gas/oxygen = 0.4), T20C, OVERMAP_FUEL_TEST_FEED_MOLES)
	injector.air_contents.remove(injector.air_contents.total_moles())
	var/list/ui = injector.ui_data(null)
	var/list/perf = ui["performance"]
	TEST_ASSERT(islist(perf), "ui_data should include performance.")
	var/ui_isp = perf["estimated_isp"]
	var/ui_gas = perf["gas_multiplier"]
	var/ui_eff = perf["thrust_efficiency"]
	var/ui_dv = perf["delta_v"]
	TEST_ASSERT(ui_isp > 0 && ui_isp < 2, "UI estimated_isp should keep fractional ISP (got [ui_isp]); nearest-multiple round would collapse this to 0.")
	TEST_ASSERT(ui_gas > 0 && ui_gas < 2, "UI gas_multiplier should keep fractional value (got [ui_gas]).")
	TEST_ASSERT(ui_eff > 0 && ui_eff <= 1, "UI thrust_efficiency should be > 0 and <= 1 (got [ui_eff]).")
	TEST_ASSERT(!perf["ship_mass_unknown"], "Fixture ship should report known mass.")
	TEST_ASSERT(ui_dv > 0, "UI delta_v should be positive with propellant (got [ui_dv]).")
	TEST_ASSERT(abs(ui_isp - fuel_injector_estimate_isp(injector)) < 0.002, "UI ISP should match estimate_isp.")
	TEST_ASSERT(abs(ui_eff - min(ui_isp / FUEL_INJECTOR_ISP_NOMINAL_MAX, 1)) < 0.002, "UI thrust_efficiency should be isp over nominal.")

	teardown_ship_thrust_fixture(fixture)

/datum/unit_test/overmap_fuel_injector/engine_link_dedupe

/datum/unit_test/overmap_fuel_injector/engine_link_dedupe/Run()
	var/turf/injector_turf = locate(
		run_loc_floor_bottom_left.x + 2,
		run_loc_floor_bottom_left.y + 3,
		run_loc_floor_bottom_left.z,
	)
	TEST_ASSERT(injector_turf, "Failed to locate injector turf for link dedupe.")
	var/turf/pipe_w = locate(injector_turf.x - 1, injector_turf.y - 1, injector_turf.z)
	var/turf/pipe_c = locate(injector_turf.x, injector_turf.y - 1, injector_turf.z)
	var/turf/pipe_e = locate(injector_turf.x + 1, injector_turf.y - 1, injector_turf.z)
	var/turf/eng_w = locate(injector_turf.x - 1, injector_turf.y - 2, injector_turf.z)
	var/turf/eng_c = locate(injector_turf.x, injector_turf.y - 2, injector_turf.z)
	var/turf/eng_e = locate(injector_turf.x + 1, injector_turf.y - 2, injector_turf.z)
	for(var/turf/needed as anything in list(pipe_w, pipe_c, pipe_e, eng_w, eng_c, eng_e))
		TEST_ASSERT(isfloorturf(needed), "Expected floor at [needed?.x],[needed?.y] for 3-engine manifold.")

	// Manifold only on the row north of the engines. Pipes on the engine turfs
	// fight the reversed L2 feed connectors (intake faces north into the manifold).
	var/list/l2_pipes = list(
		allocate(/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer2, pipe_w),
		allocate(/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer2, pipe_c),
		allocate(/obj/machinery/atmospherics/pipe/smart/simple/general/visible/layer2, pipe_e),
	)

	var/obj/machinery/overmap/fuel_injector/injector = allocate(/obj/machinery/overmap/fuel_injector, injector_turf)
	injector.setDir(SOUTH)
	injector.use_power = NO_POWER_USE

	var/list/engines = list()
	for(var/turf/engine_turf as anything in list(eng_w, eng_c, eng_e))
		var/obj/machinery/power/shuttle_engine/overmap/standard/engine = allocate(/obj/machinery/power/shuttle_engine/overmap/standard, engine_turf)
		engine.setDir(SOUTH)
		engine.use_power = NO_POWER_USE
		engines += engine

	var/list/atmos_devices = l2_pipes.Copy()
	atmos_devices += injector.feed_connector.gas_connector
	for(var/obj/machinery/power/shuttle_engine/overmap/standard/engine as anything in engines)
		atmos_devices += engine.feed_connector.gas_connector
	init_atmos_devices(atmos_devices)
	var/datum/pipeline/feed_pipe = overmap_hnt_feed_pipeline(injector.feed_connector)
	TEST_ASSERT(feed_pipe, "Injector L2 feed pipenet missing.")
	for(var/obj/machinery/power/shuttle_engine/overmap/standard/engine as anything in engines)
		TEST_ASSERT(overmap_hnt_feed_pipeline(engine.feed_connector) == feed_pipe, "Engine at [engine.x],[engine.y] should share injector L2 pipenet.")

	var/list/ship_bits = attach_simulated_ship(injector_turf, engines[1], "overmap_fuel_link_dedupe", "Link Dedupe Shuttle")
	var/obj/docking_port/mobile/port = ship_bits["port"]
	for(var/obj/machinery/power/shuttle_engine/overmap/standard/engine as anything in engines)
		if(engine == engines[1])
			continue
		engine.connect_to_shuttle(FALSE, port)
	TEST_ASSERT_EQUAL(length(port.engine_list), 3, "Port engine_list should hold all three HNTs.")

	injector.update_linked_engines()
	TEST_ASSERT_EQUAL(length(injector.linked_engines), 3, "Injector should link exactly 3 piped engines after update.")

	// Rescans used to append duplicate WEAKREFs (WEAKREF(x) in list never matches).
	for(var/obj/machinery/power/shuttle_engine/overmap/standard/engine as anything in engines)
		engine.scan_for_injector()
		engine.scan_for_injector()
	injector.update_linked_engines()
	for(var/obj/machinery/power/shuttle_engine/overmap/standard/engine as anything in engines)
		engine.scan_for_injector()

	TEST_ASSERT_EQUAL(length(injector.linked_engines), 3, "Linked engine count must stay 3 after repeated scans (got [length(injector.linked_engines)]).")

	var/list/resolved = list()
	for(var/datum/weakref/engine_ref as anything in injector.linked_engines)
		var/obj/machinery/power/shuttle_engine/overmap/engine = engine_ref?.resolve()
		TEST_ASSERT(engine, "Linked engine weakref failed to resolve.")
		TEST_ASSERT(!(engine in resolved), "Duplicate engine in linked_engines: [engine].")
		resolved += engine
		TEST_ASSERT(engine.get_linked_injector() == injector, "Engine should point back at the injector.")
		TEST_ASSERT(engine.link_via_pipe, "Engines on the shared L2 manifold should be piped links.")

	var/list/manifold = fuel_injector_manifold_share_stats(injector)
	TEST_ASSERT_EQUAL(manifold["piped_engines"], 3, "Manifold stats should report 3 piped engines.")
	TEST_ASSERT_EQUAL(manifold["adjacent_engines"], 0, "Manifold stats should report 0 adjacent engines.")

	teardown_ship_thrust_fixture(ship_bits)

// ---------------------------------------------------------------------------
// Spool: high L2 pressure → instant mass flow; low pressure → ramp.
// ---------------------------------------------------------------------------

/datum/unit_test/overmap_fuel_injector/spool_response

/datum/unit_test/overmap_fuel_injector/spool_response/Run()
	var/list/fixture = build_ship_thrust_fixture()
	var/obj/machinery/overmap/fuel_injector/injector = fixture["injector"]
	var/obj/machinery/power/shuttle_engine/overmap/standard/engine = fixture["engine"]
	var/obj/machinery/power/apc/grid_apc = fixture["apc"]
	var/obj/structure/overmap/ship/simulated/ship = fixture["ship"]

	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.update_engine(), "Engine should activate for spool tests.")
	ship.desired_throttle = 1

	// High rail: fill L2 to well above full-rail pressure so spool-up is instant.
	set_feed_mix(injector, list(/datum/gas/nitrogen = 1), T20C, OVERMAP_FUEL_TEST_FEED_MOLES)
	var/high_p = injector.return_feed_pressure()
	TEST_ASSERT(high_p >= OVERMAP_SPOOL_FULL_RAIL_PRESSURE, "High-rail fixture pressure [high_p] should meet full-rail setpoint.")
	ship.delivered_mol_s = 0
	ship.update_propellant_spool(0.2)
	TEST_ASSERT(ship.target_mol_s > OVERMAP_MOL_S_EPSILON, "Full throttle should set a non-zero target mol/s.")
	TEST_ASSERT(abs(ship.delivered_mol_s - ship.target_mol_s) <= OVERMAP_MOL_S_EPSILON, "High rail should spool to target in one 0.2s tick (delivered=[ship.delivered_mol_s] target=[ship.target_mol_s]).")

	// Low rail: nearly empty L2 — spool-up must lag.
	set_feed_mix(injector, list(/datum/gas/nitrogen = 1), T20C, 0.05)
	ship.delivered_mol_s = 0
	ship.update_propellant_spool(0.2)
	TEST_ASSERT(ship.delivered_mol_s < ship.target_mol_s * 0.5, "Low rail should not reach half target in one tick (delivered=[ship.delivered_mol_s] target=[ship.target_mol_s]).")
	var/partial = ship.delivered_mol_s
	ship.update_propellant_spool(0.2)
	TEST_ASSERT(ship.delivered_mol_s > partial, "Low rail should continue ramping on subsequent ticks.")

	teardown_ship_thrust_fixture(fixture)

// ---------------------------------------------------------------------------
// Under thrust, cold L1 refill must not quench a lit 60/40 chamber.
// ---------------------------------------------------------------------------

/datum/unit_test/overmap_fuel_injector/thrust_inlet_no_quench

/datum/unit_test/overmap_fuel_injector/thrust_inlet_no_quench/Run()
	var/list/fixture = build_ship_thrust_fixture()
	var/obj/machinery/overmap/fuel_injector/injector = fixture["injector"]
	var/obj/machinery/power/shuttle_engine/overmap/standard/engine = fixture["engine"]
	var/obj/machinery/power/apc/grid_apc = fixture["apc"]
	var/obj/structure/overmap/ship/simulated/ship = fixture["ship"]

	ship.desired_throttle = 1
	injector.air_contents.remove(injector.air_contents.total_moles())
	injector.air_contents.set_temperature(T20C)
	injector.air_contents.adjust_gas(/datum/gas/plasma, 5)
	injector.air_contents.adjust_gas(/datum/gas/oxygen, 3.5)
	injector.air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 80)
	TEST_ASSERT(injector.ignite_chamber(), "60/40 chamber should ignite for quench test.")

	// Cold high-pressure L1 supply (canister-like).
	var/datum/gas_mixture/intake_air = pipeline_air(injector.input_connector)
	TEST_ASSERT(intake_air, "L1 intake pipeline missing.")
	intake_air.remove(intake_air.total_moles())
	intake_air.set_temperature(T20C)
	intake_air.adjust_gas(/datum/gas/plasma, 40)
	intake_air.adjust_gas(/datum/gas/oxygen, 30)
	injector.input_connector.gas_connector.update_parents()

	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.update_engine(), "Engine should stay active.")
	var/demand = full_demand_moles(engine)
	ship.target_mol_s = demand
	ship.delivered_mol_s = demand

	var/min_temp = injector.air_contents.temperature
	for(var/tick in 1 to 12)
		injector.process_atmos(0.5)
		refresh_grid_power(grid_apc)
		if(injector.has_feed_propellant())
			injector.process_tick_burn(list(engine), demand * 0.2, 0.2)
		min_temp = min(min_temp, injector.air_contents.temperature)
		if(tick == 1 || tick % 4 == 0)
			log_test("QUENCH TICK [tick]: T=[round(injector.air_contents.temperature, 0.1)] P=[round(injector.air_contents.return_pressure(), 0.1)] ignited=[injector.chamber_ignited] burning=[injector.burning]")

	TEST_ASSERT(injector.chamber_ignited, "Chamber should stay ignited under thrust with cold L1.")
	TEST_ASSERT(min_temp >= PLASMA_MINIMUM_BURN_TEMPERATURE, "Chamber T must not fall below ignition under thrust (min T=[round(min_temp, 0.1)]).")
	// Inlet heater must fully bring admitted charge to target — partial warm was the quench bug.
	var/datum/gas_mixture/probe = new(CELL_VOLUME)
	probe.set_temperature(T20C)
	probe.adjust_gas(/datum/gas/plasma, 2)
	probe.adjust_gas(/datum/gas/oxygen, 1.5)
	injector.chamber_ignited = TRUE
	injector.air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 100)
	var/datum/gas_mixture/leftover = injector.heat_intake_charge(probe, 0.5)
	TEST_ASSERT(probe.temperature >= PLASMA_MINIMUM_BURN_TEMPERATURE + OVERMAP_INLET_HEAT_MARGIN - 1, "Heated charge must reach inlet target (got [probe.temperature]).")
	TEST_ASSERT(!leftover?.total_moles() || leftover.temperature <= T20C + 1, "Deferred moles should remain cold on L1, not partially warmed into the chamber.")
	teardown_ship_thrust_fixture(fixture)

// ---------------------------------------------------------------------------
// Packed chamber at max P still reacts (must not require preheater to "burn").
// ---------------------------------------------------------------------------

/datum/unit_test/overmap_fuel_injector/packed_chamber_sustains

/datum/unit_test/overmap_fuel_injector/packed_chamber_sustains/Run()
	var/list/fixture = build_ship_thrust_fixture()
	var/obj/machinery/overmap/fuel_injector/injector = fixture["injector"]
	var/obj/structure/overmap/ship/simulated/ship = fixture["ship"]

	ship.desired_throttle = 0
	injector.air_contents.remove(injector.air_contents.total_moles())
	injector.air_contents.set_temperature(T20C)
	// Fill to capacity with 60/40 at just above ignition — mirrors playtest mix.
	var/fill_moles = injector.chamber_mole_capacity()
	injector.air_contents.adjust_gas(/datum/gas/plasma, fill_moles * 0.6)
	injector.air_contents.adjust_gas(/datum/gas/oxygen, fill_moles * 0.4)
	injector.air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 20)
	TEST_ASSERT(injector.ignite_chamber(), "Packed 60/40 mix should ignite.")
	TEST_ASSERT(injector.chamber_ignited, "Ignite should set chamber_ignited.")
	var/temp_after_ignite = injector.air_contents.temperature

	// At/over servo pressure, chemistry must still run (old bug: skip react when full).
	TEST_ASSERT(injector.air_contents.return_pressure() >= injector.max_operating_pressure * 0.9, "Fixture should be near max operating pressure.")
	for(var/i in 1 to 5)
		injector.process_chamber_reaction()
	TEST_ASSERT(injector.chamber_ignited, "Packed chamber must stay ignited across pressure-relief ticks.")
	TEST_ASSERT(injector.air_contents.temperature > temp_after_ignite, "Packed chamber should self-heat without preheater (T [temp_after_ignite]→[injector.air_contents.temperature]).")

	teardown_ship_thrust_fixture(fixture)

// ---------------------------------------------------------------------------
// Cold flameout: mix below ignition for N ticks clears chamber_ignited.
// ---------------------------------------------------------------------------

/datum/unit_test/overmap_fuel_injector/cold_flameout

/datum/unit_test/overmap_fuel_injector/cold_flameout/Run()
	var/list/fixture = build_ship_thrust_fixture()
	var/obj/machinery/overmap/fuel_injector/injector = fixture["injector"]

	injector.air_contents.remove(injector.air_contents.total_moles())
	injector.air_contents.set_temperature(T20C)
	injector.air_contents.adjust_gas(/datum/gas/nitrogen, 5)
	injector.chamber_ignited = TRUE
	injector.burning = TRUE
	injector.air_contents.set_temperature(T20C)

	for(var/i in 1 to OVERMAP_COLD_FLAMEOUT_TICKS + 1)
		injector.process_chamber_reaction()
		if(!injector.chamber_ignited)
			break
	TEST_ASSERT(!injector.chamber_ignited, "Cold soak should flameout chamber_ignited.")
	TEST_ASSERT(!injector.burning, "Flameout should clear burning.")

	var/temp_before = injector.air_contents.temperature
	injector.process_chamber_reaction()
	TEST_ASSERT(!injector.chamber_ignited, "process_chamber_reaction must not re-ignite after flameout.")
	TEST_ASSERT(injector.air_contents.temperature <= temp_before + 1, "Unignited chamber should not keep climbing (T [temp_before]→[injector.air_contents.temperature]).")

	teardown_ship_thrust_fixture(fixture)

// ---------------------------------------------------------------------------
// Thrusting equilibrium: lit + thrust keeps chamber below runaway ceiling.
// ---------------------------------------------------------------------------

#define OVERMAP_FUEL_TEST_T_CEILING 20000

/datum/unit_test/overmap_fuel_injector/thrust_thermal_equilibrium

/datum/unit_test/overmap_fuel_injector/thrust_thermal_equilibrium/Run()
	var/list/fixture = build_ship_thrust_fixture()
	var/obj/machinery/overmap/fuel_injector/injector = fixture["injector"]
	var/obj/machinery/power/shuttle_engine/overmap/standard/engine = fixture["engine"]
	var/obj/machinery/power/apc/grid_apc = fixture["apc"]
	var/obj/structure/overmap/ship/simulated/ship = fixture["ship"]

	ship.desired_throttle = 1
	injector.air_contents.remove(injector.air_contents.total_moles())
	injector.air_contents.set_temperature(T20C)
	injector.air_contents.adjust_gas(/datum/gas/plasma, 6)
	injector.air_contents.adjust_gas(/datum/gas/oxygen, 4)
	injector.air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE + 50)
	TEST_ASSERT(injector.ignite_chamber(), "Equilibrium fixture should ignite.")

	// Prime L2 so nozzle draw can carry heat out immediately.
	for(var/i in 1 to 5)
		injector.process_atmos(0.5)
	refresh_grid_power(grid_apc)
	TEST_ASSERT(engine.update_engine(), "Engine should stay active.")
	TEST_ASSERT(injector.has_feed_propellant(), "Thrust equilibrium needs L2 primed.")
	var/demand = full_demand_moles(engine)
	ship.target_mol_s = demand
	ship.delivered_mol_s = demand

	var/peak_temp = injector.air_contents.temperature
	for(var/tick in 1 to 30)
		injector.process_atmos(0.5)
		refresh_grid_power(grid_apc)
		if(injector.has_feed_propellant())
			injector.process_tick_burn(list(engine), demand * 0.2, 0.2)
		peak_temp = max(peak_temp, injector.air_contents.temperature)
		if(tick == 1 || tick % 10 == 0)
			log_test("EQ TICK [tick]: T=[round(injector.air_contents.temperature, 0.1)] P=[round(injector.air_contents.return_pressure(), 0.1)] ignited=[injector.chamber_ignited] feed_n=[round(injector.get_feed_air()?.total_moles() || 0, 0.01)]")

	TEST_ASSERT(peak_temp < OVERMAP_FUEL_TEST_T_CEILING, "Thrusting burn peak T=[round(peak_temp, 0.1)] should stay under [OVERMAP_FUEL_TEST_T_CEILING]K.")
	teardown_ship_thrust_fixture(fixture)

#undef OVERMAP_FUEL_TEST_T_CEILING

#undef OVERMAP_FUEL_TEST_TICKS
#undef OVERMAP_FUEL_TEST_PRESSURE
#undef OVERMAP_FUEL_TEST_FEED_MOLES
#undef OVERMAP_FUEL_TEST_THRUST_TOLERANCE
