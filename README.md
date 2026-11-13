# Tidewrack Journal Save Hardening

A focused Godot 4 save-state compatibility module and regression suite for journal persistence.

## Compatibility contract

`JournalSaveState.try_migrate()` is a pure migration boundary:

- Legacy saves without `save_version` or `journal` receive an empty journal.
- The existing `flags` dictionary is copied without whitelisting, renaming, or inference.
- Canonical flags — `skeptic`, `believer`, `trusted_edith`, and `radioed_tom` — are regression-tested through repeated Continue cycles.
- Unknown top-level and journal fields survive migration.
- A malformed journal section safely defaults without touching otherwise valid progress.
- A malformed `flags` value fails loading rather than silently discarding story state.
- Journal normalization is idempotent and contains no UI, dialogue, reward, or discovery-trigger side effects.

`JournalSaveStore` writes a validated `.pending` file first and preserves the prior active file as `.bak` before promotion. A failed promotion fails closed so the active save and recovery copy remain available.

## Integration order

1. Gather the game’s complete state in its existing save owner.
2. Pass that dictionary to `JournalSaveStore.save()`.
3. On Continue, call `load_with_recovery()` before any scene, dialogue, or journal UI binds.
4. Hydrate the world and existing story flags first.
5. Bind the journal view from the returned `journal` data only; do not re-run discovery callbacks.

The adapter intentionally does not restore transient UI state such as an open journal, a dialogue modal, or an in-flight callback.

## Run tests

With Godot 4 available:

```bash
godot --headless --path . -s res://tests/test_journal_save_state.gd
```

The suite covers each release-blocking condition:

| Condition | Fixture / test |
| --- | --- |
| Legacy saves add only journal defaults | `legacy_no_journal.json` |
| “Keep it quiet” retains `trusted_edith` | `keep_it_quiet.json` |
| Lamp-room puzzle and journal state persist | `post_lamp_room.json` |
| Malformed journal data cannot harm flags | `malformed_journal.json` |
| Unknown future fields survive | `future_fields.json` |
| Invalid flags are never coerced away | `test_invalid_flags_fail_without_coercion` |
| Duplicate/replayed discoveries are idempotent | `test_discovery_normalization_is_idempotent` |
