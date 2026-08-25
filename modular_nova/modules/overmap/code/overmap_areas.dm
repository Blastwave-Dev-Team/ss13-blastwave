// MODULE ID: OVERMAP
// Area trees for overmap map sections. Two roots:
//   - Mobile, shuttle-backed vessels (fighter, frigate) hang off /area/shuttle
//     so they inherit the shuttle ceiling/gravity machinery, exactly like the
//     advanced shuttles (e.g. the Manticore /area/shuttle/mining/large/advanced).
//   - Static orbital structures (installation, depot) use a dedicated
//     /area/overmap_structure root, since /area/overmap is already the grid Z.

/* MOBILE SHIP AREAS */

/// Base for overmap vessels whose hull is a real shuttle docking port.
/area/shuttle/overmap
	requires_power = TRUE
	area_limited_icon_smoothing = /area/shuttle/overmap

/// Subcapital ship flown directly via NIF/neurohelm (SHIP_CONTROL_DIRECT).
/area/shuttle/overmap/fighter
	name = "Fighter"

/// Purpose-built overmap ship, typically helm-console piloted.
/area/shuttle/overmap/frigate
	name = "Frigate"

/area/shuttle/overmap/frigate/interdyne_cargo
	name = "Interdyne Cargo"

/area/shuttle/overmap/frigate/tarkon_driver
	name = "Tarkon Driver"

/* STATIC ORBITAL STRUCTURE AREAS */

/// Base for non-mobile orbital structures loaded as their own map section.
/area/overmap_structure
	name = "Orbital Structure"
	requires_power = TRUE
	static_lighting = TRUE
	icon = 'icons/area/areas_station.dmi'
	icon_state = "shuttle"

/// Medium orbital structure (mini-station). Meant to be subclassed per
/// installation into individual sub-areas (e.g. .../installation/medbay).
/area/overmap_structure/installation
	name = "Orbital Installation"

/// Small orbital structure. Single area, not expected to be subclassed.
/area/overmap_structure/depot
	name = "Orbital Depot"
