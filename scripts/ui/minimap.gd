class_name Minimap
extends Control
## 2D minimap: track polyline + coloured kart dots (player larger, ringed).

var track: TrackData
var race: RaceManager
var _pts := PackedVector2Array()
var _min := Vector2.ZERO
var _scale := 1.0
var _offset := Vector2.ZERO


func setup(t: TrackData, r: RaceManager) -> void:
	track = t
	race = r
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in range(0, t.points.size(), 3):
		var p := Vector2(t.points[i].x, t.points[i].z)
		lo = lo.min(p)
		hi = hi.max(p)
	_min = lo
	var span := hi - lo
	_scale = minf((size.x - 16.0) / maxf(span.x, 1.0), (size.y - 16.0) / maxf(span.y, 1.0))
	_offset = (size - span * _scale) * 0.5
	_pts.clear()
	for i in range(0, t.points.size(), 3):
		_pts.append(_to_map(t.points[i]))


func _to_map(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - _min) * _scale + _offset


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35), true)
	if track == null:
		return
	draw_polyline(_pts, Color(0.25, 0.18, 0.1, 0.9), 7.0, true)
	draw_polyline(_pts, Color(0.95, 0.85, 0.65), 4.0, true)
	draw_circle(_to_map(track.position_at(track.finish_offset)), 5.0, Color.WHITE)
	if race == null:
		return
	for k: Kart in race.karts:
		var p := _to_map(k.global_position)
		if k.is_player:
			draw_circle(p, 8.0, Color.WHITE)
			draw_circle(p, 6.0, k.body_color)
		else:
			draw_circle(p, 5.0, k.body_color.darkened(0.2))
