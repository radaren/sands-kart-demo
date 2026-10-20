extends ItemEffect
## 云雾 (ink cloud): a dark ink bank left behind; karts driving through lose vision
## for 3 s (player: ink-blot overlay with a clear centre, AI: steering wobble).
## I7: the bank puffs out from the user's tail instead of popping in.

const RADIUS := 7.0
var puffs: Array[MeshInstance3D] = []


func _ready() -> void:
	life = 12.0
	var p := user.global_position - user.forward_dir() * 6.0
	p.y = ground_y_at(p)
	global_position = p
	var m := FxLib.mat("ink_cloud", Color(0.16, 0.12, 0.22), false, 0.82)
	var s := SphereMesh.new(); s.radius = 2.4; s.height = 3.4; s.radial_segments = 16; s.rings = 8
	for k in 7:
		var mi := add_mesh(s, m, Vector3(cos(k * 0.9) * 3.5, 1.2 + (k % 2) * 0.8, sin(k * 1.7) * 3.0))
		mi.scale = Vector3.ONE * 0.05
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puffs.append(mi)
		var tw := mi.create_tween()
		tw.tween_interval(k * 0.04)
		tw.tween_property(mi, "scale", Vector3.ONE * (0.85 + 0.1 * (k % 3)), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	FxLib.burst(system, p + Vector3.UP, Color(0.3, 0.22, 0.4), 26, 6.0, 0.8, 1.4, 0.5)


func tick(d: float) -> void:
	for i in puffs.size():
		puffs[i].position.y += sin(age * 1.5 + i) * d * 0.2
	if life - age < 0.6:
		for mi in puffs:
			mi.scale = mi.scale.move_toward(Vector3.ZERO, d * 2.0)
	for k: Kart in system.race.karts:
		if k == user:
			continue
		if k.global_position.distance_to(global_position) < RADIUS:
			k.cloud_time = maxf(k.cloud_time, 3.0)
