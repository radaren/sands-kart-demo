extends ItemEffect
## 护盾: blocks the next attack within shield_time s. The bubble itself (fresnel
## shader) and its break effect live on KartVisual (I8); this only plays the
## activation ring.

func _ready() -> void:
	life = 0.45
	user.shield_time = user.config.shield_time
	user.announced.emit(user, "护盾开启", Kart.Tone.GOOD)
	var ring := TorusMesh.new(); ring.inner_radius = 1.5; ring.outer_radius = 1.7
	var mi := add_mesh(ring, FxLib.mat("shield_ring", Color(0.4, 0.9, 1.0)), Vector3(0, 0.8, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func tick(_d: float) -> void:
	if is_instance_valid(user):
		global_position = user.global_position
	scale = Vector3.ONE * (0.6 + age * 2.0)
