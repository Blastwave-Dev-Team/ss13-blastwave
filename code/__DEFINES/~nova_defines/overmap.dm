// MODULE ID: OVERMAP
// Cross-file defines for the overmap module. Per the Nova handbook,
// any define used in more than one file lives here.

/// Z-trait flagging the dedicated overmap grid Z-level.
#define ZTRAIT_OVERMAP "Overmap"

/// Width/height of the overmap grid (square).
#define OVERMAP_DIMENSIONS 20

/// Cap on placement retries when picking a free overmap tile.
#define MAX_OVERMAP_PLACEMENT_ATTEMPTS 100

/// Minimum chebyshev distance a placed POI must keep from the star at the
/// center of the grid. The star sprite is drawn from `overmap_large.dmi`
/// (96x96, with `pixel_x = pixel_y = -32`), so it visually occupies a 3x3
/// tile footprint centered on its own tile. A buffer of 2 keeps any 1x1
/// POI sprite just outside that footprint.
#define OVERMAP_STAR_BUFFER 2

// Generator strategies. Prototype hardcodes RANDOM; SOLAR is reserved for the
// post-prototype config-flagged backlog item.
#define OVERMAP_GENERATOR_RANDOM "Random"
#define OVERMAP_GENERATOR_SOLAR "Solar"

// Dock-id prefixes used by dynamic-encounter docks. Renamed away from WS'
// "whiteship" because ss13-blastwave already ships `whiteship_*.dmm` shuttle
// templates that would collide.
#define OVERMAP_DOCK_PREFIX "overmap_ship"
#define OVERMAP_FERRY_PREFIX "overmap_ferry"

// Overmap object IDs.
#define MAIN_OVERMAP_OBJECT_ID "home"
#define AWAY_OVERMAP_OBJECT_ID_MINING "mining"

// Ship state machine.
#define OVERMAP_SHIP_IDLE "idle"
#define OVERMAP_SHIP_FLYING "flying"
#define OVERMAP_SHIP_DOCKING "docking"
#define OVERMAP_SHIP_UNDOCKING "undocking"

// Dynamic-encounter planet flavors. Defined now (used by deferred dynamic-
// encounter work post-prototype) so the constants exist when refactors land.
#define DYNAMIC_WORLD_LAVA "lava"
#define DYNAMIC_WORLD_ICE "ice"
#define DYNAMIC_WORLD_JUNGLE "jungle"
#define DYNAMIC_WORLD_SAND "sand"

// --- Physics constants ---

/// Physics tick rate in deciseconds. 1ds = 0.1s = 10Hz.
#define OVERMAP_PHYSICS_WAIT 1

/// Max pixel displacement per physics tick. Prevents ships from clipping
/// through edge turfs. Must be less than ICON_SIZE_ALL (32) to guarantee
/// no tile-skipping. 16px/tick at 4Hz = 2 tiles/sec max per axis.
#define OVERMAP_INTERPOLATE_LIMIT 16

/// Velocity epsilon: below this threshold, consider the ship stopped.
#define OVERMAP_VELOCITY_EPSILON 0.001

/// Gravitational constant for ISP/escape velocity calculations.
#define OVERMAP_G0 9.8

/// Max ship speed in tiles/second.
#define OVERMAP_MAX_SPEED 2

/// Maneuverability: how quickly actual velocity converges on desired (0..1 per second).
#define OVERMAP_MANEUVERABILITY 0.8

// --- Ship control flags (bitfield) ---

/// Ship can be operated from a helm console (ByondUi camera + TGUI).
#define SHIP_CONTROL_CONSOLE (1<<0)
/// Ship can be operated via NIF or neurohelm direct piloting.
#define SHIP_CONTROL_DIRECT (1<<1)

// --- Pilot traits (mutually exclusive paths) ---

#define TRAIT_NIF_PILOTING "trait_nif_piloting"
#define TRAIT_NEUROHELM_PILOTING "trait_neurohelm_piloting"
