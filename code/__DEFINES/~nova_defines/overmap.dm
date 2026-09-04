// MODULE ID: OVERMAP
// Cross-file defines for the overmap module. Per the Nova handbook,
// any define used in more than one file lives here.

/// Z-trait flagging the dedicated overmap grid Z-level.
#define ZTRAIT_OVERMAP "Overmap"

/// Width/height of the overmap grid (square).
#define OVERMAP_DIMENSIONS 64

/// Cap on placement retries when picking a free overmap tile.
#define MAX_OVERMAP_PLACEMENT_ATTEMPTS 100

/// Minimum chebyshev distance a placed POI must keep from the star at the
/// center of the grid. The star sprite is drawn from `overmap_large.dmi`
/// (96x96, with `pixel_x = pixel_y = -32`), so it visually occupies a 3x3
/// tile footprint centered on its own tile. A buffer of 2 keeps any 1x1
/// POI sprite just outside that footprint.
#define OVERMAP_STAR_BUFFER 2

// Generator strategies. Config-selectable via `overmap_generator_type`.
#define OVERMAP_GENERATOR_RANDOM "Random"
#define OVERMAP_GENERATOR_SOLAR "Solar"

// Dock-id prefixes used by dynamic-encounter docks. Renamed away from WS'
// "whiteship" because ss13-blastwave already ships `whiteship_*.dmm` shuttle
// templates that would collide.
#define OVERMAP_DOCK_PREFIX "overmap_ship"
#define OVERMAP_FERRY_PREFIX "overmap_ferry"

// --- Named site Z-level seeding ---

/// Ruins with max(width, height) at or below this side length pack onto shared cluster Zs.
#define OVERMAP_CLUSTER_RUIN_MAX_SIDE 30
/// Minimum chebyshev gap (tiles) between ruin footprints on a cluster Z.
#define OVERMAP_CLUSTER_MIN_SEPARATION 60
/// Min chebyshev gap between a landing zone and a ruin (LZs only need clearance,
/// not the wide ruin-ruin debris spacing — that gap leaves dense clusters with 0 LZs).
#define OVERMAP_SITE_LZ_RUIN_SEPARATION 8
/// Edge margin (tiles) from TRANSITIONEDGE when placing ruins / LZs on a site Z.
#define OVERMAP_SITE_EDGE_MARGIN 8
/// Side length of each seeded landing zone on a site Z.
#define OVERMAP_SITE_LZ_SIDE 40
/// Extra tiles the astrogation camera may roam past an LZ bbox.
#define OVERMAP_SITE_CAMERA_MARGIN 3
/// Placement attempts before giving up on a ruin / LZ anchor.
#define OVERMAP_SITE_PLACE_ATTEMPTS 80
/// Traits for dedicated overmap site Z-levels (self-loop so pods stay on-Z).
#define ZTRAITS_OVERMAP_SITE list(ZTRAIT_LINKAGE = SELFLOOPING)

// Overmap object IDs.
#define MAIN_OVERMAP_OBJECT_ID "home"
#define AWAY_OVERMAP_OBJECT_ID_MINING "mining"
#define DES_TWO_OVERMAP_OBJECT_ID "des_two"

// Affiliation flags for cross-faction stealth.
#define OVERMAP_AFFILIATION_NT "nt"
#define OVERMAP_AFFILIATION_DS2 "ds2"
#define OVERMAP_AFFILIATION_NEUTRAL "neutral"

/// Programmable landing controller board: lock pad+console to an overmap faction.
#define LANDING_CONTROLLER_LOCK_FACTION "faction"
/// Programmable landing controller board: lock console to one ID owner; pad stays open.
#define LANDING_CONTROLLER_LOCK_USER "user"

// Shipyard fabricator construction phases. Networks precede structure because a
// pipe or cable is only hidden by the deck laid over it: hiding runs off the
// turf change, so anything printed onto a finished deck sits on top of it.
#define SHIPYARD_PHASE_RODS 1
#define SHIPYARD_PHASE_PLATING 2
#define SHIPYARD_PHASE_FRAMES 3
#define SHIPYARD_PHASE_NETWORKS 4
#define SHIPYARD_PHASE_STRUCTURE 5
#define SHIPYARD_PHASE_FINAL 6
#define SHIPYARD_PHASE_COMMISSIONING 7

// Declarative shipyard operation kinds.
#define SHIPYARD_OP_RODS "rods"
#define SHIPYARD_OP_PLATING "plating"
#define SHIPYARD_OP_GIRDER "girder"
#define SHIPYARD_OP_MACHINE_FRAME "machine_frame"
#define SHIPYARD_OP_COMPUTER_FRAME "computer_frame"
#define SHIPYARD_OP_TURF "turf"
#define SHIPYARD_OP_OBJECT "object"
#define SHIPYARD_OP_GENERATED "generated"
#define SHIPYARD_OP_MACHINE "machine"
#define SHIPYARD_OP_COMPUTER "computer"
#define SHIPYARD_OP_COMMISSION "commission"
#define SHIPYARD_OP_DECAL "decal"

// Declarative construction-route strategies. A route decides how one mapped
// type is reproduced; the material policy separately decides what it costs.
/// Initialize in nullspace, prepare, place atomically, then commission.
#define SHIPYARD_ROUTE_GENERATE "generate"
/// Construct directly on the target turf, then commission. Used by networks.
#define SHIPYARD_ROUTE_PLACE "place"
/// Machine frame plus circuit board and stock parts.
#define SHIPYARD_ROUTE_MACHINE "machine"
/// Computer frame plus circuit board and glass.
#define SHIPYARD_ROUTE_COMPUTER "computer"
/// Replay a map spawner as the concrete types it would have produced.
#define SHIPYARD_ROUTE_EXPAND "expand"
/// Apply a turf decal. Free, since it is paint rather than construction.
#define SHIPYARD_ROUTE_PAINT "paint"
/// Record the target instead of building it.
#define SHIPYARD_ROUTE_SKIP "skip"
/// Another phase already accounts for the target, so the manifest stays silent
/// about it rather than reporting it as something the build left out.
#define SHIPYARD_ROUTE_OMIT "omit"

// Grouping for manifest content the shipyard does not construct.
/// Cosmetic or map-only content that never needed construction.
#define SHIPYARD_SKIP_IGNORED "ignored"
/// Deliberately refused: unsafe, stateful, or organic composition.
#define SHIPYARD_SKIP_BLACKLISTED "blacklisted"
/// No construction route or material recipe could be derived.
#define SHIPYARD_SKIP_UNSUPPORTED "unsupported"

/// Recursion guard when replaying map spawners as concrete construction targets.
#define SHIPYARD_EXPANSION_DEPTH 3

// Ship state machine.
#define OVERMAP_SHIP_IDLE "idle"
#define OVERMAP_SHIP_FLYING "flying"
#define OVERMAP_SHIP_DOCKING "docking"
#define OVERMAP_SHIP_UNDOCKING "undocking"

// Dynamic-encounter planet flavors (reserved for future multi-Z planetary
// bodies: several content clusters under one overmap tile / docking ports).
#define DYNAMIC_WORLD_LAVA "lava"
#define DYNAMIC_WORLD_ICE "ice"
#define DYNAMIC_WORLD_JUNGLE "jungle"
#define DYNAMIC_WORLD_SAND "sand"

// --- Encounter & event constants ---

/// Global cooldown between dynamic encounter loads (prevents rapid-fire reservation spam).
#define OVERMAP_ENCOUNTER_COOLDOWN (90 SECONDS)

/// Cooldown between active radar scans from a single ship.
#define OVERMAP_SCAN_COOLDOWN (5 SECONDS)

/// Chebyshev tile range for docking and direct overmap interactions.
#define OVERMAP_INTERACTION_RANGE 1

/// Time before a scanned contact fades from the radar if not re-scanned.
#define OVERMAP_SCAN_DECAY (30 SECONDS)

/// Station dish: full 360° sweep uses this short chebyshev/tile range.
#define OVERMAP_RADAR_WIDE_RANGE 6
/// Station dish: narrowest cone uses this long range.
#define OVERMAP_RADAR_NARROW_RANGE 32
/// Narrowest sweep cone the dish will accept, in degrees.
#define OVERMAP_RADAR_MIN_ARC 30
/// Default packet compression when no processor is in the path.
#define OVERMAP_RADAR_DEFAULT_COMPRESSION 45
/// Rolling sweep transcripts kept on the radar console.
#define OVERMAP_RADAR_TRANSCRIPT_SWEEPS 5
/// Shared network id for mapped Flight Ops radar machines.
#define OVERMAP_RADAR_NETWORK_FOC "flightops"
/// Shared autolinker token for mapped Flight Ops radar machines and consoles.
#define OVERMAP_RADAR_AUTOLINK_FOC "foc"
/// Max characters for an operator track label on a radar console.
#define OVERMAP_RADAR_TRACK_NAME_MAX 12

// --- Physics constants ---

/// SSovermap global tick (events). Entity physics and orbits use SSfastprocess.wait (also 0.2s).
#define OVERMAP_PHYSICS_WAIT 2

/// Minimum interval between throttled `update_screen()` rebuilds during flight (~20fps).
#define OVERMAP_SCREEN_UPDATE_INTERVAL 0.5 SECONDS

/// Max pixel displacement per physics tick. Prevents ships from clipping
/// through edge turfs. Must be less than ICON_SIZE_ALL (32) to guarantee
/// no tile-skipping. At 5Hz and the hard speed limit of 2, peak displacement
/// is 12.8px/tick — comfortably under this cap.
#define OVERMAP_INTERPOLATE_LIMIT 16

/// Velocity epsilon: below this threshold, consider the ship stopped.
/// Must stay below one assisted hall/partial-throttle acceleration step.
#define OVERMAP_VELOCITY_EPSILON 0.00001

/// Gravitational constant for ISP/escape velocity calculations.
#define OVERMAP_G0 9.8

/// Emergency integration ceiling in tiles/second. Normal cruise is the lower
/// flight-assisted envelope derived from thrust, mass, and braking distance.
#define OVERMAP_MAX_SPEED 2

/// Maneuverability: how quickly actual velocity converges on desired (0..1 per second).
/// Retained for station-keeping / legacy autopilot; forward flight accel uses thrust/mass.
#define OVERMAP_MANEUVERABILITY 0.8

/// Converts thrust/mass into tiles/s² toward the throttle target.
/// At 0.029, one healthy HNT (30 thrust) on a mass-100 ship crosses the
/// 64×64 playable diagonal in roughly six minutes at full throttle.
#define OVERMAP_THRUST_ACCEL_SCALE 0.029

/// Flight computer target stopping distance in overmap tiles. The assisted
/// speed envelope is sqrt(2 * available_acceleration * this distance).
#define OVERMAP_ASSIST_BRAKING_DISTANCE 4

/// Emergency recovery brake authority relative to normal rated braking.
#define OVERMAP_EMERGENCY_BRAKE_MULTIPLIER 3
/// One-shot hull integrity cost at minimum and maximum flight speed.
#define OVERMAP_EMERGENCY_BRAKE_HULL_DAMAGE_MIN 3
#define OVERMAP_EMERGENCY_BRAKE_HULL_DAMAGE_MAX 15
/// Physical brute damage dealt to each active engine at minimum/maximum speed.
#define OVERMAP_EMERGENCY_BRAKE_ENGINE_DAMAGE_MIN 20
#define OVERMAP_EMERGENCY_BRAKE_ENGINE_DAMAGE_MAX 100

// --- Propellant / fuel injector ---

/// Default mapped fill mole fractions (plasma / oxygen).
#define OVERMAP_FUEL_PLASMA_RATIO 0.6
#define OVERMAP_FUEL_OXYGEN_RATIO 0.4

/// Mapped shuttle chamber pressure target (~3 atm) at matter-bin T1 (servo setpoint).
#define OVERMAP_FUEL_DEFAULT_PRESSURE (3 * ONE_ATMOSPHERE)
/// Extra operating pressure per matter-bin tier above T1.
#define OVERMAP_FUEL_PRESSURE_PER_BIN_TIER (1 * ONE_ATMOSPHERE)
/// Max moles pushed chamber→L2 per tick when over servo pressure (intake stays gated).
#define OVERMAP_FUEL_RELIEF_RATE 5

/// Thrust-to-moles knob; tune for ~10 min full-tank burn at full throttle.
#define OVERMAP_PROP_MOLES_PER_THRUST 0.05

/// Nominal max ISP for thrust-efficiency display in the fuel injector UI.
#define FUEL_INJECTOR_ISP_NOMINAL_MAX 1.5

/// Layer-2 propellant manifold between fuel injectors and HNT engines.
#define OVERMAP_HNT_FEED_LAYER 2

/// Max moles transferred chamber → L2 feed per atmos tick while idle (pressure-regulated).
/// Kept well below typical chamber capacity (~9 mol at 3 atm) so idle ticks cannot empty the chamber.
#define OVERMAP_FEED_TRANSFER_RATE 1.5
/// Max moles chamber → L2 per atmos tick while engines want thrust (hot inventory turnover).
/// Kept below ~half a T1 chamber so cold L1 refill cannot quench the fire in one tick.
#define OVERMAP_FEED_THRUST_TRANSFER_RATE 3.5
/// Minimum chamber-vs-feed pressure delta (kPa) before feed push runs.
#define OVERMAP_FEED_MIN_DELTA_P 1
/// Target L2 feed pressure (kPa) to keep primed while idle; stop pushing once reached.
#define OVERMAP_FEED_BUFFER_PRESSURE (0.5 * ONE_ATMOSPHERE)
/// Never transfer more than this fraction of current chamber moles in one tick (idle).
#define OVERMAP_FEED_MAX_CHAMBER_FRACTION 0.1
/// Chamber fraction cap while thrusting — residence time for chemistry before refill.
#define OVERMAP_FEED_THRUST_CHAMBER_FRACTION 0.25
/// Inlet charge is heated at least this far above ignition while the chamber is lit.
#define OVERMAP_INLET_HEAT_MARGIN 25
/// Multiplier on glow-plug wattage for heating L1 charge while ignited.
/// Thrust refill (~3 mol/tick × ~130 J/mol/K × ~100 K) needs ~40 kJ/tick; base
/// preheat alone (~10 kJ at 0.5 spt) was quenching the chamber.
#define OVERMAP_INLET_HEAT_POWER_MULT 20

/// L2 pressure (kPa) at which mass-flow spool-up is effectively instant.
#define OVERMAP_SPOOL_FULL_RAIL_PRESSURE OVERMAP_FUEL_DEFAULT_PRESSURE
/// Minimum spool-up rate (mol/s²) even on a near-empty rail ("revving").
#define OVERMAP_SPOOL_MIN_ACCEL 2
/// Spool-down rate (mol/s²); faster than spool-up so throttle cuts feel responsive.
#define OVERMAP_SPOOL_DECEL 80
/// Atmos ticks below ignition temperature before forced flameout (clears chamber_ignited).
#define OVERMAP_COLD_FLAMEOUT_TICKS 5

#define OVERMAP_THERMAL_EXHAUST_TEMP 2000
#define OVERMAP_CHEMICAL_ISP_BONUS 1.15
#define OVERMAP_EXHAUST_ISP_THRESHOLD 0.5

/// Max LINDA react() iterations per burn tick.
#define OVERMAP_REACT_ITERATIONS 5

/// Fuel injector glow-plug heater wattage per micro laser tier (heat delivered to the chamber).
#define OVERMAP_PREHEAT_POWER_BASE 20000
/// Highest chamber preheat setpoint (K) reachable at a given micro laser rating.
#define OVERMAP_PREHEAT_SETPOINT_MAX(rating) (500 + 250 * ((rating) - 1))
/// Energy (joules) billed per igniter spark attempt, successful or not.
#define OVERMAP_IGNITE_SPARK_ENERGY 2000
/// Throttle below this is treated as "no thrust" for propellant draw.
#define OVERMAP_THRUST_EPSILON 0.01
/// Mass-flow / spool rates below this are treated as zero.
#define OVERMAP_MOL_S_EPSILON 0.001

// --- Ship control flags (bitfield) ---

/// Ship can be operated from a helm console (ByondUi camera + TGUI).
#define SHIP_CONTROL_CONSOLE (1<<0)
/// Ship can be operated via NIF or neurohelm direct piloting.
#define SHIP_CONTROL_DIRECT (1<<1)

// --- Pilot traits (mutually exclusive paths) ---

#define TRAIT_NIF_PILOTING "trait_nif_piloting"
#define TRAIT_NEUROHELM_PILOTING "trait_neurohelm_piloting"
