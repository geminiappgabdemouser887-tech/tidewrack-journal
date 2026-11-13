class_name JournalSaveStore
extends RefCounted
## File adapter for JournalSaveState.
##
## The active file is only replaced after a complete, validated pending file
## exists. The last known-good active file is copied to .bak first so a failed
## promotion cannot silently erase player progress.

const BACKUP_SUFFIX := ".bak"
const PENDING_SUFFIX := ".pending"


static func load_with_recovery(save_path: String) -> Dictionary:
	var primary_result := _load_file(save_path)
	if primary_result.get("ok", false):
		primary_result["recovered_from_backup"] = false
		return primary_result

	var backup_result := _load_file(save_path + BACKUP_SUFFIX)
	if backup_result.get("ok", false):
		backup_result["recovered_from_backup"] = true
		backup_result["primary_error"] = primary_result.get("error", "Unknown load failure.")
		return backup_result

	return {
		"ok": false,
		"error": "Neither the active save nor its backup could be loaded.",
		"primary_error": primary_result.get("error", "Unknown load failure."),
		"backup_error": backup_result.get("error", "Unknown load failure."),
	}


static func save(save_path: String, raw_save: Dictionary) -> Dictionary:
	var migration_result := JournalSaveState.try_migrate(raw_save)
	if not migration_result.get("ok", false):
		return migration_result

	var pending_path := save_path + PENDING_SUFFIX
	var pending_file := FileAccess.open(pending_path, FileAccess.WRITE)
	if pending_file == null:
		return _failure("Could not open pending save: %s" % pending_path)

	pending_file.store_string(JSON.stringify(migration_result["save"]))
	pending_file.flush()
	pending_file.close()

	# Validate the exact bytes written before touching the active save.
	var pending_result := _load_file(pending_path)
	if not pending_result.get("ok", false):
		return _failure("Pending save validation failed: %s" % pending_result.get("error", ""))

	if FileAccess.file_exists(save_path):
		var backup_error := DirAccess.copy_absolute(save_path, save_path + BACKUP_SUFFIX)
		if backup_error != OK:
			return _failure("Could not refresh last known-good backup.")

	# On platforms where rename replaces an existing file, this is an atomic
	# promotion. If that platform guarantee is unavailable, this fails closed:
	# the active file and .bak remain intact rather than deleting either.
	var promotion_error := DirAccess.rename_absolute(pending_path, save_path)
	if promotion_error != OK:
		return _failure("Could not promote validated pending save; active save was left intact.")

	return {
		"ok": true,
		"save": migration_result["save"],
		"backup_path": save_path + BACKUP_SUFFIX,
	}


static func _load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("Save file does not exist: %s" % path)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not open save: %s" % path)

	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return _failure("Save JSON is malformed: %s" % path)

	return JournalSaveState.try_migrate(json.data)


static func _failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"error": message,
	}
