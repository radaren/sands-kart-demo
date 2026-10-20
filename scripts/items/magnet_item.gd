extends ItemEffect
## 磁铁: locks onto the kart ahead and pulls the user towards it for 2.5 s.
## I-presentation: scrolling additive tether + magnetic rings riding along it.

var beam: MeshInstance3D
var rings: Array[MeshInstance3D] = []


func _ready() -> void:
	life = 2.5
	if target == null or not is_instance_valid(target):
		life = 0.1
		return
	if target.shield_time > 0.0:
		target.hit("magnet", 0.0, true)   # consumes the shield
		life = 0.1
		return
	var c := CylinderMesh.new(); c.top_radius = 0.22; c.bottom_radius = 0.22; c.height = 1.0; c.radial_segments = 12
	beam = add_mesh(c, FxLib.magnet_beam_mat())
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var t := TorusMesh.new(); t.inner_radius = 0.35; t.outer_radius = 0.45
	for i in 4:
		var r := MeshInstance3D.new()
		r.mesh = t
		r.material_override = FxLib.mat("magnet_ring", Color(1.0, 0.85, 0.9), false, 0.9)
		r.top_level = true
		r.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(r)
		rings.append(r)


func tick(_d: float) -> void:
	if not is_instance_valid(target) or not is_instance_valid(user) or beam == null:
		return
	user.add_boost("magnet", 8.0, 0.15, 0.0)
	target.add_slow("magnet", 3.0, 0.15)
	var a := user.global_position + Vector3.UP * 0.9
	var b := target.global_position + Vector3.UP * 0.9
	var mid := (a + b) * 0.5
	var dist := a.distance_to(b)
	global_position = mid
	if dist > 0.1:
		look_at(b, Vector3.UP)
		beam.rotation = Vector3(PI / 2, 0, 0)
		beam.scale = Vector3(1, dist, 1)
		var fwd := (b - a) / dist
		for i in rings.size():
			var t := fmod(age * 1.6 + i / float(rings.size()), 1.0)   # rings travel target -> user
			rings[i].global_position = b.lerp(a, t)
			rings[i].global_basis = Basis(Quaternion(Vector3.UP, fwd)).scaled(Vector3.ONE * (0.7 + 0.5 * sin(t * PI)))
