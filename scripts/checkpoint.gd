class_name CheckpointTracker
extends RefCounted
## Per-kart checkpoint bookkeeping: passes must happen in order, progress is
## clamped just past the next unpassed checkpoint (no shortcut gains), and the
## last passed checkpoint is the respawn anchor.

const SLACK := 30.0

var checkpoints := PackedFloat32Array()
var next_index := 0
var last_passed_s := 0.0


func _init(cps: PackedFloat32Array, start_s: float) -> void:
	checkpoints = cps
	last_passed_s = start_s


## Feed the raw projected progress; returns the validated progress.
func update(raw_progress: float) -> float:
	while next_index < checkpoints.size() and raw_progress >= checkpoints[next_index]:
		last_passed_s = checkpoints[next_index]
		next_index += 1
	if next_index < checkpoints.size():
		return minf(raw_progress, checkpoints[next_index] + SLACK)
	return raw_progress


func all_passed() -> bool:
	return next_index >= checkpoints.size()


func count() -> int:
	return next_index
