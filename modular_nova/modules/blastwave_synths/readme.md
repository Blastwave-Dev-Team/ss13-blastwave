## Title: Derelict military synths

MODULE ID: BLASTWAVE_SYNTHS

### Description:

Hostile derelict hardware for ruins, plus the coolant blood that makes it read
as a distinct hardware line from the playable oil-blooded synth.

**Coolant blood** — `/datum/blood_type/coolant` and `/datum/reagent/coolant`.
Milky cyan-white (`BLOOD_COLOR_COOLANT`, deliberately not `#FFFFFF`, which
vanishes on light floors), and unlike oil it is not a fuel subtype, so military
synths cannot be set on fire by their own blood. Dries to a chalky film rather
than staying wet, which is how you tell a coolant pool from an oil pool.

**`/datum/species/synthetic/military`** — a corpse-and-mob-only chassis whose
only real difference from the playable synth is `exotic_bloodtype`. Everything
else (synth organs, synth bodyparts, `TRAIT_ROBOTIC_DNA_ORGANS`) is inherited,
so surgery on a body still yields real synth organs. It is locked out of player
hands three ways, because the point is that ruin bodies read as military
hardware, not that anyone can play one:

- `check_roundstart_eligible()` returns `FALSE`, so it is never a roundstart race
- `always_customizable = FALSE` keeps it out of character preferences
- `changesource_flags = MIRROR_BADMIN` narrows the parent's flags so it cannot
  leak out through pride mirrors, slime extracts, race swaps or ERT spawns

It also needs its own `id` (`SPECIES_SYNTH_MILITARY`): `GLOB.species_list` is
keyed on `id`, so reusing `SPECIES_SYNTH` would collide with the playable synth.

**`/mob/living/basic/trooper/blastwave_synth`** and
**`/mob/living/basic/blastwave_cyborg`** — the actual ruin mobs, sharing
`FACTION_BLASTWAVE_DERELICT` so they do not shoot each other.

#### Why the trooper overrides `get_bloodtype()`

Setting `exotic_bloodtype` on the species is not sufficient, because
`/mob/living/basic` mobs never consult species for combat blood.
`/mob/living/get_bloodtype()` routes anything `MOB_ROBOTIC` straight to oil.
Overriding it on the trooper is what actually colours the flying splatter
(`temp_visual`), the floor decal (`make_blood_splatter`), and blood left on
weapons and clothing (`get_blood_dna_list`). The global robotic-to-oil fallback
is left alone on purpose.

Separately, `/mob/living/basic` inherits `default_blood_volume = 0`, which makes
`CAN_HAVE_BLOOD` false and suppresses every splatter regardless of blood type,
so the trooper sets `default_blood_volume = BLOOD_VOLUME_NORMAL`.

### TG Proc/File Changes:

- `code/modules/mob/living/basic/trooper/trooper.dm`: new
  `var/species_path = /datum/species/human`, forwarded to
  `apply_dynamic_human_appearance()` in `Initialize()`. The trooper mob builds
  its sprite from a generated human dummy, and there is no hook to influence
  that species without either this two-line change or generating the appearance
  twice per spawn. Defaults to human, so no existing trooper changes.

### Master file additions

- N/A

### Defines:

- `code/__DEFINES/~nova_defines/blood.dm`: `BLOOD_TYPE_COOLANT`,
  `BLOOD_COLOR_COOLANT`
- `code/__DEFINES/~nova_defines/DNA.dm`: `SPECIES_SYNTH_MILITARY`
- `code/__DEFINES/~nova_defines/factions.dm`: `FACTION_BLASTWAVE_DERELICT`

### Included files that are not contained in this module:

- N/A

### Credits:

Blastwave.
