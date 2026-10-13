/// Station trait given by /datum/station_trait/back_in_the_black.
#define STATION_TRAIT_BACK_IN_THE_BLACK "station_trait_back_in_the_black"

/// Revenue target added per enrolled Neuro Fiscal Tracker seat.
#define BITB_GOAL_PER_CREW 2000
/// Revenue target floor, so a low-pop shift still has something to chase.
#define BITB_MIN_GOAL 25000
/// Share of shift revenue returned to living enrolled associates when the target is met.
#define BITB_BONUS_FRACTION 0.5
/// Spare implant cases in the CMO's enrollment kit.
#define BITB_LATEJOIN_IMPLANT_COUNT 6

/// Never implanted; holds no seat.
#define BITB_SEAT_PENDING "pending"
/// Claimed a seat on first implant; keeps it until voided.
#define BITB_SEAT_ACTIVE "active"
/// Released its seat; refuses further implantation.
#define BITB_SEAT_VOIDED "voided"

/// Default overlay heading; admins can replace it.
#define BITB_DEFAULT_GOAL_LABEL "NT SHAREHOLDER GOAL"
/// Longest admin-set overlay heading that still fits beside the numbers.
#define BITB_GOAL_LABEL_MAX_LEN 32

/// Sent on the trait when progress or the goal changes: (earned, goal, goal_label, amount, source)
/// amount and source are null for redraws that should not show a contribution alert.
#define COMSIG_BITB_PROGRESS "bitb_progress"
