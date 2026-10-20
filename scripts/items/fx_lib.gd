class_name FxLib
extends RefCounted
## Shared, cached visual effects for items / hits / collisions (I5-I9, V1, K11).
## Everything is web-safe: CPUParticles3D (no GPU particles in the Compatibility
## renderer on WebGL2), unshaded additive materials and tiny shaders. Materials
## are cached by key so no item creates a fresh material (= shader variant) at
## use time, and prewarm() draws each one once during the countdown so the
## first missile doesn't hitch while its shader compiles.

static var _mats := {}
static var _meshes := {}
const SMOKE := Color(0.88, 0.86, 0.84)

const SHIELD_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float strength = 1.0;
void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	float bands = 0.5 + 0.5 * sin(UV.y * 60.0 - TIME * 4.0);
	ALBEDO = tint.rgb * (rim * 1.6 + 0.08 + 0.12 * bands * rim) * strength;
}
"""

## Unshaded material, cached by key. additive = glow-like blending.
static func mat(key: String, color: Color, additive := true, alpha := 1.0, vertex_color := false, billboard := false) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = false
	elif alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive or alpha < 1.0:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = vertex_color
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_receive_shadows = true
	_mats[key] = m
	return m


## Lit (shaded) material for solid props (banana peel, missile body), cached.
static func solid(key: String, color: Color, emission := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


static func shader_mat(key: String, code: String, tint: Color) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", tint)
	_mats[key] = m
	return m


static func shield_mat() -> ShaderMaterial:
	return shader_mat("shield", SHIELD_SHADER, Color(0.35, 0.85, 1.0))


static func ufo_beam_mat() -> StandardMaterial3D:
	return mat("beam_ufo", Color(0.45, 1.0, 0.5), true, 0.35)


static func magnet_beam_mat() -> StandardMaterial3D:
	return mat("beam_mag", Color(1.0, 0.25, 0.5), false, 0.75)


## Soft round sprite for particles (no hard quads).
static func soft_dot() -> Texture2D:
	if _meshes.has("soft_dot"):
		return _meshes["soft_dot"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_meshes["soft_dot"] = t
	return t


static func quad(size := 1.0) -> QuadMesh:
	var key := "quad%.2f" % size
	if not _meshes.has(key):
		var q := QuadMesh.new()
		q.size = Vector2(size, size)
		_meshes[key] = q
	return _meshes[key]


## A CPUParticles3D emitter with billboard quads. Not added to the tree.
static func particles(color: Color, amount: int, lifetime: float, speed: float, size: float,
		gravity := -6.0, spread := 180.0, one_shot := true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = quad(1.0)
	# alpha-blended, not additive: additive vanishes against the bright sand
	var pm := mat("pt_soft", Color.WHITE, false, 0.999, true, true)
	pm.albedo_texture = soft_dot()
	p.material_override = pm
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = 0.95 if one_shot else 0.0
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = speed * 0.45
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 1.0
	p.damping_max = 3.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, Color(color, 1.0))
	g.set_color(1, Color(color.darkened(0.5), 0.0))
	p.color_ramp = g
	p.color = Color.WHITE
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## Single soft billboard puff (smoke trails): grows then shrinks away.
## (Continuous CPUParticles3D on a fast-moving parent drew a black quad at the
## emitter in the Compatibility renderer, so trails are made of these.)
static func puff(parent: Node, pos: Vector3, color: Color, size := 0.8, life := 0.8) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = quad(1.0)
	var key := "puff_%s" % color.to_html()
	if not _mats.has(key):
		var m := mat(key, color, false, 0.7, false, true)
		m.albedo_texture = soft_dot()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = _mats[key]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.3
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life * 0.3).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, life * 0.7).set_ease(Tween.EASE_IN).set_delay(life * 0.3)
	tw.tween_property(mi, "global_position", pos + Vector3.UP * 0.6, life)
	tw.chain().tween_callback(mi.queue_free)


## One-shot particle burst at a world position; frees itself.
static func burst(parent: Node, pos: Vector3, color: Color, amount := 24, speed := 8.0, life := 0.5,
		size := 0.35, gravity := -9.0, spread := 180.0) -> CPUParticles3D:
	var p := particles(color, amount, life, speed, size, gravity, spread, true)
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(p, life + 0.3)
	return p


## Additive sphere that grows and fades (explosion core, shield pop).
static func flash_sphere(parent: Node, pos: Vector3, color: Color, radius := 1.0, time := 0.3, grow := 3.0) -> void:
	var mi := MeshInstance3D.new()
	if not _meshes.has("sphere"):
		var s := SphereMesh.new(); s.radius = 1.0; s.height = 2.0; s.radial_segments = 16; s.rings = 8
		_meshes["sphere"] = s
	mi.mesh = _meshes["sphere"]
	var m := mat("flash_%s" % color.to_html(), color).duplicate() as StandardMaterial3D
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * radius
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * grow, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, time)
	tw.chain().tween_callback(mi.queue_free)


## Explosion: core flash + fire + smoke + debris.
static func explosion(parent: Node, pos: Vector3, scale := 1.0) -> void:
	flash_sphere(parent, pos, Color(1.0, 0.75, 0.35), 0.8 * scale, 0.3, 3.2)
	burst(parent, pos, Color(1.0, 0.55, 0.15), int(40 * scale), 11.0 * scale, 0.55, 0.9 * scale, -2.0)
	burst(parent, pos + Vector3.UP * 0.3, Color(0.35, 0.32, 0.3), int(18 * scale), 4.0, 1.1, 1.6 * scale, 1.5)
	burst(parent, pos, Color(1.0, 0.9, 0.6), int(20 * scale), 16.0, 0.7, 0.18, -18.0)


## Jagged lightning ribbon from a to b (two crossed ribbons so it reads from any
## side); additive, so it never draws an opaque box.
static func bolt_mesh(a: Vector3, b: Vector3, rng: RandomNumberGenerator, segments := 10, jitter := 1.2, width := 0.35) -> ArrayMesh:
	var pts: Array[Vector3] = []
	for i in segments + 1:
		var t := float(i) / segments
		var p := a.lerp(b, t)
		if i > 0 and i < segments:
			p += Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)) * jitter * sin(t * PI)
		pts.append(p)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		for i in segments:
			var w0 := width * (1.0 - 0.6 * float(i) / segments)
			var w1 := width * (1.0 - 0.6 * float(i + 1) / segments)
			var p0 := pts[i]; var p1 := pts[i + 1]
			var v := [p0 - side * w0, p0 + side * w0, p1 + side * w1, p1 - side * w1]
			for idx in [0, 1, 2, 0, 2, 3]:
				st.add_vertex(v[idx])
	return st.commit()


static func _free_later(n: Node, t: float) -> void:
	# bound to the node's own method: the connection dies with the node
	n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)


## Draw every cached material once (in front of the camera, for 2 frames) so the
## Compatibility renderer compiles their shaders during the countdown (I-perf / H3).
static func prewarm(parent: Node3D, at: Vector3) -> void:
	var holder := Node3D.new()
	holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(holder)
	holder.global_position = at
	explosion(holder, at, 0.2)
	burst(holder, at, Color(0.85, 1.0, 1.0), 4)
	burst(holder, at, Color(1.0, 0.85, 0.4), 4)
	burst(holder, at, Color(0.4, 0.8, 1.0), 4)
	burst(holder, at, Color(0.75, 0.6, 1.0), 4)
	burst(holder, at, Color(0.15, 0.12, 0.2), 4)
	shield_mat(); ufo_beam_mat(); magnet_beam_mat()
	puff(holder, at, SMOKE, 0.1, 0.1)
	solid("peel", Color(1.0, 0.86, 0.22)); solid("peel_tip", Color(0.35, 0.22, 0.08))
	for k: String in _mats.keys():
		var mi := MeshInstance3D.new()
		mi.mesh = quad(0.05)
		mi.material_override = _mats[k]
		holder.add_child(mi)
	_free_later(holder, 0.15)
