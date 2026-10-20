class_name TrackData
extends RefCounted
## Immutable track geometry sampled at a fixed interval.
##
## Everything that needs "where is the track" (karts, AI, props, minimap,
## ranking) reads from here. Points come from data/track_layout.json, which is
## produced by tools/track_builder.py, so the layout is authored offline and
## only consumed at runtime.

const DEFAULT_LAYOUT := "res://data/track_layout.json"

var points := PackedVector3Array()   ## centre line, world space
var tangents := PackedVector3Array() ## unit forward at each sample
var rights := PackedVector3Array()   ## unit right (horizontal)
var normals := PackedVector3Array()  ## surface up
var cum := PackedFloat32Array()      ## arc length at each sample
var curvature := PackedFloat32Array()## radius of curvature in metres
var step := 2.0
var length := 0.0
var road_width := 12.0
var wall_height := 0.8
var start_offset := 0.0
var finish_offset := 0.0
var ramps := PackedFloat32Array()
var ramp_length := 16.0
var boosts := PackedFloat32Array()
var item_rows := PackedFloat32Array()
var checkpoints := PackedFloat32Array()
var track_name := ""

static var _cache: TrackData = null


static func load_default() -> TrackData:
	if _cache != null:
		return _cache
	var data := TrackData.new()
	data._read(DEFAULT_LAYOUT)
	_cache = data
	return data


func _read(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("TrackData: cannot read %s" % path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("TrackData: malformed layout %s" % path)
		return
	var d: Dictionary = parsed
	track_name = str(d.get("name", "Track"))
	step = float(d.get("step", 2.0))
	road_width = float(d.get("road_width", 12.0))
	wall_height = float(d.get("wall_height", 0.8))
	start_offset = float(d.get("start_offset", 6.0))
	finish_offset = float(d.get("finish_offset", 0.0))
	for raw: Variant in d.get("points", []):
		var arr: Array = raw
		points.append(Vector3(float(arr[0]), float(arr[1]), float(arr[2])))
	for key: String in ["ramps", "boosts", "item_rows", "checkpoints"]:
		var dst := PackedFloat32Array()
		for raw: Variant in d.get(key, []):
			dst.append(float(raw))
		match key:
			"ramps": ramps = dst
			"boosts": boosts = dst
			"item_rows": item_rows = dst
			"checkpoints": checkpoints = dst
	ramp_length = float(d.get("ramp_length", 16.0))
	length = float(d.get("length", maxf(0.0, (points.size() - 1) * step)))
	_build_frames()


func _build_frames() -> void:
	var n := points.size()
	tangents.resize(n)
	rights.resize(n)
	normals.resize(n)
	cum.resize(n)
	curvature.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + points[i].distance_to(points[i - 1])
	for i in n:
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, n - 1)]
		var t := next - prev
		t.y = 0.0
		if t.length_squared() < 0.0001:
			t = Vector3.FORWARD
		t = t.normalized()
		tangents[i] = t
		rights[i] = t.cross(Vector3.UP).normalized()
		var slope := (next.y - prev.y) / maxf(0.001, Vector2(next.x - prev.x, next.z - prev.z).length())
		normals[i] = (Vector3.UP - t * slope).normalized()
	# signed curvature -> radius, smoothed with a small window
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var a := tangents[maxi(i - 3, 0)]
		var b := tangents[mini(i + 3, n - 1)]
		var ang := absf(a.signed_angle_to(b, Vector3.UP))
		var dist := maxf(0.001, points[mini(i + 3, n - 1)].distance_to(points[maxi(i - 3, 0)]))
		raw[i] = dist / maxf(0.0001, ang)
	for i in n:
		curvature[i] = raw[i]


func sample_distance(i: int) -> float:
	return cum[clampi(i, 0, cum.size() - 1)] if cum.size() > 0 else 0.0


func index_at(s: float) -> int:
	if cum.is_empty():
		return 0
	var clamped := clampf(s, 0.0, cum[cum.size() - 1])
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if cum[mid] < clamped:
			lo = mid + 1
		else:
			hi = mid
	return lo


func position_at(s: float) -> Vector3:
	var i := index_at(s)
	if i <= 0:
		return points[0] if points.size() > 0 else Vector3.ZERO
	var span := cum[i] - cum[i - 1]
	var t := 0.0 if span <= 0.0001 else clampf((s - cum[i - 1]) / span, 0.0, 1.0)
	return points[i - 1].lerp(points[i], t)


func tangent_at(s: float) -> Vector3:
	var i := index_at(s)
	if i <= 0:
		return tangents[0] if tangents.size() > 0 else Vector3.FORWARD
	var span := cum[i] - cum[i - 1]
	var t := 0.0 if span <= 0.0001 else clampf((s - cum[i - 1]) / span, 0.0, 1.0)
	var v := tangents[i - 1].lerp(tangents[i], t)
	v.y = 0.0
	return v.normalized()


func right_at(s: float) -> Vector3:
	var t := tangent_at(s)
	return t.cross(Vector3.UP).normalized()


func radius_at(s: float) -> float:
	return curvature[clampi(index_at(s), 0, curvature.size() - 1)]


## Projects a world position onto the track, searching only near `hint_index`.
## Returns {index, distance, lateral, forward_offset} where `distance` is the
## arc length of the closest centre-line sample.
func project(pos: Vector3, hint_index: int, window: int = 14) -> Dictionary:
	if points.is_empty():
		return {"index": 0, "distance": 0.0, "lateral": 0.0, "signed": 0.0}
	var best_i := clampi(hint_index, 0, points.size() - 1)
	var best_d := pos.distance_squared_to(points[best_i])
	var lo := maxi(0, best_i - window)
	var hi := mini(points.size() - 1, best_i + window)
	for i in range(lo, hi + 1):
		var d := pos.distance_squared_to(points[i])
		if d < best_d:
			best_d = d
			best_i = i
	# refine with a segment projection so progress is continuous
	var s := cum[best_i]
	var lateral := 0.0
	var signed := 0.0
	for pass_i in 2:
		var j := clampi(best_i - 1 + pass_i, 0, points.size() - 2)
		var a := points[j]
		var b := points[j + 1]
		var ab := b - a
		var ab_len2 := ab.length_squared()
		if ab_len2 < 0.0001:
			continue
		var t := clampf((pos - a).dot(ab) / ab_len2, 0.0, 1.0)
		var proj := a + ab * t
		var d := pos.distance_squared_to(proj)
		if d <= best_d + 0.0001:
			best_d = d
			best_i = j
			s = cum[j] + ab.length() * t
			var r := rights[j]
			signed = (pos - proj).dot(r)
			lateral = absf(signed)
	return {"index": best_i, "distance": s, "lateral": lateral, "signed": signed}


func next_checkpoint(s: float) -> float:
	for c in checkpoints:
		if c > s + 0.5:
			return c
	return finish_offset


func grid_slot(index: int) -> Dictionary:
	## 2 columns x 3 rows, staggered; index 0 is the player on the last row.
	var row := index / 2
	var col := index % 2
	var s := start_offset + 6.0 - row * 7.0
	var offset := 2.6 if col == 0 else -2.6
	return {"s": maxf(s, 2.0), "offset": offset}


func spawn_transform(s: float, lateral: float) -> Transform3D:
	var p := position_at(s) + right_at(s) * lateral
	var t := tangent_at(s)
	var basis := Basis.looking_at(t, Vector3.UP)
	return Transform3D(basis, p + Vector3.UP * 0.6)


## If s is within `window` metres before a ramp lip, returns the lip offset, else -1.
func ramp_lip_near(s: float, window := 2.5) -> float:
	for r in ramps:
		var lip := r + ramp_length
		if s >= lip - window and s <= lip + 0.5:
			return lip
	return -1.0


## Steepest road slope (rise / run) in the few metres before s.
func slope_before(s: float, span := 4.0) -> float:
	var best := -INF
	var x := s - span
	while x < s:
		best = maxf(best, (position_at(x + 1.0).y - position_at(x).y))
		x += 0.5
	return best
