class_name SandsTrack
extends Node3D
## 时之沙 single-run track. Loads the baked data from tools/track_builder.py and
## builds Path3D/Curve3D, road + kerbs + walls (with collision), boost pads,
## start/finish lines, dune terrain and procedural decorations.

const DATA_PATH := "res://data/track_data.json"
const TERRAIN_PATH := "res://data/terrain_height.bin"
const RUNOFF := 120.0

var data: Dictionary
var length := 0.0
var half_width := 7.0
var samples_s := PackedFloat32Array()
var samples_p := PackedVector3Array()
var samples_h := PackedFloat32Array()
var samples_r := PackedFloat32Array()   # curvature radius (m), 1e4 = straight
var samples_turn := PackedFloat32Array() # +1 left, -1 right, 0 straight
var checkpoints: Array = []
var boost_pads: Array = []
var item_sites: Array = []
var jumps: Array = []
var start_s := 22.0
var segments := {}
var path: Path3D
var curve: Curve3D
var _terrain := PackedFloat32Array()
var _tinfo := {}
var build_visuals := true


func _ready() -> void:
	load_data()
	_build_path()
	_build_road()
	if build_visuals:
		_build_environment()
		_build_terrain()
		_build_pads_and_lines()
		TrackDecor.build(self, data.decor, terrain_height)


func load_data() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	data = JSON.parse_string(f.get_as_text())
	length = data.length
	half_width = data.half_width
	checkpoints = data.checkpoints
	boost_pads = data.boost_pads
	item_sites = data.item_sites
	jumps = data.jumps
	start_s = data.start_s
	segments = data.segments
	for c in data.centerline:
		samples_p.append(Vector3(c[0], c[1], c[2]))
		samples_h.append(c[3])
		samples_s.append(c[4])
	var n := samples_s.size()
	for i in n:
		var a := maxi(0, i - 2)
		var b := mini(n - 1, i + 2)
		var dh := wrapf(samples_h[b] - samples_h[a], -PI, PI)
		var ds := samples_s[b] - samples_s[a]
		samples_r.append(10000.0 if absf(dh) < 1e-4 else minf(10000.0, ds / absf(dh)))
		samples_turn.append(0.0 if absf(dh) < 1e-4 else signf(dh))
	var tf := FileAccess.open(TERRAIN_PATH, FileAccess.READ)
	if tf:
		_terrain = tf.get_buffer(tf.get_length()).to_float32_array()
	_tinfo = data.terrain


# ------------------------------------------------------------ queries
func _index_at(s: float) -> int:
	var i := samples_s.bsearch(clampf(s, 0.0, length))
	return clampi(i, 1, samples_s.size() - 1)


func point_at(s: float) -> Vector3:
	if s > length:
		return samples_p[samples_p.size() - 1] + tangent_at(length) * (s - length)
	if s < 0.0:
		return samples_p[0] + tangent_at(0.0) * s
	var i := _index_at(s)
	var s0 := samples_s[i - 1]
	var s1 := samples_s[i]
	var t := 0.0 if s1 - s0 < 1e-5 else (s - s0) / (s1 - s0)
	return samples_p[i - 1].lerp(samples_p[i], t)


func heading_at(s: float) -> float:
	var i := _index_at(s)
	var s0 := samples_s[i - 1]
	var s1 := samples_s[i]
	var t := clampf((s - s0) / maxf(s1 - s0, 1e-5), 0.0, 1.0)
	return lerp_angle(samples_h[i - 1], samples_h[i], t)


func tangent_at(s: float) -> Vector3:
	var h := heading_at(s)
	return Vector3(-sin(h), 0.0, -cos(h))


func right_at(s: float) -> Vector3:
	var h := heading_at(s)
	return Vector3(cos(h), 0.0, -sin(h))


func radius_at(s: float) -> float:
	return samples_r[_index_at(s)]


func turn_sign_at(s: float) -> float:
	return samples_turn[_index_at(s)]


## Smallest curvature radius in [s, s + span].
func min_radius_ahead(s: float, span: float) -> Array:
	var best := 10000.0
	var sign := 0.0
	var x := s
	while x <= s + span:
		var r := radius_at(x)
		if r < best:
			best = r
			sign = turn_sign_at(x)
		x += 2.0
	return [best, sign]


func lateral_of(pos: Vector3, s: float) -> float:
	return (pos - point_at(s)).dot(right_at(s))


## Closest centre-line offset. Uses a local window around `hint` (robust next to
## hairpins); falls back to Curve3D.get_closest_offset when hint < 0.
func closest_offset(pos: Vector3, hint := -1.0) -> float:
	if hint < 0.0:
		return curve.get_closest_offset(to_local(pos))
	var lo := _index_at(hint - 40.0) - 1
	var hi := _index_at(hint + 40.0)
	var best := INF
	var best_s := hint
	for i in range(maxi(lo, 0), mini(hi, samples_p.size() - 1)):
		var a := samples_p[i]
		var b := samples_p[i + 1]
		var ab := Vector3(b.x - a.x, 0, b.z - a.z)
		var ap := Vector3(pos.x - a.x, 0, pos.z - a.z)
		var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var d := (ap - ab * t).length_squared() + pow((pos.y - lerpf(a.y, b.y, t)) * 0.3, 2)
		if d < best:
			best = d
			best_s = lerpf(samples_s[i], samples_s[i + 1], t)
	if hint >= length - 2.0:
		var over := (pos - samples_p[samples_p.size() - 1]).dot(tangent_at(length))
		if over > 0.0:
			return length + over
	return best_s


func boost_pad_at(s: float, lateral: float) -> Dictionary:
	for p in boost_pads:
		if s >= p.s and s <= p.s + p.len:
			var hw := 4.0
			if p.shape == "trapezoid":
				var t: float = (s - p.s) / p.len
				hw = lerpf(2.5, half_width - 0.5, t)
			if absf(lateral) <= hw:
				return p
	return {}


func terrain_height(x: float, z: float) -> float:
	if _terrain.is_empty():
		return -0.5
	var gx := (x - float(_tinfo.x0)) / float(_tinfo.cell)
	var gz := (z - float(_tinfo.z0)) / float(_tinfo.cell)
	var nx := int(_tinfo.nx)
	var nz := int(_tinfo.nz)
	var ix := clampi(int(gx), 0, nx - 2)
	var iz := clampi(int(gz), 0, nz - 2)
	var fx := clampf(gx - ix, 0.0, 1.0)
	var fz := clampf(gz - iz, 0.0, 1.0)
	var h00 := _terrain[iz * nx + ix]
	var h10 := _terrain[iz * nx + ix + 1]
	var h01 := _terrain[(iz + 1) * nx + ix]
	var h11 := _terrain[(iz + 1) * nx + ix + 1]
	return lerpf(lerpf(h00, h10, fx), lerpf(h01, h11, fx), fz)


func segment_name_at(s: float) -> String:
	for k in segments:
		if s >= segments[k].start and s <= segments[k].end:
			return "%s %s" % [k, segments[k].name]
	return ""


# ------------------------------------------------------------ build
func _build_path() -> void:
	path = Path3D.new()
	path.name = "TrackPath"
	curve = Curve3D.new()
	curve.bake_interval = 1.0
	var step := 2
	for i in range(0, samples_p.size(), step):
		curve.add_point(samples_p[i])
	if (samples_p.size() - 1) % step != 0:
		curve.add_point(samples_p[samples_p.size() - 1])
	path.curve = curve
	add_child(path)


## Centre-line samples plus a straight run-off after the finish line.
func _ribbon_points() -> Array:
	var pts := []
	for i in samples_p.size():
		pts.append([samples_p[i], samples_h[i], samples_s[i]])
	var last: Vector3 = samples_p[samples_p.size() - 1]
	var h := samples_h[samples_h.size() - 1]
	var t := Vector3(-sin(h), 0, -cos(h))
	var k := 4.0
	while k <= RUNOFF:
		pts.append([last + t * k, h, length + k])
		k += 4.0
	return pts


func _road_texture() -> ImageTexture:
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in 128:
		for x in 128:
			var c := Color(0.64, 0.53, 0.41)
			var jx := x % 32 < 1
			var jy := (y + (16 if (x / 32) % 2 == 0 else 0)) % 32 < 1
			if jx or jy:
				c = Color(0.5, 0.4, 0.3)
			c = c.darkened(rng.randf() * 0.06)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_road() -> void:
	var pts := _ribbon_points()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kerb := SurfaceTool.new()
	kerb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var road_faces := PackedVector3Array()
	var wall_faces := PackedVector3Array()
	var hw := half_width
	var wh := 1.1
	var ramp_ranges := []
	for j in jumps:
		ramp_ranges.append([j.s, j.s + j.len])
	for i in pts.size() - 1:
		var a: Vector3 = pts[i][0]
		var b: Vector3 = pts[i + 1][0]
		var ha: float = pts[i][1]
		var hb: float = pts[i + 1][1]
		var sa: float = pts[i][2]
		var sb: float = pts[i + 1][2]
		var ra := Vector3(cos(ha), 0, -sin(ha))
		var rb := Vector3(cos(hb), 0, -sin(hb))
		var al := a - ra * hw; var ar := a + ra * hw
		var bl := b - rb * hw; var br := b + rb * hw
		var ramp := false
		for rr in ramp_ranges:
			if sa >= rr[0] and sa < rr[1]:
				ramp = true
		var col := Color(1.0, 0.72, 0.35) if ramp else Color.WHITE
		_quad(st, al, ar, br, bl, Vector2(0, sa / 7.0), Vector2(1, sb / 7.0), col)
		road_faces.append_array([al, ar, br, al, br, bl])
		# kerbs (red/white every 3 m)
		var kc := Color(0.85, 0.15, 0.1) if int(sa / 3.0) % 2 == 0 else Color(0.95, 0.95, 0.9)
		var up := Vector3(0, 0.02, 0)
		_quad(kerb, al + up, al + ra * 0.7 + up, bl + rb * 0.7 + up, bl + up, Vector2.ZERO, Vector2.ONE, kc)
		_quad(kerb, ar - ra * 0.7 + up, ar + up, br + up, br - rb * 0.7 + up, Vector2.ZERO, Vector2.ONE, kc)
		# low walls: inner face, top, outer face (collision taller than visual)
		for sd: float in [-1.0, 1.0]:
			var wa: Vector3 = a + ra * sd * (hw + 0.3)
			var wb: Vector3 = b + rb * sd * (hw + 0.3)
			var wa2: Vector3 = a + ra * sd * (hw + 1.1)
			var wb2: Vector3 = b + rb * sd * (hw + 1.1)
			var wcol := Color(0.78, 0.58, 0.38)
			var dn := Vector3(0, -3.0, 0)
			var upv := Vector3(0, wh, 0)
			_quad(wall, wa + dn, wb + dn, wb + upv, wa + upv, Vector2.ZERO, Vector2.ONE, wcol)
			_quad(wall, wa + upv, wb + upv, wb2 + upv, wa2 + upv, Vector2.ZERO, Vector2.ONE, wcol.lightened(0.15))
			_quad(wall, wa2 + upv, wb2 + upv, wb2 + dn, wa2 + dn, Vector2.ZERO, Vector2.ONE, wcol.darkened(0.1))
			var ch := Vector3(0, 3.2, 0)
			wall_faces.append_array([wa + dn, wb + dn, wb + ch, wa + dn, wb + ch, wa + ch])
	# end barrier
	var e: Vector3 = pts[pts.size() - 1][0]
	var eh: float = pts[pts.size() - 1][1]
	var er := Vector3(cos(eh), 0, -sin(eh))
	var bar := [e - er * (hw + 1) + Vector3(0, -3, 0), e + er * (hw + 1) + Vector3(0, -3, 0), e + er * (hw + 1) + Vector3(0, 3.2, 0), e - er * (hw + 1) + Vector3(0, 3.2, 0)]
	wall_faces.append_array([bar[0], bar[1], bar[2], bar[0], bar[2], bar[3]])
	_quad(wall, bar[0], bar[1], bar[2] - Vector3(0, 2.0, 0), bar[3] - Vector3(0, 2.0, 0), Vector2.ZERO, Vector2.ONE, Color(0.9, 0.2, 0.1))
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_texture = _road_texture()
	road_mat.vertex_color_use_as_albedo = true
	road_mat.roughness = 0.9
	road_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	plain.roughness = 0.85
	plain.cull_mode = BaseMaterial3D.CULL_DISABLED
	for pair in [[st, road_mat, "Road"], [kerb, plain, "Kerbs"], [wall, plain, "Walls"]]:
		var t: SurfaceTool = pair[0]
		t.generate_normals()
		var mi := MeshInstance3D.new()
		mi.name = pair[2]
		mi.mesh = t.commit()
		mi.material_override = pair[1]
		add_child(mi)
	# collision: ground (layer 1, raycasts only) and walls (layer 2)
	var ground := StaticBody3D.new()
	ground.name = "RoadCollision"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var gs := ConcavePolygonShape3D.new()
	gs.set_faces(road_faces)
	gs.backface_collision = true
	var gcs := CollisionShape3D.new(); gcs.shape = gs
	ground.add_child(gcs)
	add_child(ground)
	var walls := StaticBody3D.new()
	walls.name = "WallCollision"
	walls.collision_layer = 2
	walls.collision_mask = 0
	var ws := ConcavePolygonShape3D.new()
	ws.set_faces(wall_faces)
	ws.backface_collision = true
	var wcs := CollisionShape3D.new(); wcs.shape = ws
	walls.add_child(wcs)
	add_child(walls)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv0: Vector2, uv1: Vector2, col: Color) -> void:
	# a-b at start (left,right), c-d at end (right,left); wound for upward normals
	var uvs := [Vector2(uv0.x, uv0.y), Vector2(uv1.x, uv0.y), Vector2(uv1.x, uv1.y), Vector2(uv0.x, uv1.y)]
	var vs := [a, b, c, d]
	for idx in [0, 2, 1, 0, 3, 2]:
		st.set_color(col)
		st.set_uv(uvs[idx])
		st.add_vertex(vs[idx])


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.33, 0.58, 0.88)
	sm.sky_horizon_color = Color(0.95, 0.82, 0.62)
	sm.ground_horizon_color = Color(0.9, 0.75, 0.55)
	sm.ground_bottom_color = Color(0.7, 0.55, 0.38)
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.83, 0.65)
	env.fog_density = 0.0016
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _build_terrain() -> void:
	if _terrain.is_empty():
		return
	var nx := int(_tinfo.nx)
	var nz := int(_tinfo.nz)
	var cell := float(_tinfo.cell)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in nz:
		for ix in nx:
			var h := _terrain[iz * nx + ix]
			var c := Color(0.93, 0.76, 0.5).lerp(Color(0.85, 0.62, 0.38), clampf((h + 2.0) / 14.0, 0.0, 1.0))
			c = c.darkened(0.04 * sin(ix * 1.7 + iz * 2.3))
			st.set_color(c)
			st.set_uv(Vector2(ix, iz) * 0.25)
			st.add_vertex(Vector3(float(_tinfo.x0) + ix * cell, h, float(_tinfo.z0) + iz * cell))
	for iz in nz - 1:
		for ix in nx - 1:
			var i0 := iz * nx + ix
			var i1 := i0 + 1
			var i2 := i0 + nx
			var i3 := i2 + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i2)
			st.add_index(i1); st.add_index(i3); st.add_index(i2)
	st.generate_normals()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Dunes"
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# far sand plane to the horizon
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000, 6000)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.9, 0.72, 0.48)
	pm.roughness = 1.0
	var pmi := MeshInstance3D.new()
	pmi.mesh = plane
	pmi.material_override = pm
	pmi.position = Vector3(0, -2.5, 0)
	add_child(pmi)


func _chevron_texture(col: Color) -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var v := absf(x - 32.0) * 0.6 + float(y % 32)
			var on := fmod(v, 32.0) < 12.0
			img.set_pixel(x, y, col if on else col.darkened(0.55))
	return ImageTexture.create_from_image(img)


func _build_pads_and_lines() -> void:
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_texture = _chevron_texture(Color(0.2, 0.9, 1.0))
	pad_mat.emission_enabled = true
	pad_mat.emission_texture = pad_mat.albedo_texture
	pad_mat.emission_energy_multiplier = 1.4
	pad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trap_mat := pad_mat.duplicate()
	trap_mat.albedo_texture = _chevron_texture(Color(1.0, 0.75, 0.15))
	trap_mat.emission_texture = trap_mat.albedo_texture
	for p in boost_pads:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var s: float = p.s
		while s < p.s + p.len - 0.1:
			var s2 := minf(s + 2.0, p.s + p.len)
			var w1 := 4.0; var w2 := 4.0
			if p.shape == "trapezoid":
				w1 = lerpf(2.5, half_width - 0.5, (s - p.s) / p.len)
				w2 = lerpf(2.5, half_width - 0.5, (s2 - p.s) / p.len)
			var up := Vector3(0, 0.04, 0)
			var a := point_at(s) - right_at(s) * w1 + up
			var b := point_at(s) + right_at(s) * w1 + up
			var c := point_at(s2) + right_at(s2) * w2 + up
			var d := point_at(s2) - right_at(s2) * w2 + up
			_quad(st, a, b, c, d, Vector2(0, -(s - p.s) / 4.0), Vector2(1, -(s2 - p.s) / 4.0), Color.WHITE)
			s = s2
		var mi := MeshInstance3D.new()
		mi.name = "BoostPad_" + str(p.name)
		mi.mesh = st.commit()
		mi.material_override = trap_mat if p.shape == "trapezoid" else pad_mat
		add_child(mi)
	# start & finish checkered lines + banners
	for info in [[start_s, "START  起点"], [length, "FINISH  终点"]]:
		var s: float = info[0]
		var img := Image.create(16, 2, false, Image.FORMAT_RGB8)
		for x in 16:
			for y in 2:
				img.set_pixel(x, y, Color.WHITE if (x + y) % 2 == 0 else Color.BLACK)
		var tex := ImageTexture.create_from_image(img)
		var m := StandardMaterial3D.new()
		m.albedo_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var up := Vector3(0, 0.05, 0)
		var c0 := point_at(s - 1.0); var c1 := point_at(s + 1.0)
		var r := right_at(s) * half_width
		_quad(st, c0 - r + up, c0 + r + up, c1 + r + up, c1 - r + up, Vector2.ZERO, Vector2.ONE, Color.WHITE)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = m
		add_child(mi)
		# gantry
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.85, 0.2, 0.15)
		for sd in [-1, 1]:
			var post := MeshInstance3D.new()
			var pb := BoxMesh.new(); pb.size = Vector3(0.8, 7.0, 0.8)
			post.mesh = pb
			post.material_override = gm
			post.position = point_at(s) + right_at(s) * sd * (half_width + 1.5) + Vector3(0, 3.5, 0)
			add_child(post)
		var beam := MeshInstance3D.new()
		var bb := BoxMesh.new(); bb.size = Vector3(half_width * 2 + 4, 1.4, 0.6)
		beam.mesh = bb
		beam.material_override = gm
		beam.position = point_at(s) + Vector3(0, 7.2, 0)
		beam.rotation.y = heading_at(s)
		add_child(beam)
		var lbl := Label3D.new()
		lbl.text = info[1]
		lbl.font_size = 96
		lbl.pixel_size = 0.012
		lbl.position = point_at(s) + Vector3(0, 7.2, 0) - tangent_at(s) * 0.35
		lbl.rotation.y = heading_at(s) + PI
		lbl.modulate = Color(1, 0.95, 0.7)
		lbl.outline_size = 12
		add_child(lbl)
