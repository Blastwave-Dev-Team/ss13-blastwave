// MODULE ID: SPACEPODS
// Equipment slot identifiers and construction-frame restart indices for spacepods.
// Ported from Whitesands (code/__DEFINES/~whitesands_defines/spacepods.dm).

/// Construction step a destroyed pod's wreck frame restarts at (core bolted, no bulkhead or armor).
#define SPACEPOD_FRAME_WRECK_INDEX 7
/// Construction step a pod's frame restarts at when its welded armor is sliced off (armor still bolted on).
#define SPACEPOD_FRAME_ARMOR_INDEX 12

#define SPACEPOD_POWER_SCALE (STANDARD_BATTERY_VALUE / STANDARD_CELL_VALUE)

/// Pixels forward from pod center to cannon muzzle along the facing unit vector (clears 64x64 hull at oblique angles).
#define SPACEPOD_CANNON_FORWARD_OFFSET 48
/// Pixels lateral from pod center to each dual cannon along the perpendicular unit vector.
#define SPACEPOD_CANNON_LATERAL_OFFSET 16

#define SPACEPOD_SLOT_CARGO "cargo"
#define SPACEPOD_SLOT_MISC "misc"
#define SPACEPOD_SLOT_WEAPON "weapon"
#define SPACEPOD_SLOT_LOCK "lock"
