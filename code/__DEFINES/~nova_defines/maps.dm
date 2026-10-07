#define AWAYSTART_MAINTSROOM "AWAYSTART_MAINTSROOM"

#define ZTRAIT_JUNGLE_RUINS "Jungle Ruins"
#define ZTRAIT_JUNGLE_CAVE_RUINS "Jungle Cave Ruins"

/// boolean - does this z refuse teleports to and from it. Runtime sources use add_teleport_jam() instead.
#define ZTRAIT_NO_TELEPORT "No Teleport"

/// Range for a jam source covering its whole Z rather than a radius around itself. Lives out here
/// rather than beside add_teleport_jam() because the unit tests compile well before that module does.
#define JAM_RANGE_WHOLE_Z -1
