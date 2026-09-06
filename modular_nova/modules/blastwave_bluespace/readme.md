## Title: Bluespace interdiction and unstable bluespace

MODULE ID: BLASTWAVE_BLUESPACE

### Description:

Two cooperating hazards used to fence players into an encounter.

**Z-level teleport jam** — a refcounted registry (`GLOB.teleport_jam_sources`)
of sources interdicting a given Z. While a Z is jammed, nothing may teleport
into or out of it. `add_teleport_jam()` / `remove_teleport_jam()` take a source
so overlapping jammers do not clobber each other, and `is_teleport_jammed()`
also honours the static `ZTRAIT_NO_TELEPORT` Z-trait for mapped-in dead zones.
`/obj/machinery/teleport_jammer` is the reusable machine wrapper; it drops its
jam when it loses power, breaks, or moves off-Z.

**Unstable bluespace field** — a global singleton
(`/datum/unstable_bluespace_field`) that listens on
`COMSIG_GLOB_MOVABLE_POST_TELEPORT` and scatters, hurts, or misdelivers anything
that completes a teleport anywhere in the world while at least one source is
active. It deliberately watches *successful* teleports rather than gating them,
so it stacks on top of the jam: the jam says "you cannot leave this Z", the
field says "teleporting at all is a bad idea right now".

`/obj/machinery/unstable_field_generator` is the gravity-generator lookalike
that sources the field, built as a main tile plus decorative part tiles, and
shut down by feeding it keycards.

#### Why the jam lives in `check_teleport_valid()`

Putting the check at that choke point is what makes quantum pads, hand
teleporters, bags of holding, and syndicate teleporters all obey it for free,
because they route through `do_teleport()` without `forced`. Anything passing
`forced = TRUE` (admin moves, ghost movement, gateways) is intentionally
unaffected.

The new `bypass_jam` argument exists so a single deliberate exception — the
hierophant club — can punch through interdiction while still being exposed to
the unstable field. It defaults to `FALSE`, so no existing caller changes
behaviour.

### TG Proc/File Changes:

- `code/datums/helper_datums/teleport.dm`: `proc/do_teleport` (new `bypass_jam`
  arg, forwarded to `check_teleport_valid()` and to buckled riders; new
  `SEND_GLOBAL_SIGNAL(COMSIG_GLOB_MOVABLE_POST_TELEPORT)` next to the existing
  per-atom `COMSIG_MOVABLE_POST_TELEPORT`), `proc/check_teleport_valid` (new
  `bypass_jam` arg and the interdiction check itself)
- `code/game/objects/effects/phased_mob.dm`: `proc/try_move_adjacent` — jaunt
  movement never calls `do_teleport()`, so it needs its own check alongside the
  existing `ZTRAIT_NOPHASE` one
- `code/modules/mining/lavaland/mining_loot/megafauna/hierophant.dm`:
  `proc/teleport_mob` — passes `bypass_jam = TRUE`, the one player-facing
  exception

### Master file additions

- #NEW `modular_nova/master_files/code/modules/mining/equipment/wormhole_jaunter.dm`:
  `/obj/item/wormhole_jaunter/get_destinations` — the jaunter picks its own exit
  before teleporting, so it never reaches the `check_teleport_valid()` gate.
  Filters interdicted beacons out of the parent's candidate list.

### Defines:

- `code/__DEFINES/~nova_defines/maps.dm`: `ZTRAIT_NO_TELEPORT`
- `code/__DEFINES/~nova_defines/signals.dm`: `COMSIG_GLOB_MOVABLE_POST_TELEPORT`

### Included files that are not contained in this module:

- N/A

### Credits:

Blastwave.
