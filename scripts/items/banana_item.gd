extends ItemEffect
## 香蕉皮: dropped behind the user; the first kart that touches it spins out.

func _ready() -> void:
	life = 45.0
	var p := user.global_position - user.forward_dir() * 3.2
	p.y = ground_y_at(p) + 0.15
	global_position = p
	var peel := SphereMesh.new(); peel.radius = 0.45; peel.height = 0.35
	add_mesh(peel, emissive(Color(1.0, 0.85, 0.2), 0.6))
	for k in 3:
		var leaf := BoxMesh.new(); leaf.size = Vector3(0.18, 0.06, 0.7)
		add_mesh(leaf, emissive(Color(0.95, 0.8, 0.15), 0.4), Vector3(sin(k * 2.1) * 0.35, 0.05, cos(k * 2.1) * 0.35), Vector3(0, k * 2.1, 0.3))


func tick(_d: float) -> void:
	rotation.y += _d * 0.5
	for k: Kart in system.race.karts:
		if k == user and age < 0.8:
			continue
		if k.global_position.distance_to(global_position) < 1.7:
			k.hit("banana", 0.9, true)
			finish()
			return
