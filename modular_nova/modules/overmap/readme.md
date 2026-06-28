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
- `modular_nova/modules/overmap/code/overmap_circuits.dm` - circuit
  boards for helm, nav, engine, heater.
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
  site POIs, stealth gating, crosslinked Z prevention, beacon.

### master_files overrides

- `modular_nova/master_files/code/controllers/subsystem/mapping.dm` -
  adds `overmap_space_ruins` var on `/datum/map_config`; extends
  `setup_ruins()` to skip space ruin seeding when flag is set.

### Core file changes (NOVA EDIT ADDITION/CHANGE OVERMAP)

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
  config flag (NOVA EDIT ADDITION - OVERMAP).
- `code/modules/unit_tests/_unit_tests.dm` - include for
  `~nova/overmap_ruins.dm` (NOVA EDIT ADDITION - OVERMAP).

### Config (map JSON, not .dmm)

- `_maps/metastation.json` - `space_ruin_levels: 0`,
  `space_empty_levels: 0`, `overmap_space_ruins: true`.

## Credits

Original Whitesands code: Whitesands contributors. Forward-port for
ss13-blastwave: see git history.
