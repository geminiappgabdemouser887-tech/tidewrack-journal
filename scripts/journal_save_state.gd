class_name JournalSaveState
extends RefCounted
## Pure save migration for journal state.
##
## This class deliberately has no scene, UI, dialogue, or reward dependencies.
## Loading a save therefore cannot replay discovery side effects or mutate flags.

const CURRENT_SAVE_VERSION := 2
const LEGACY_SAVE_VERSION := 1

static func try_migrate(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("Save payload must be a dictionary.")

	var source: Dictionary = raw
	var migrated: Dictionary = source.duplicate(true)

	var source_version: int = LEGACY_SAVE_VERSION
	if migrated.has("save_version"):
		var serialized_version: Variant = migrated["save_version"]
		if typeof(serialized_version) != TYPE_INT and typeof(serialized_version) != TYPE_FLOAT:
			return _failure("save_version must be an integer.")
		source_version = int(serialized_version)
		if float(source_version) != float(serialized_version):
			return _failure("save_version must be an integer.")
		if source_version < LEGACY_SAVE_VERSION:
			return _failure("save_version cannot be negative or zero.")

	# Flags are opaque compatibility data. Do not whitelist, rename, or infer them.
	var flags: Variant = migrated.get("flags", {})
	if typeof(flags) != TYPE_DICTIONARY:
		return _failure("flags must be a dictionary when present.")
	migrated["flags"] = (flags as Dictionary).duplicate(true)

	var journal_result := _normalize_journal(migrated.get("journal", {}))
	if not journal_result["ok"]:
		return journal_result
	migrated["journal"] = journal_result["journal"]

	# Never downgrade a save created by a future build. Unknown fields are retained.
	migrated["save_version"] = maxi(source_version, CURRENT_SAVE_VERSION)

	return {
		"ok": true,
		"save": migrated,
		"was_legacy": source_version < CURRENT_SAVE_VERSION,
		"journal_was_repaired": journal_result["was_repaired"],
	}


static func _normalize_journal(value: Variant) -> Dictionary:
	var journal: Dictionary = {}
	var was_repaired := false

	if typeof(value) == TYPE_DICTIONARY:
		# Preserve unknown journal fields for forward compatibility.
		journal = (value as Dictionary).duplicate(true)
	else:
		# Journal is optional in legacy saves; a malformed subsection must not
		# invalidate otherwise valid story progress.
		was_repaired = true

	var discovered := _unique_nonempty_strings(journal.get("discovered_ids", []))
	var read := _unique_nonempty_strings(journal.get("read_ids", []))
	for entry_id in read:
		if not discovered.has(entry_id):
			discovered.append(entry_id)
			was_repaired = true

	var pinned_id: Variant = journal.get("pinned_id", null)
	if typeof(pinned_id) == TYPE_STRING and discovered.has(pinned_id):
		journal["pinned_id"] = pinned_id
	else:
		if pinned_id != null:
			was_repaired = true
		journal["pinned_id"] = null

	journal["discovered_ids"] = discovered
	journal["read_ids"] = read
	return {
		"ok": true,
		"journal": journal,
		"was_repaired": was_repaired,
	}


static func _unique_nonempty_strings(value: Variant) -> Array:
	var result: Array = []
	if typeof(value) != TYPE_ARRAY:
		return result

	for candidate in value:
		if typeof(candidate) != TYPE_STRING:
			continue
		var entry_id: String = candidate
		if not entry_id.is_empty() and not result.has(entry_id):
			result.append(entry_id)
	return result


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
