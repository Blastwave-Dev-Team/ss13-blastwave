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

**Coolant decal variants** — `coolant` subtypes of `blood`, `blood/splatter`,
`blood/old`, `blood/drip`, `blood/trail`, `blood/tracks`, `blood/footprints`,
`blood/gibs`, `blood/gibs/old` and `blood/gibs/robot_debris` (plus the latter's
`limb`/`up`/`down` shapes), and a `coolant/slippery` pool.

These are for **mappers only**. Every decal a synth bleeds at runtime is already
coolant-coloured, because decals are built from the bleeding mob's blood type;
these exist so a ruin can be dressed with a fight that happened before the round
started. Each one carries a `get_default_blood_type()` override — that cannot be
shared, since DM has no multiple inheritance, so it is restated per decal
exactly as upstream's oil variants do it.

Their `name` and `color` are StrongDMM previews rather than runtime values:
`update_name()` rebuilds the name from `base_name`/`base_suffix` plus the blood
type (giving "pool of coolant", "drop of coolant") and `update_blood_color()`
recolours from blood DNA, so both are overwritten on init unless a parent nulls
`base_name`. They are set regardless, or the ruin previews as red puddles.

`robot_debris` is the exception worth knowing: it nulls its own colour and skips
`update_blood_color()`, so the coolant subtypes are visually identical to the
oil originals. Only the reagent and blood DNA differ. `hitsplatter` and
`trail_holder` have no coolant variants because they are runtime-only and never
survive maploading; `innards` and `bubblegum` are organic.

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

These mobs are deliberately voiceless here. They use TG's stock trooper
controllers, which means on a server without the private content pack they say
nothing of their own and still inherit the parent blackboard's
`BB_REINFORCEMENTS_SAY` of `"411 in progress, requesting backup!"` when calling
reinforcements — a Nanotrasen security radio code, which is wrong for them but
harmless without the encounter it belongs to.

The content pack supplies the barks by reopening these types and repointing
`ai_controller` at its own controllers. If you change the `ai_controller` values
below, the pack's overrides need updating in step or they will silently keep
pointing at the old ones.

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
