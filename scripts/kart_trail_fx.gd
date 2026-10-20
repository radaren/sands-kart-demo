class_name KartTrailFx
extends Node3D
## V1: per-kart ground effects, web-safe (billboard puffs + one-shot bursts, no
## continuous particle emitters on fast parents - those drew a black quad in the
## Compatibility renderer):
##   - rear-wheel dust, rate and size grow with speed (more off the road)
##   - drift sparks as small bursts in the tier colour
##   - boost flame trail behind the exhausts
##   - landing dust ring
##   - drift skid marks: dark strips on the road that fade after a few seconds

const SAND := Color(0.86, 0.76, 0.58)
const FLAME := Color(1.0, 0.62, 0.18)
const SKID_LIFE := 6.0
const SKID_MAX := 360
const FX_RANGE := 70.0          ## only karts this close to the camera emit

var race: RaceManager
var _acc := {}                  ## kart -> Vector3(dust, spark, flame) accumulators
var _last_skid := {}            ## kart -> [left, right] last points (or null)
var _skids: Array = []          ## [a_l, a_r, b_l, b_r, born] quads: two strips per segment
var _mesh := ImmediateMesh.new()
var _mi := MeshInstance3D.new()
var _clock := 0.0
var stats := {"dust": 0, "sparks": 0, "flames": 0, "landing_dust": 0, "skid_segments": 0}


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mi.mesh = _mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mi.material_override = m
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_mi)
	if race:
		for k in race.karts:
			k.landed.connect(_on_landed)


func _on_landed(k: Kart, air: float) -> void:
	if air < 0.25 or not _near(k):
		return
	stats["landing_dust"] += 1
	var n := 8
	for i in n:
		var a := TAU * i / n
		var off := Vector3(cos(a), 0.0, sin(a)) * 1.1
		FxLib.puff(self, k.global_position + off + Vector3.UP * 0.2, SAND, 1.2 + air, 0.7)
	FxLib.burst(self, k.global_position + Vector3.UP * 0.2, SAND.darkened(0.1), 14, 5.0, 0.5, 0.3, -6.0, 70.0)


func _near(k: Kart) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam == null or cam.global_position.distance_to(k.global_position) < FX_RANGE


func _process(delta: float) -> void:
	if race == null or delta <= 0.0:
		return
	_clock += delta
	for k: Kart in race.karts:
		_kart_fx(k, delta)
	_draw_skids()


func _kart_fx(k: Kart, delta: float) -> void:
	var v := k.get_node_or_null("Visual") as Node3D
	if v == null or not v.visible:
		_last_skid[k] = null
		return
	var xf := v.global_transform
	var rear_l := xf * Vector3(-0.8, 0.05, 0.85)
	var rear_r := xf * Vector3(0.8, 0.05, 0.85)
	var acc: Vector3 = _acc.get(k, Vector3.ZERO)
	var near := _near(k)
	var sp := absf(k.speed)
	# dust
	if k.grounded and sp > 8.0 and near:
		var off_road := absf(k.lateral) > race.track.road_width * 0.5
		acc.x += delta * (sp / 30.0) * (22.0 if off_road else 9.0)
		while acc.x >= 1.0:
			acc.x -= 1.0
			var side := rear_l if randf() < 0.5 else rear_r
			FxLib.puff(self, side + Vector3(randf_range(-0.2, 0.2), 0.1, randf_range(-0.2, 0.2)), SAND,
					lerpf(0.5, 1.1, clampf(sp / 30.0, 0.0, 1.0)) * (1.4 if off_road else 1.0), 0.6)
			stats["dust"] += 1
	# drift sparks
	var tier := k.drift_tier() if k.drifting else -1
	if tier >= 1 and k.grounded and near:
		acc.y += delta * 12.0
		while acc.y >= 1.0:
			acc.y -= 1.0
			var c: Color = KartVisual.SPARK_COLORS.get([1, 4, 2, 5][tier], Color.WHITE)
			FxLib.burst(self, rear_l if k.drift_dir > 0 else rear_r, c, 4, 4.0, 0.25, 0.14, -12.0, 60.0)
			stats["sparks"] += 1
	# flame trail
	if k.is_boosting() and near:
		acc.z += delta * 30.0
		while acc.z >= 1.0:
			acc.z -= 1.0
			var ex := xf * Vector3(randf_range(-0.25, 0.25), 0.62, 2.1)
			FxLib.puff(self, ex, FLAME, 0.55, 0.25)
			stats["flames"] += 1
	_acc[k] = acc
	# skid marks
	if k.drifting and k.grounded:
		var prev = _last_skid.get(k)
		if prev == null:
			_last_skid[k] = [rear_l, rear_r]
		elif (prev[0] as Vector3).distance_to(rear_l) > 0.6:
			_skids.append([prev[0], prev[1], rear_l, rear_r, _clock, xf.basis.x])
			stats["skid_segments"] += 1
			if _skids.size() > SKID_MAX:
				_skids.pop_front()
			_last_skid[k] = [rear_l, rear_r]
	else:
		_last_skid[k] = null


func _draw_skids() -> void:
	while not _skids.is_empty() and _clock - float(_skids[0][4]) > SKID_LIFE:
		_skids.pop_front()
	_mesh.clear_surfaces()
	if _skids.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for sk in _skids:
		var a := clampf(1.0 - (_clock - float(sk[4])) / SKID_LIFE, 0.0, 1.0) * 0.55
		var col := Color(0.08, 0.06, 0.05, a)
		var side: Vector3 = sk[5] * 0.13
		for w in 2:
			var p0: Vector3 = sk[w]
			var p1: Vector3 = sk[w + 2]
			var lift := Vector3.UP * 0.03
			var q := [p0 - side + lift, p0 + side + lift, p1 + side + lift, p1 - side + lift]
			for idx in [0, 1, 2, 0, 2, 3]:
				_mesh.surface_set_color(col)
				_mesh.surface_add_vertex(q[idx])
	_mesh.surface_end()


func skid_count() -> int:
	return _skids.size()
