# Journal save behavior

This document is the release contract for the journal-save change in
`scripts/journal_save_state.gd` and `scripts/journal_save_store.gd`.

## Save layout

The migration adds a journal section without changing the meaning or shape of
existing story flags:

```json
{
  "save_version": 2,
  "flags": {
    "trusted_edith": true
  },
  "journal": {
    "discovered_ids": ["edith_letter"],
    "read_ids": ["edith_letter"],
    "pinned_id": "edith_letter"
  }
}
```

The rest of the save remains application-owned and is carried through
unchanged. In particular, `flags` is opaque data: the journal layer does not
rename, whitelist, infer, or re-evaluate it.

## Legacy-save behavior

A save made before this change is identified by its missing `journal` section
(and, for the oldest saves, its missing `save_version`).

When that save is loaded after this change:

1. Its full top-level dictionary is copied.
2. Its `flags` dictionary is copied deeply and unchanged.
3. An empty journal is added: no entries are discovered, read, or pinned.
4. Existing unknown fields are retained.
5. No journal discovery, dialogue, reward, or flag callback is run during
   migration.
6. The first subsequent save writes the upgraded layout through a validated
   pending file while retaining a last-known-good `.bak` copy.

A non-dictionary `flags` value is a hard load failure. The loader must not
“repair” that value by discarding player story state.

## Continue behavior

Continue must load and migrate save data before binding scenes or UI. Restore
order is:

1. Load active save; use `.bak` only if the active save is unreadable.
2. Run `JournalSaveState.try_migrate()`.
3. Restore the world and existing story flags.
4. Bind the journal UI from `journal` data.
5. Start in a safe gameplay state, never in a restored dialogue callback or
   open journal modal.

The journal model is idempotent. Loading the same save repeatedly must not
duplicate entries, replay rewards, or mutate flags.

## Release-blocking edge cases

| Edge case | Required behavior | Automated coverage |
| --- | --- | --- |
| Pre-journal save | Loads with an empty journal; every flag and unknown field survives | `legacy_no_journal.json` / `_test_legacy_save_adds_only_journal_defaults` |
| Missing `save_version` | Treated as legacy and upgraded additively | `legacy_no_journal.json` |
| “Keep it quiet” branch | `trusted_edith` remains true across repeated Continue cycles | `keep_it_quiet.json` / `_test_keep_it_quiet_flag_survives_two_continue_cycles` |
| Post-lamp-room save | Puzzle flag and journal discovery/read/pin data all restore | `post_lamp_room.json` / `_test_post_lamp_room_save_keeps_puzzle_and_journal_state` |
| Malformed journal subsection | Defaults only journal state; valid flags remain untouched | `malformed_journal.json` / `_test_malformed_journal_cannot_damage_flags` |
| Malformed `flags` | Fails closed; flags are never coerced or dropped | `_test_invalid_flags_fail_without_coercion` |
| Duplicate or replayed discovery | Produces one stable entry; no rewards or flags fire in migration | `_test_discovery_normalization_is_idempotent` |
| Unknown future save/journal data | Retained; future `save_version` is never downgraded | `future_fields.json` / `_test_unknown_fields_and_future_version_survive` |
| Truncated active save | Loader falls back to last-known-good `.bak` instead of resetting progress | `JournalSaveStore.load_with_recovery()`; add a filesystem integration fixture when the game’s slot paths are wired |
| Failed write promotion | Active save and `.bak` remain intact; return failure rather than deleting either | `JournalSaveStore.save()`; verify on each shipping platform |
| Save during dialogue/journal UI | Resume in safe gameplay UI state; do not restore callbacks or modals | Integration requirement in the game’s Continue owner; add an end-to-end scene test when wired |

## Verification before shipping

Run:

```bash
godot --headless --path . -s res://tests/test_journal_save_state.gd
```

Do not ship if a legacy fixture fails, `trusted_edith` changes after Continue,
the lamp-room fixture loses state, recovery cannot preserve a known-good save,
or a Continue cycle replays journal side effects.
