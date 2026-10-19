extends ItemEffect
## 云雾: a fog bank left behind; karts driving through lose vision (HUD fog for
## the player, steering wobble for the AI) for 3 s.

const RADIUS := 7.0


func _ready() -> void:
	life = 12.0
	var p := user.global_position - user.forward_dir() * 6.0
	p.y = ground_y_at(p)
	global_position = p
	var m := emissive(Color(0.85, 0.87, 0.92), 0.4, 0.55)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for k in 7:
		var s := SphereMesh.new(); s.radius = 2.4; s.height = 3.4
		add_mesh(s, m, Vector3(cos(k * 0.9) * 3.5, 1.2 + (k % 2) * 0.8, sin(k * 1.7) * 3.0))


func tick(_d: float) -> void:
	for k: Kart in system.race.karts:
		if k == user:
			continue
		if k.global_position.distance_to(global_position) < RADIUS:
			k.cloud_time = maxf(k.cloud_time, 3.0)
