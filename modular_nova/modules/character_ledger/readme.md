<https://github.com/NovaSector/NovaSector/pull/>

## Character Ledger

Module ID: CHARACTER_LEDGER

### Description

Persistent per-character Nanotrasen credit ledger, plus an ATM that
moves credits between that ledger and the round ID account. Identity is an
immutable `character_uuid` on character prefs, copied onto the mind at spawn.
Ledger rows are INSERT-only. ATM deposits need no PIN; withdrawals require the
character PIN each click.

### TG Proc/File Changes

- `code/__DEFINES/subsystems.dm`: `DB_MINOR_VERSION` bumped for ledger schema
- `code/modules/unit_tests/_unit_tests.dm`: include for
  `~nova/character_ledger.dm`
- `SQL/nova_schema.sql`: `character_identity`,
  `character_ledger_transaction`, `character_ledger_append`
- `SQL/database_changelog.md`: schema 5.40 notes

### Modular Overrides

- `modular_nova/master_files/code/datums/mind/_mind.dm`:
  `var/character_uuid`, `var/atm_pin`
- `modular_nova/master_files/code/modules/mob/dead/new_player/new_player.dm`:
  `create_character` copies UUID, ensures identity, remembers ATM PIN
- `modular_nova/master_files/code/modules/jobs/job_types/_job.dm`:
  `on_job_equipping` remembers ATM PIN after job gear
- `modular_nova/master_files/code/controllers/subsystem/persistence/_persistence.dm`:
  `collect_data` runs evac deposit and ROUND_CLOSE
- `modular_nova/master_files/code/modules/client/preferences.dm`:
  `var/character_uuid`
- `modular_nova/master_files/code/modules/client/preferences_savefile.dm`:
  load/save `character_uuid`

### Defines

- `code/__DEFINES/~nova_defines/character_ledger.dm`:
  `LEDGER_CURRENCY_NTCR`, `LEDGER_CHANNEL_*`, `LEDGER_STATUS_*`,
  `ATM_DEPOSIT_LIMIT_DEFAULT`, `ATM_WITHDRAW_LIMIT_DEFAULT`,
  `EVAC_DEPOSIT_MULTIPLIER_DEFAULT`, `ATM_PIN_MIN`, `ATM_PIN_MAX`

### Included files that are not contained in this module

- `tgui/packages/tgui/interfaces/CharacterATM.tsx`
- `tgui/packages/tgui/interfaces/PreferencesMenu/preferences/features/character_preferences/nova/atm_pin.tsx`
- `code/modules/unit_tests/~nova/character_ledger.dm`
- `config/nova/config_nova.txt`: `ATM_DEPOSIT_LIMIT`, `ATM_WITHDRAW_LIMIT`,
  `EVAC_DEPOSIT_MULTIPLIER`
- `_maps/nova/automapper/automapper_config.toml`: 1x1 arrivals ATM overlays
  for Meta, Delta, Icebox, Tram, Wawa, Nebula, and Catwalk
- `_maps/nova/automapper/templates/*/..._atm.dmm`

### Credits

- Blastwave
