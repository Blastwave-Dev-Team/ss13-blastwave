https://github.com/Blastwave-Dev-Team/ss13-blastwave/pull/15

## Shuttle Frame Rod Landing Pad Construction

Module ID: SHUTTLE_CONSTRUCTION

### Description:

Allows anchoring shuttle frame rods onto existing station turfs (plating or tiled floors) without replacing the underlying turf. Frame turfs display a manually-smoothed lattice overlay so players can build shuttle plating on top while leaving the landing pad intact when the shuttle departs.

### TG Proc/File Changes:

- `code/datums/elements/shuttle_construction_turf.dm`: `Attach`, `Detach` — hook calls for overlay lifecycle; `pre_turf_changed`, `post_turf_changed` — track layer removal so deconstructing built plating re-exposes the frame rods
- `code/game/turfs/open/floor.dm`: `attackby` — shuttle frame rod and tile handling on tiled floors; `examine` — rod hint line; `rcd_vals`, `rcd_act` — plating instead of wall on frame turfs
- `code/game/turfs/open/floor/plating.dm`: `attackby` — shuttle frame rod and tile handling on plating
- `code/modules/unit_tests/_unit_tests.dm`: includes shuttle construction unit tests
- `code/modules/unit_tests/shuttle_construction.dm`: unit tests for frame rod behavior

### Modular Overrides:

- `modular_nova/modules/shuttle_construction/code/frame_construction.dm`: `shuttle_frame_build_plating_with_tile`, `shuttle_frame_rcd_vals`, `shuttle_frame_rcd_act`
- `modular_nova/modules/shuttle_construction/code/frame_overlays.dm`: `shuttle_construction_turf_reexpose_rods`, `shuttle_construction_turf_overlay_attached`, `shuttle_construction_turf_overlay_detached`, `update_shuttle_frame_overlay`, `remove_shuttle_frame_overlay`, `update_shuttle_frame_neighbor_overlays`, `calculate_shuttle_frame_lattice_bitmask`
- `modular_nova/modules/shuttle_construction/code/frame_rods.dm`: `build_shuttle_frame_with_rods`

### Defines:

- `SHUTTLE_ROD_TRAIT_SOURCE` — fixed trait source string for station-anchored shuttle frame rods (in `code/__DEFINES/~nova_defines/shuttle_construction.dm`)

### Included files that are not contained in this module:

- N/A

### Credits:

- Blastwave contributors
