extends ItemEffect
## 闪电: strikes every kart ahead of the user: short stun + 3 s slow.

func _ready() -> void:
	life = 0.5
	var bolt_m := emissive(Color(0.75, 0.55, 1.0), 6.0)
	for k: Kart in system.race.karts:
		if k == user or k.rank >= user.rank or k.finished:
			continue
		k.hit("lightning", 0.5, true, 8.0, 3.0)
		for j in 4:
			var b := BoxMesh.new(); b.size = Vector3(0.25, 4.0, 0.25)
			var mi := add_mesh(b, bolt_m)
			mi.top_level = true
			mi.global_position = k.global_position + Vector3(sin(j) * 0.4, 2.0 + j * 3.6, cos(j) * 0.4)
			mi.rotation = Vector3(0, 0, 0.35 * (1 if j % 2 == 0 else -1))
	system.flash(Color(0.8, 0.7, 1.0))
