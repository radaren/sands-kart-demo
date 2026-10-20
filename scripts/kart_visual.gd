class_name KartVisual
extends Node3D
## Procedural cartoon kart (boxes / cylinders / spheres), styled after
## assets/karts/reference/kart_candidate_1.png (red buggy with roll cage).
## Used because no 3D kart model was delivered yet; 6 drivers = 6 colours.
## Child of a Kart; follows the kart state every frame (ground tilt, drift yaw,
## boost flames, drift sparks, shield bubble, stun spin, respawn blink).

var body_color := Color.RED
var flames: Array[MeshInstance3D] = []
var sparks: Array[MeshInstance3D] = []
var shield_bubble: MeshInstance3D
var wheels: Array[Node3D] = []
var model: Node3D
var _spark_mat: StandardMaterial3D
var _flame_mat: StandardMaterial3D


static func mat(c: Color, emissive := 0.0, rough := 0.6) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	return m


func _add(mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	(parent if parent else model).add_child(mi)
	return mi


func build(color: Color, driver_name: String) -> void:
	body_color = color
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var body := mat(color, 0.0, 0.35)
	var dark := mat(Color(0.12, 0.12, 0.14))
	var metal := mat(Color(0.75, 0.75, 0.8), 0.0, 0.2)
	var skin := mat(Color(1.0, 0.82, 0.66))
	var white := mat(Color(0.95, 0.95, 0.95))
	# chassis (kart faces -Z)
	var chassis := BoxMesh.new(); chassis.size = Vector3(1.3, 0.28, 2.1)
	_add(chassis, body, Vector3(0, 0.38, 0))
	var nose := BoxMesh.new(); nose.size = Vector3(1.0, 0.22, 0.6)
	_add(nose, body, Vector3(0, 0.36, -1.25), Vector3(-0.25, 0, 0))
	var bumper := BoxMesh.new(); bumper.size = Vector3(1.45, 0.16, 0.18)
	_add(bumper, dark, Vector3(0, 0.3, -1.55))
	var pod := BoxMesh.new(); pod.size = Vector3(0.28, 0.24, 1.1)
	_add(pod, body, Vector3(-0.72, 0.42, 0.05))
	_add(pod, body, Vector3(0.72, 0.42, 0.05))
	var seat := BoxMesh.new(); seat.size = Vector3(0.7, 0.55, 0.25)
	_add(seat, dark, Vector3(0, 0.75, 0.55), Vector3(-0.2, 0, 0))
	# engine + exhausts
	var eng := BoxMesh.new(); eng.size = Vector3(0.8, 0.35, 0.45)
	_add(eng, metal, Vector3(0, 0.6, 0.95))
	var pipe := CylinderMesh.new(); pipe.top_radius = 0.09; pipe.bottom_radius = 0.09; pipe.height = 0.5
	for x in [-0.25, 0.25]:
		_add(pipe, metal, Vector3(x, 0.62, 1.25), Vector3(PI / 2, 0, 0))
	# spoiler
	var wing := BoxMesh.new(); wing.size = Vector3(1.5, 0.06, 0.35)
	_add(wing, body, Vector3(0, 1.05, 1.1))
	var strut := BoxMesh.new(); strut.size = Vector3(0.06, 0.4, 0.1)
	for x in [-0.5, 0.5]:
		_add(strut, dark, Vector3(x, 0.85, 1.1))
	# roll cage (like the reference buggy)
	var bar := CylinderMesh.new(); bar.top_radius = 0.05; bar.bottom_radius = 0.05; bar.height = 1.1
	for x in [-0.5, 0.5]:
		_add(bar, dark, Vector3(x, 1.15, 0.35), Vector3(0.35, 0, 0))
		_add(bar, dark, Vector3(x, 1.2, -0.15), Vector3(-0.5, 0, 0))
	var top_bar := CylinderMesh.new(); top_bar.top_radius = 0.05; top_bar.bottom_radius = 0.05; top_bar.height = 1.05
	_add(top_bar, dark, Vector3(0, 1.62, 0.12), Vector3(0, 0, PI / 2))
	# steering wheel
	var sw := TorusMesh.new(); sw.inner_radius = 0.12; sw.outer_radius = 0.17
	_add(sw, dark, Vector3(0, 0.78, -0.25), Vector3(-1.1, 0, 0))
	# driver
	var torso := CapsuleMesh.new(); torso.radius = 0.24; torso.height = 0.7
	_add(torso, white, Vector3(0, 0.92, 0.3))
	var head := SphereMesh.new(); head.radius = 0.24; head.height = 0.48
	_add(head, skin, Vector3(0, 1.38, 0.28))
	var helmet := SphereMesh.new(); helmet.radius = 0.29; helmet.height = 0.42; helmet.is_hemisphere = true
	_add(helmet, body, Vector3(0, 1.42, 0.3))
	var visor := BoxMesh.new(); visor.size = Vector3(0.36, 0.1, 0.05)
	_add(visor, dark, Vector3(0, 1.4, 0.04))
	# wheels
	var wheel := CylinderMesh.new(); wheel.top_radius = 0.3; wheel.bottom_radius = 0.3; wheel.height = 0.28
	var hub := CylinderMesh.new(); hub.top_radius = 0.13; hub.bottom_radius = 0.13; hub.height = 0.3
	for p in [Vector3(-0.78, 0.3, -0.75), Vector3(0.78, 0.3, -0.75), Vector3(-0.8, 0.32, 0.8), Vector3(0.8, 0.32, 0.8)]:
		var w := Node3D.new()
		w.position = p
		model.add_child(w)
		_add(wheel, dark, Vector3.ZERO, Vector3(0, 0, PI / 2), w)
		_add(hub, metal, Vector3.ZERO, Vector3(0, 0, PI / 2), w)
		wheels.append(w)
	# number plate with driver initial colour stripe
	var stripe := BoxMesh.new(); stripe.size = Vector3(0.25, 0.3, 2.12)
	_add(stripe, white, Vector3(0, 0.39, 0))
	# boost flames (hidden until boosting)
	_flame_mat = mat(Color(1.0, 0.55, 0.1), 4.0)
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.albedo_color.a = 0.85
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flame := CylinderMesh.new(); flame.top_radius = 0.0; flame.bottom_radius = 0.14; flame.height = 0.9
	for x in [-0.25, 0.25]:
		var f := _add(flame, _flame_mat, Vector3(x, 0.62, 1.9), Vector3(-PI / 2, 0, 0))
		f.visible = false
		flames.append(f)
	# drift sparks
	_spark_mat = mat(Color(0.4, 0.8, 1.0), 5.0)
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var spark := BoxMesh.new(); spark.size = Vector3(0.12, 0.12, 0.45)
	for x in [-0.8, 0.8]:
		var s := _add(spark, _spark_mat, Vector3(x, 0.1, 1.2))
		s.visible = false
		sparks.append(s)
	# shield bubble
	# shield bubble: fresnel shader (bright rim, clear centre) instead of a milky ball (I8)
	var sb := SphereMesh.new(); sb.radius = 1.6; sb.height = 3.0; sb.radial_segments = 24; sb.rings = 12
	_shield_mat = FxLib.shield_mat().duplicate() as ShaderMaterial
	shield_bubble = MeshInstance3D.new()
	shield_bubble.mesh = sb
	shield_bubble.material_override = _shield_mat
	shield_bubble.position = Vector3(0, 0.8, 0)
	shield_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield_bubble)    # not under the model: it must not tumble with the kart
	shield_bubble.visible = false
	# name tag
	var tag := Label3D.new()
	tag.text = driver_name
	tag.font_size = 48
	tag.pixel_size = 0.008
	tag.position = Vector3(0, 2.1, 0)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = color.lightened(0.3)
	tag.outline_size = 10
	tag.no_depth_test = false
	add_child(tag)
	name_tag = tag


var kart: Kart
var name_tag: Label3D
const SPARK_COLORS := {1: Color(0.85, 0.85, 0.8), 4: Color(0.35, 0.7, 1.0), 2: Color(1.0, 0.55, 0.1), 5: Color(0.8, 0.35, 1.0)}
var land_ring: MeshInstance3D
var _cam_fade := 0.0
var _shield_mat: ShaderMaterial
var _shield_break_t := -1.0
var _shield_on_t := 0.0
var _was_shield := false
var _ring_mat: StandardMaterial3D
var _ring_t := -1.0
var _t := 0.0


func _ready() -> void:
	kart = get_parent() as Kart
	# landing-boost cue: a bright ring bursts out from the wheels on touchdown
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 24
	torus.ring_segments = 6
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ring_mat.albedo_color = Color(0.8, 1.0, 1.0, 1.0)
	land_ring = MeshInstance3D.new()
	land_ring.mesh = torus
	land_ring.material_override = _ring_mat
	land_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	land_ring.visible = false
	land_ring.position = Vector3(0, 0.1, 0)
	add_child(land_ring)
	if kart:
		kart.landing_window_opened.connect(func(_k: Kart) -> void: _ring_t = 0.0)
		kart.shield_blocked.connect(_on_shield_blocked)
	# Driven every rendered frame from the kart's interpolated transform (C1),
	# so it is top-level and opts out of physics interpolation itself.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	top_level = true


func _process(delta: float) -> void:
	# name tags: hide when the camera is right on top of the kart (huge text)
	var cam := get_viewport().get_camera_3d()
	var cam_d := cam.global_position.distance_to(global_position) if cam else 100.0
	if name_tag:
		name_tag.visible = cam_d > 9.0
	# C6: other karts right at the lens fade out instead of filling the screen
	if kart and not kart.is_player and model:
		var fade := clampf((3.5 - cam_d) / 1.5, 0.0, 1.0)
		if absf(fade - _cam_fade) > 0.02:
			_cam_fade = fade
			for g in model.find_children("*", "GeometryInstance3D", true, false):
				(g as GeometryInstance3D).transparency = fade
			model.visible = fade < 0.98
	if kart == null or model == null:
		return
	_t += delta
	var yaw_off := 0.0
	if kart.drifting:
		yaw_off = float(kart.drift_dir) * -deg_to_rad(16.0)
	_hit_reaction(delta)
	var up := kart.ground_normal.normalized() if kart.grounded else Vector3.UP
	var yaw := kart.facing_yaw + yaw_off
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := fwd.cross(up).normalized()
	var f2 := up.cross(right).normalized()
	var target := Basis(right, up, -f2).orthonormalized()
	var xf := kart.get_global_transform_interpolated()
	global_transform = Transform3D(global_basis.orthonormalized().slerp(target, 1.0 - exp(-12.0 * delta)), xf.origin)
	var blink := kart.freeze_time > 0.0 or kart.invuln_time > 0.0
	visible = not blink or int(_t * (10.0 if kart.freeze_time > 0.0 else 16.0)) % 2 == 0
	# drift sparks by tier (K5): 1 white (charging), 4 blue, 2 orange, 5 purple
	var dstate := 0
	if kart.drifting:
		dstate = [1, 4, 2, 5][kart.drift_tier()]
	if kart.mini_window > 0.0:
		dstate = [4, 4, 2, 5][clampi(kart.mini_tier, 0, 3)]
	if kart.landing_window > 0.0:
		dstate = 3     # touchdown flash: white sparks = tap now
	if _ring_t >= 0.0:
		_ring_t += delta
		var k := _ring_t / 0.35
		land_ring.visible = k < 1.0
		land_ring.scale = Vector3.ONE * lerpf(0.6, 2.6, sqrt(minf(k, 1.0)))
		_ring_mat.albedo_color.a = clampf(1.0 - k, 0.0, 1.0)
		if k >= 1.0:
			_ring_t = -1.0
	update_fx(kart.is_boosting(), dstate, kart.shield_time > 0.0, kart.speed * delta / 0.3, _t)


## I-presentation: hit reactions instead of a generic spin / dead stop.
##   missile  -> tumble: a full forward flip with a hop
##   banana   -> spin-out: two yaw turns easing out
##   lightning-> squash flat, then pop back (with a buzz jitter)
##   other    -> one quick spin
var react_kind := ""
var react_progress := 0.0


func _hit_reaction(_delta: float) -> void:
	var pitch := 0.0
	var yaw := 0.0
	var hop := 0.0
	var sq := 1.0
	react_kind = ""
	if kart.stun_time > 0.0 and kart.stun_total > 0.0:
		var t := clampf(1.0 - kart.stun_time / kart.stun_total, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - t, 2.2)
		react_kind = kart.stun_kind
		react_progress = t
		match kart.stun_kind:
			"missile":
				pitch = -TAU * clampf(t / 0.75, 0.0, 1.0) ** 0.8
				hop = sin(clampf(t / 0.75, 0.0, 1.0) * PI) * 1.8
			"banana":
				yaw = TAU * 2.0 * e
			"lightning":
				sq = lerpf(0.45, 1.0, clampf((t - 0.5) / 0.5, 0.0, 1.0))
				yaw = sin(_t * 80.0) * 0.06 * (1.0 - t)
			_:
				yaw = TAU * e
	model.position = Vector3(0, hop, 0)
	model.rotation = Vector3(pitch, yaw, 0)
	model.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))


func _on_shield_blocked(_k: Kart, _kind: String) -> void:
	_shield_break_t = 0.0
	FxLib.burst(get_parent().get_parent(), global_position + Vector3.UP * 0.8, Color(0.5, 0.95, 1.0), 36, 9.0, 0.6, 0.35, -9.0)
	FxLib.flash_sphere(get_parent().get_parent(), global_position + Vector3.UP * 0.8, Color(0.5, 0.95, 1.0), 1.6, 0.25, 1.6)


func update_fx(boosting: bool, drift_state: int, shield: bool, wheel_spin: float, t: float) -> void:
	for f in flames:
		f.visible = boosting
		if boosting:
			f.scale = Vector3.ONE * (0.85 + 0.3 * sin(t * 40.0 + f.position.x * 10.0))
	for s in sparks:
		s.visible = drift_state > 0
		if drift_state != 3:
			s.scale = Vector3.ONE
	if drift_state == 3:
		_spark_mat.albedo_color = Color(0.85, 1.0, 1.0)
		_spark_mat.emission = Color(0.85, 1.0, 1.0)
		for sp in sparks:
			sp.scale = Vector3(2.2, 2.2, 1.6)
	else:
		var c: Color = SPARK_COLORS.get(drift_state, Color(0.4, 0.8, 1.0))
		_spark_mat.albedo_color = c
		_spark_mat.emission = c
	# shield: pops in, shimmers, and bursts (scale up + fade) when it blocks
	if shield and not _was_shield:
		_shield_on_t = 0.0
	_was_shield = shield
	_shield_on_t += get_process_delta_time()
	if _shield_break_t >= 0.0:
		_shield_break_t += get_process_delta_time()
		var k := _shield_break_t / 0.25
		shield_bubble.visible = k < 1.0
		shield_bubble.scale = Vector3.ONE * (1.0 + 0.6 * k)
		_shield_mat.set_shader_parameter("strength", 2.0 * (1.0 - k))
		if k >= 1.0:
			_shield_break_t = -1.0
	else:
		shield_bubble.visible = shield
		var pop := clampf(_shield_on_t / 0.2, 0.0, 1.0)
		shield_bubble.scale = Vector3.ONE * (0.3 + 0.7 * pop + 0.08 * sin(pop * PI))
		_shield_mat.set_shader_parameter("strength", 1.0 + 0.15 * sin(t * 6.0))
	for w in wheels:
		w.rotation.x -= wheel_spin
