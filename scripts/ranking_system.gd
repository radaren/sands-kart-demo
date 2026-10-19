class_name RankingSystem
extends RefCounted
## Live ranking: finished karts by finish order, then by validated progress
## (progress = arc length from TrackData.project, i.e. closest centre-line offset,
## clamped by CheckpointTracker), laps * length added for multi-lap support.

static func total_progress(kart: Kart, lap: int, track_length: float) -> float:
	return (lap - 1) * track_length + kart.progress


static func sort_karts(karts: Array, finish_order: Array) -> Array:
	var arr := karts.duplicate()
	arr.sort_custom(func(a: Kart, b: Kart) -> bool:
		var fa := finish_order.find(a)
		var fb := finish_order.find(b)
		if fa >= 0 and fb >= 0:
			return fa < fb
		if fa >= 0:
			return true
		if fb >= 0:
			return false
		return a.progress > b.progress)
	for i in arr.size():
		(arr[i] as Kart).rank = i + 1
	return arr
