// MODULE ID: BLASTWAVE_HARDLIGHT
// Tuning for hard-light projection. The machines live in modular_nova/modules/blastwave_hardlight.

/// Charge a projector holds when fully recovered. Everything below is expressed against this.
#define HARDLIGHT_PAD_MAX_CHARGE 400

/**
 * Charge per second a projector recovers, by capacitor tier.
 *
 * This is the whole room-by-room difficulty gradient: a tier one pad is a nuisance you can clear
 * and then work in peace, a tier four pad is back on its feet before you have finished the task you
 * cleared it for. Mappers pick the tier; nothing else about a projector differs between rooms.
 */
#define HARDLIGHT_RECHARGE_TIER_ONE 4
#define HARDLIGHT_RECHARGE_TIER_TWO 8
#define HARDLIGHT_RECHARGE_TIER_THREE 15
#define HARDLIGHT_RECHARGE_TIER_FOUR 25

/// Fraction of max charge a collapsed projector must recover before it can project again.
#define HARDLIGHT_REACTIVATE_FRACTION 0.8

/**
 * Damage-to-charge conversion, applied after armour.
 *
 * Armour already decides how much of a hit survives; these decide what that survival costs the pad.
 * Stamina is multiplied rather than merely surviving because disablers are meant to be the answer,
 * and a weapon that does nothing to a living target has to do something here or nobody will carry one.
 */
#define HARDLIGHT_DRAIN_COEFF_BRUTE 1
#define HARDLIGHT_DRAIN_COEFF_BURN 1
#define HARDLIGHT_DRAIN_COEFF_STAMINA 3

/// Charge a heavy EMP strips. Halved for light. Ion bolts arrive here rather than through damage.
#define HARDLIGHT_EMP_DRAIN 200
/// One blast usually reaches the pad and the body both. Inside this window they count as one hit.
#define HARDLIGHT_EMP_WINDOW (0.5 SECONDS)

/// Below this fraction of max charge the projection destabilises: hits harder, and is hurt harder.
#define HARDLIGHT_ENRAGE_FRACTION 0.25
/// Drain multiplier applied while destabilised, so a pad that starts losing keeps losing.
#define HARDLIGHT_ENRAGE_DRAIN_MULT 1.5
/// Damage multiplier applied to the avatar's own attacks while destabilised.
#define HARDLIGHT_ENRAGE_DAMAGE_MULT 1.5

/// How often the command core re-scores areas and decides where to stand.
#define HARDLIGHT_DIRECTOR_INTERVAL (2 SECONDS)

/**
 * How much closer a rival plate has to be before the unit will abandon the one it is on.
 *
 * Rooms may carry as many plates as they deserve, and the unit takes whichever is nearest whoever
 * it is going for. Without a margin that turns into a twitch: someone sidesteps, the arithmetic
 * flips, and the body derezzes and reforms two tiles away every couple of seconds. This is the
 * width of the dead band, in tiles, and it wants to be wider than ordinary shuffling.
 */
#define HARDLIGHT_REPAD_MARGIN 3

// Drilling a containment field. An emitter fires every two to ten seconds with a pause every third
// shot, so these are calibrated in bolts rather than in seconds: roughly twenty landed hits.
/// Drill progress needed to breach a containment field.
#define HARDLIGHT_DRILL_REQUIRED 100
/// Progress a single emitter bolt contributes.
#define HARDLIGHT_DRILL_PER_BOLT 5
/// Quiet time after the last bolt before the breach starts closing up again. Comfortably longer
/// than the emitter's own worst-case shot cycle, so ordinary firing never reads as an interruption.
#define HARDLIGHT_DRILL_IDLE_WINDOW (15 SECONDS)
/// Progress lost per second once the drill has gone quiet. Slow on purpose: losing the room should
/// cost ground, not erase the attempt.
#define HARDLIGHT_DRILL_DECAY 1

/// How far from the plate the tether reaches. It comes out of the floor, not out of the body's arm.
#define HARDLIGHT_TETHER_RANGE 2

/// How far the body has to have strayed from its plate before walking it back stops being worth it.
#define HARDLIGHT_RECALL_DISTANCE 4
/// How long the body spends as nothing but a smear of light between plate and floor.
#define HARDLIGHT_RECALL_TRANSIT (0.4 SECONDS)
/// How long a rooted victim needs to pull themselves free unaided.
#define HARDLIGHT_TETHER_BREAKOUT (12 SECONDS)

// Encounter progression. The core owns this; puzzle machinery reads it and pushes it forward.
/// Landed, but the unit has not woken up yet.
#define HARDLIGHT_PHASE_DORMANT 0
/// The unit is hunting. The three field tasks are live.
#define HARDLIGHT_PHASE_ACTIVE 1
/// Containment is down and the core is physically reachable.
#define HARDLIGHT_PHASE_BREACHED 2
/// The matrix has been pulled. The garrison is waking up.
#define HARDLIGHT_PHASE_EXTRACTED 3

// The encounter's palette.
//
// Orange rather than the holopad cyan, and deliberately so: every hologram a player has ever seen
// is blue, so a blue one reads as furniture. This has to say "not that" at a glance and from across
// a room, because the whole first lesson of the encounter is that the rules you know do not apply.
/// Standing light - the body, its beam back to the plate, and the tether.
#define HARDLIGHT_COLOUR "#ff8a2b"
/// The same light with the plate behind it running out. Reads as heat rather than as a hologram.
#define HARDLIGHT_COLOUR_DESTABILISED "#ff3b1f"
/// For anything that casts rather than is cast.
#define HARDLIGHT_LIGHT_COLOUR LIGHT_COLOR_ORANGE

// The three things phase two asks for. Held as a bitfield on the core rather than as a count,
// because the unit should be able to react to *which* one was just taken, not only to how many.
/// A command matrix carrier has been fabricated.
#define HARDLIGHT_OBJECTIVE_CARRIER (1<<0)
/// The core encryption authorization has been written to a card.
#define HARDLIGHT_OBJECTIVE_KEYS (1<<1)
/// A beam emitter has been stood up and pointed at the containment ring.
#define HARDLIGHT_OBJECTIVE_EMITTER (1<<2)
/// All three, for the tier maths.
#define HARDLIGHT_OBJECTIVES_ALL (HARDLIGHT_OBJECTIVE_CARRIER | HARDLIGHT_OBJECTIVE_KEYS | HARDLIGHT_OBJECTIVE_EMITTER)

// How long the unit leaves between unprompted lines. Wide, and wide on purpose: a boss that talks
// on a predictable beat stops being a presence in the room and starts being a metronome.
#define HARDLIGHT_TAUNT_INTERVAL_MIN (90 SECONDS)
#define HARDLIGHT_TAUNT_INTERVAL_MAX (150 SECONDS)

/// Blackboard slot for something the director wants dead ahead of any living target.
#define BB_HARDLIGHT_PRIORITY_TARGET "BB_hardlight_priority_target"
/// Blackboard slot holding the plate-tether ability.
#define BB_HARDLIGHT_TETHER "BB_hardlight_tether"
/// Blackboard slot holding the snap-back-to-the-plate ability.
#define BB_HARDLIGHT_RECALL "BB_hardlight_recall"
