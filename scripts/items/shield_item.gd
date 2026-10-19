extends ItemEffect
## 护盾: blocks the next attack within shield_time s (bubble drawn by KartVisual).

func _ready() -> void:
	life = 0.6
	user.shield_time = user.config.shield_time
	user.announced.emit(user, "护盾开启", Kart.Tone.GOOD)
	var s := SphereMesh.new(); s.radius = 1.8; s.height = 3.6
	add_mesh(s, emissive(Color(0.25, 0.9, 0.9), 2.0, 0.35), Vector3(0, 0.8, 0))


func tick(_d: float) -> void:
	if is_instance_valid(user):
		global_position = user.global_position
	scale = Vector3.ONE * (1.0 + age)
