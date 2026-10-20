extends ItemEffect
## 闪电: strikes every kart ahead of the user: short stun + 3 s slow.
## I9: transparent additive jagged bolts from the sky (no opaque boxes), impact
## sparks, flicker; the screen flashes only when the player is struck.

var bolts: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	life = 0.45
	_rng.seed = hash(system.race.race_time)
	var player_hit := false
	for k: Kart in system.race.karts:
		if k == user or k.rank >= user.rank or k.finished:
			continue
		var landed := k.hit("lightning", 0.5, true, 8.0, 3.0)
		if landed and k.is_player:
			player_hit = true
		var top := k.global_position + Vector3(_rng.randf_range(-3, 3), 38.0, _rng.randf_range(-3, 3))
		for j in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = FxLib.bolt_mesh(top, k.global_position + Vector3.UP * 0.4, _rng, 12, 1.6 - j * 0.6, 0.32 - j * 0.12)
			mi.material_override = FxLib.mat("bolt_core" if j == 1 else "bolt_glow",
					Color(1, 1, 1) if j == 1 else Color(0.65, 0.5, 1.0), true, 0.95 if j == 1 else 0.7)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.top_level = true
			mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(mi)
			mi.global_transform = Transform3D.IDENTITY
			bolts.append(mi)
		FxLib.burst(system, k.global_position + Vector3.UP * 0.5, Color(0.8, 0.7, 1.0), 22, 9.0, 0.4, 0.3, -12.0)
		FxLib.flash_sphere(system, k.global_position + Vector3.UP * 0.6, Color(0.45, 0.35, 0.8), 0.4, 0.2, 2.5)
	if player_hit:
		system.flash(Color(0.85, 0.8, 1.0))


func tick(_d: float) -> void:
	# flicker, then fade out
	var on := int(age * 30.0) % 3 != 1
	for b in bolts:
		b.visible = on and age < life - 0.05
