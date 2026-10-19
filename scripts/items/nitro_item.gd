extends ItemEffect
## 氮气: +nitro_bonus m/s for nitro_time s (buff stacks by max with other boosts).

func _ready() -> void:
	life = user.config.nitro_time
	user.add_boost("nitro", user.config.nitro_bonus, user.config.nitro_time, 0.5)
	var ring := TorusMesh.new(); ring.inner_radius = 0.9; ring.outer_radius = 1.2
	add_mesh(ring, emissive(Color(0.25, 0.65, 1.0), 3.0, 0.7), Vector3(0, 0.7, 1.6), Vector3(PI / 2, 0, 0))


func tick(_d: float) -> void:
	if is_instance_valid(user):
		global_transform = user.global_transform
		scale = Vector3.ONE * (1.0 + age * 0.6)
