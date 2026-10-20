extends ItemEffect
## 飞碟: flies to the race leader and hovers over it for 4 s, slowing it down.
## Presentation: blinking rim lights, bobbing, scrolling tractor-beam cone and
## sparkles rising in the beam.

var arrived := false
var hover := 0.0
var beam: MeshInstance3D
var lights: Array[MeshInstance3D] = []
var sparkle: CPUParticles3D


func _ready() -> void:
	life = 9.0
	global_position = user.global_position + Vector3.UP * 4.0
	var disc := CylinderMesh.new(); disc.top_radius = 1.0; disc.bottom_radius = 1.8; disc.height = 0.45
	add_mesh(disc, FxLib.solid("ufo_disc", Color(0.7, 0.75, 0.8), 0.15))
	var under := CylinderMesh.new(); under.top_radius = 1.8; under.bottom_radius = 0.9; under.height = 0.3
	add_mesh(under, FxLib.solid("ufo_under", Color(0.35, 0.4, 0.45)), Vector3(0, -0.35, 0))
	var dome := SphereMesh.new(); dome.radius = 0.75; dome.height = 0.9; dome.is_hemisphere = true
	add_mesh(dome, FxLib.mat("ufo_dome", Color(0.5, 1.0, 0.7), false, 0.75), Vector3(0, 0.2, 0))
	var bulb := SphereMesh.new(); bulb.radius = 0.12; bulb.height = 0.24
	for i in 8:
		var a := i * TAU / 8.0
		lights.append(add_mesh(bulb, FxLib.mat("ufo_light", Color(1.0, 0.95, 0.4)), Vector3(cos(a) * 1.55, -0.05, sin(a) * 1.55)))
	var cone := CylinderMesh.new(); cone.top_radius = 0.6; cone.bottom_radius = 2.0; cone.height = 3.4; cone.cap_top = false; cone.cap_bottom = false
	beam = add_mesh(cone, FxLib.ufo_beam_mat(), Vector3(0, -2.1, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	sparkle = FxLib.particles(Color(0.7, 1.0, 0.7), 30, 1.0, 2.5, 0.25, 2.0, 15.0, false)
	sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparkle.emission_sphere_radius = 1.2
	sparkle.local_coords = true
	add_child(sparkle)
	sparkle.position = Vector3(0, -3.6, 0)
	sparkle.emitting = false


func threatens(k: Kart) -> bool:
	return k == target and not arrived


func tick(delta: float) -> void:
	if not is_instance_valid(target):
		finish()
		return
	var goal := target.global_position + Vector3.UP * 3.8
	if not arrived:
		global_position = global_position.move_toward(goal, 80.0 * delta)
		if global_position.distance_to(goal) < 1.0:
			arrived = true
			if not target.hit("ufo", 0.0, true):
				finish()
				return
			beam.visible = true
			sparkle.emitting = true
			system.ufo_arrived.emit(target)
	else:
		global_position = goal + Vector3.UP * sin(hover * 3.0) * 0.15
		hover += delta
		target.add_slow("ufo", 9.0, 0.15)
		if hover >= 4.0:
			finish()
	rotation.y += delta * 4.0
	for i in lights.size():
		lights[i].visible = (int(age * 8.0) + i) % 2 == 0
