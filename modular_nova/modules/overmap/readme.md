# Overmap

## About

A tile-based "overmap" Z-level for navigating shuttles between points of
interest (the station, mining, and post-prototype dynamic encounters).
Originally implemented for Whitesands; this is a forward-port adapted to
Nova-shaped tooling.

The system models a 20x20 grid where each shuttle is represented by a
`/obj/structure/overmap/ship/simulated` icon. Players sit at a helm
console, see the overmap via a `ByondUi` map widget, and pilot the ship
between station/mining/etc. by manipulating engines and a 3x3 directional
control. Clicking "Act" on an overmap target triggers a real
`SSshuttle.request()` against an associated stationary docking port.

## Module ID

`OVERMAP`

## Status

Playable prototype - milestones M1 through M7 from the implementation
plan. Post-prototype backlog (events, dynamic encounters, planet
generator stub, solar generator, configuration entries, wraparound
polish, more shuttle area_spawn entries) is tracked separately.

Space ruin spawning is now overmap-controlled: when `overmap_space_ruins`
is TRUE in map config, SSmapping no longer creates crosslinked space ruin
Zs. Instead, SSovermap.seed_space_sites() places ruin templates as named
`/level/site` POIs on isolated reserved Zs.

Which ruins that draws, and therefore how many full Z levels of turfs a
round carries, varies run to run. `log_overmap_footprint()` writes the
count, the levels taken, and the template ids to `world.log` once the grid
is generated, so a round that runs out of memory can be read back against
what it seeded.

Cross-faction stealth hides the NT station from DS2 viewers (and vice
versa in v1) until a deployable syndicate beacon is activated.

## Files added

### New modular files

- `modular_nova/modules/overmap/code/overmap_subsystem.dm` - SSovermap.
- `modular_nova/modules/overmap/code/overmap_objects.dm` - turfs, area,
  base `/obj/structure/overmap`, level subtypes (main, mining, site), star.
- `modular_nova/modules/overmap/code/overmap_ships.dm` - base ship and
  `/ship/simulated` (shuttle-bound) types.
- `modular_nova/modules/overmap/code/overmap_helm.dm` - helm console
  computer + viewscreen.
- `modular_nova/modules/overmap/code/overmap_nav.dm` - shuttle-docker
  subtype that filters landing targets through the overmap.
- `modular_nova/modules/overmap/code/overmap_engine.dm`,
  `overmap_engine_types.dm`, `overmap_heater.dm` - shuttle thrust/fuel.
- `modular_nova/modules/overmap/code/gas_connector.dm` - hidden unary
  atmos port used by `gas_machine_connector`, with shuttle-transit-safe
  `return_pipenet` / `add_member` guards.
- `modular_nova/modules/overmap/code/overmap_circuits.dm` - circuit
  boards for helm, nav, engine, heater, landing controller, and corner beacon.
- `modular_nova/modules/overmap/code/overmap_landing_beacon.dm` -
  player-constructable landing zones: `/obj/machinery/landing_corner`
  light beacons linked via multitool to a `/obj/machinery/computer/landing_controller`
  console (records-style login, command/engineering access) that derives a
  rectangular landmark, gated by `max_overmap_landing_zone_dimension`.
- `tgui/packages/tgui/interfaces/OvermapLandingController.tsx` - the
  landing controller UI (login gate, zone naming, corner validation,
  occupancy). Static mock: `tgui/prototypes/OvermapLandingController.html`.
- `modular_nova/modules/overmap/code/overmap_area_spawn.dm` -
  `/datum/area_spawn` entries for helm, nav, engines, and the wall-mount
  distress beacon.
- `modular_nova/modules/overmap/code/overmap_distress_beacon.dm` -
  wall-mount NT distress beacon (additive evac call path).
- `modular_nova/modules/overmap/code/overmap_syndicate_beacon.dm` -
  deployable syndicate station beacon (reveals NT to DS2).
- `modular_nova/modules/overmap/icons/*.dmi` - sprites including
  `stationary_beacons.dmi` (NT wall beacon + syndicate deployable states).
- `tgui/packages/tgui/interfaces/HelmConsole.tsx` - the helm UI rewrite.
- `tgui/packages/tgui/interfaces/DistressBeacon.tsx` - evac beacon TGUI.
- `code/__DEFINES/~nova_defines/overmap.dm` - cross-file defines.
- `code/modules/unit_tests/~nova/overmap_ruins.dm` - unit tests for
  site POIs, stealth gating, crosslinked Z prevention, beacon, and the
  corpse spawner environment exemption.

### master_files overrides

- `modular_nova/master_files/code/controllers/subsystem/mapping.dm` -
  adds `overmap_space_ruins` var on `/datum/map_config`; extends
  `setup_ruins()` to skip space ruin seeding when flag is set.
- `modular_nova/master_files/code/datums/elements/atmos_requirements.dm`
  and `body_temp_sensitive.dm` - exempt a mob a corpse spawner is in the
  middle of making from the maploaded-environment assertions. Sites and
  encounters load after SSair, which is when those assertions stop being
  deferred and start catching the live line between a corpse spawner
  creating its mob and killing it, failing CI on airless stock ruins.

### Core file changes (BLASTWAVE EDIT ADDITION/CHANGE OVERMAP)

- `code/modules/shuttle/mobile_port/mobile_port.dm` - adds
  `var/obj/structure/overmap/ship/simulated/current_ship` to
  `/obj/docking_port/mobile`, and a `SSovermap.setup_shuttle_ship(src)`
  hook in `Initialize()` for non-mapload ports.
- `code/modules/shuttle/mobile_port/shuttle_move.dm` - calls
  `current_ship?.check_loc()` in `initiate_docking` after a successful
  move, so the overmap icon resyncs to the destination Z. Stays below
  the existing SSliquids hook so liquid handling fires first.
- `code/__HELPERS/names.dm` - syncs `SSovermap.main.name` to
  `GLOB.station_name` whenever the station is renamed.
- `code/datums/map_config.dm` - JSON parse for `overmap_space_ruins`
  config flag (BLASTWAVE EDIT ADDITION - OVERMAP).
- `code/modules/atmospherics/machinery/components/unary_devices/machine_connector.dm` -
  explicit `gas_connector` subtype instantiation and `piping_layer` support
  (BLASTWAVE EDIT - OVERMAP).
- `code/controllers/subsystem/mapping.dm` - `claim_turfs_for_reservation`
  proc for post-load ruin turf claiming (BLASTWAVE EDIT - OVERMAP).
- `code/modules/mapping/space_management/space_reservation.dm` - multiz
  reservation bounds hardening (BLASTWAVE EDIT - OVERMAP).
- `code/modules/library/bookcase.dm` - null `book_data` guard during ruin
  map init (BLASTWAVE EDIT - OVERMAP).
- `code/modules/research/techweb/nodes/engi_nodes.dm` - overmap console
  and propulsion techweb designs (BLASTWAVE EDIT - OVERMAP).
- `code/controllers/subsystem/shuttle.dm` - deferred `post_load` in preview
  flow (BLASTWAVE EDIT - SHUTTLE_CONSTRUCTION).
- `code/controllers/master.dm` - `paused_ticks` MC guard (BLASTWAVE EDIT -
  OVERMAP).
- `code/modules/unit_tests/_unit_tests.dm` - include for
  `~nova/overmap_ruins.dm` (BLASTWAVE EDIT ADDITION - OVERMAP).
- `code/modules/shuttle/mobile_port/variants/custom/blueprints.dm` -
  christen routes through `sync_shuttle_display_name` (overmap + GPS);
  master-blueprint TGUI `renameShuttle` + `shuttleName` ui_data
  (BLASTWAVE EDIT - OVERMAP). Helper lives in
  `modular_nova/modules/overmap/code/overmap_shuttles.dm`.
- `code/controllers/subsystem/air.dm` - `begin_z_eject` / `end_z_eject` /
  `eject_z_from_lists` and `ejected_zs` gate on `add_to_active` so overmap
  content-Z soft-clear purges LINDA without walking `Z_TURFS`
  (BLASTWAVE EDIT - OVERMAP).
- `code/modules/atmospherics/environmental/LINDA_turf_tile.dm` - null-air
  neighbor guard before `LINDA_CYCLE_ARCHIVE` during Z soft-clear races
  (BLASTWAVE EDIT - OVERMAP).
- `code/controllers/subsystem/atoms.dm` - re-check `INITIALIZED_1` after
  `CreateAtoms` yield so async modular map loads (Port Tarkon) cannot
  double-init unique ruin areas (BLASTWAVE EDIT - OVERMAP).
- `code/game/objects/structures/crates_lockers/closets/utility_closets.dm` -
  confines emergency-closet random replacement/deletion to mapload so
  nullspace shipyard preparation is deterministic.
- `code/modules/mapping/mapping_helpers.dm` - accepts an explicit completed
  shipyard target and serialized DMM vars, then applies airlock, air-alarm,
  and APC behavior through the actual inherited helper subtype.
- `code/modules/power/lighting/light.dm` - permits initialized light fixtures
  to remain safely in nullspace until atomic shipyard placement.
- `code/modules/power/power.dm` - ignores deferred cable icon refreshes whose
  turf was deleted during shuttle/test cleanup.

### Config (map JSON, not .dmm)

- Every playable map's JSON (metastation, icebox, tramstation, blueshift,
  oceanpubby, and the rest) - `space_ruin_levels: 0`,
  `space_empty_levels: 0`, `overmap_space_ruins: true`. Debug and event
  maps zero the legacy levels without taking overmap ruins.

## Credits

Original Whitesands code: Whitesands contributors. Forward-port for
ss13-blastwave: see git history.
