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

## Files added

### New modular files

- `modular_nova/modules/overmap/code/overmap_subsystem.dm` - SSovermap.
- `modular_nova/modules/overmap/code/overmap_objects.dm` - turfs, area,
  base `/obj/structure/overmap`, level subtypes (main, mining), star.
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
  `/datum/area_spawn` entries that retrofit existing Nova shuttles with
  helm + nav + engines without `.dmm` edits.
- `modular_nova/modules/overmap/icons/*.dmi` - sprites copied from
  Whitesands and renamed to flatten the icons folder per Nova convention.
- `tgui/packages/tgui/interfaces/HelmConsole.tsx` - the helm UI rewrite.
- `code/__DEFINES/~nova_defines/overmap.dm` - cross-file defines.

### Core file changes (NOVA EDIT ADDITION OVERMAP)

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

## Credits

Original Whitesands code: Whitesands contributors. Forward-port for
ss13-blastwave: see git history.
