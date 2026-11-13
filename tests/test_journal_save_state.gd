extends SceneTree

const JournalSaveState = preload("res://scripts/journal_save_state.gd")

var _failures := 0


func _init() -> void:
	_test_legacy_save_adds_only_journal_defaults()
	_test_keep_it_quiet_flag_survives_two_continue_cycles()
	_test_post_lamp_room_save_keeps_puzzle_and_journal_state()
	_test_malformed_journal_cannot_damage_flags()
	_test_unknown_fields_and_future_version_survive()
	_test_invalid_flags_fail_without_coercion()
	_test_discovery_normalization_is_idempotent()

	if _failures == 0:
		print("All journal save-state regression tests passed.")
		quit(0)
	else:
		push_error("%s journal save-state regression tests failed." % _failures)
		quit(1)


func _test_legacy_save_adds_only_journal_defaults() -> void:
	var legacy := _fixture("legacy_no_journal.json")
	var original_flags: Dictionary = legacy["flags"].duplicate(true)
	var result := JournalSaveState.try_migrate(legacy)

	_expect_true(result["ok"], "legacy save should load")
	var migrated: Dictionary = result["save"]
	_expect_equal(migrated["flags"], original_flags, "legacy flags must be deep-equal")
	_expect_equal(migrated["unknown_legacy_field"], "keep-me", "unknown top-level data must survive")
	_expect_equal(migrated["journal"]["discovered_ids"], [], "legacy save starts with empty journal")
	_expect_equal(migrated["journal"]["read_ids"], [], "legacy save starts with empty read state")
	_expect_equal(migrated["journal"]["pinned_id"], null, "legacy save starts unpinned")
	_expect_equal(migrated["save_version"], 2, "legacy save upgrades to current version")


func _test_keep_it_quiet_flag_survives_two_continue_cycles() -> void:
	var first := JournalSaveState.try_migrate(_fixture("keep_it_quiet.json"))
	_expect_true(first["ok"], "keep-it-quiet save should load")
	var second := JournalSaveState.try_migrate(first["save"])
	_expect_true(second["ok"], "save should survive a second Continue cycle")
	_expect_equal(second["save"]["flags"]["trusted_edith"], true, "keep-it-quiet must retain trusted_edith")
	_expect_equal(second["save"]["flags"], first["save"]["flags"], "Continue must not mutate canonical flags")


func _test_post_lamp_room_save_keeps_puzzle_and_journal_state() -> void:
	var result := JournalSaveState.try_migrate(_fixture("post_lamp_room.json"))
	_expect_true(result["ok"], "post-lamp-room save should load")
	var save: Dictionary = result["save"]
	_expect_equal(save["world"]["lamp_room_complete"], true, "lamp-room completion must survive")
	_expect_equal(save["journal"]["discovered_ids"], ["lens_notes", "edith_letter"], "journal discovery order must survive")
	_expect_equal(save["journal"]["read_ids"], ["lens_notes"], "journal read state must survive")
	_expect_equal(save["journal"]["pinned_id"], "lens_notes", "journal pin must survive")


func _test_malformed_journal_cannot_damage_flags() -> void:
	var result := JournalSaveState.try_migrate(_fixture("malformed_journal.json"))
	_expect_true(result["ok"], "malformed journal must not reject valid story state")
	var save: Dictionary = result["save"]
	_expect_equal(save["flags"]["skeptic"], true, "malformed journal must not alter skeptic")
	_expect_equal(save["flags"]["trusted_edith"], true, "malformed journal must not alter trusted_edith")
	_expect_equal(save["journal"]["discovered_ids"], [], "malformed journal resets to safe defaults")
	_expect_equal(save["journal"]["read_ids"], [], "malformed read state resets to safe defaults")


func _test_unknown_fields_and_future_version_survive() -> void:
	var result := JournalSaveState.try_migrate(_fixture("future_fields.json"))
	_expect_true(result["ok"], "future-version save should be tolerated")
	var save: Dictionary = result["save"]
	_expect_equal(save["save_version"], 9, "migration must not downgrade a future version")
	_expect_equal(save["future_top_level"]["marker"], "retain", "unknown top-level data must survive")
	_expect_equal(save["journal"]["future_metadata"]["sort"], "custom", "unknown journal data must survive")


func _test_invalid_flags_fail_without_coercion() -> void:
	var result := JournalSaveState.try_migrate({"flags": ["trusted_edith"]})
	_expect_true(not result["ok"], "non-dictionary flags must fail instead of being discarded")


func _test_discovery_normalization_is_idempotent() -> void:
	var raw := {
		"flags": {"believer": true},
		"journal": {
			"discovered_ids": ["radio_log", "radio_log", ""],
			"read_ids": ["radio_log", "edith_note"],
			"pinned_id": "edith_note",
		},
	}
	var first := JournalSaveState.try_migrate(raw)
	var second := JournalSaveState.try_migrate(first["save"])
	_expect_true(first["ok"] and second["ok"], "normalized journal should remain loadable")
	_expect_equal(first["save"]["journal"], second["save"]["journal"], "normalization must be idempotent")
	_expect_equal(first["save"]["journal"]["discovered_ids"], ["radio_log", "edith_note"], "read entries must be discoverable once")


func _fixture(name: String) -> Dictionary:
	var file := FileAccess.open("res://tests/fixtures/%s" % name, FileAccess.READ)
	if file == null:
		push_error("Could not open fixture: %s" % name)
		return {}
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("Fixture is not a JSON dictionary: %s" % name)
		return {}
	return json.data


func _expect_true(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		push_error("%s; expected %s, got %s" % [message, expected, actual])
