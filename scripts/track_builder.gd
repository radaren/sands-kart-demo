class_name TrackBuilder
extends Node3D
## Builds the drivable world from TrackData: road ribbon, walls, boost pads,
## item box rows, gates, dune terrain and scenery.
##
## Generated once in _ready(). The road and the (invisible, tall) wall faces
## use ConcavePolygonShape3D so karts follow slopes and ramps exactly.

signal item_box_collected(kart: Node3D)
signal boost_pad_entered(kart: Node3D)

const LAYER_WORLD := 1
const LAYER_KART := 2
const LAYER_TRIGGER := 4
const LAYER_WALL := 8

const TERRAIN_CELL := 8.0          ## T4: was 12 m; indexed + smooth normals now
## T3: canyon zone (track distance, m): U-turns + sweeper between the ramp
## basin and the dunes. Terrain 8.5-34 m off the road rises to road + 14-25 m.
const CANYON_FROM := 630.0
const CANYON_TO := 1180.0
var build_ms := {}
const BUCKET_SIZE := 24.0
const WALL_COLLISION_HEIGHT := 4.5
const ITEM_RESPAWN := 1.2

@export var build_on_ready := true

var track: TrackData
var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _buckets := {}

var item_box_nodes: Array[Node3D] = []


func _ready() -> void:
	if build_on_ready:
		build()


func build() -> void:
	track = TrackData.load_default()
	_noise.seed = 20261019
	_noise.frequency = 0.006
	_noise.fractal_octaves = 4
	_detail.seed = 77
	_detail.frequency = 0.05
	var t0 := Time.get_ticks_usec()
	_index_track()
	_build_road()
	_build_walls()
	_build_road_marks()
	var t1 := Time.get_ticks_usec()
	_build_terrain()
	build_ms["terrain"] = (Time.get_ticks_usec() - t1) / 1000.0
	_build_gates()
	_build_boost_pads()
	_build_item_rows()
	var t2 := Time.get_ticks_usec()
	_build_scenery()
	_build_roadside_band()
	build_ms["scenery"] = (Time.get_ticks_usec() - t2) / 1000.0
	build_ms["total"] = (Time.get_ticks_usec() - t0) / 1000.0
	print("TRACK BUILD ms ", build_ms, " shadow-off meshes ", shadow_casters_off)


# ---------------------------------------------------------------------------
# spatial lookup
# ---------------------------------------------------------------------------
func _index_track() -> void:
	_buckets.clear()
	for i in track.points.size():
		var p := track.points[i]
		var key := Vector2i(int(floor(p.x / BUCKET_SIZE)), int(floor(p.z / BUCKET_SIZE)))
		if not _buckets.has(key):
			_buckets[key] = PackedInt32Array()
		var arr: PackedInt32Array = _buckets[key]
		arr.append(i)
		_buckets[key] = arr


func nearest_track(x: float, z: float, radius_buckets: int = 2) -> Dictionary:
	var key := Vector2i(int(floor(x / BUCKET_SIZE)), int(floor(z / BUCKET_SIZE)))
	var best := 1e20
	var best_i := -1
	for dx in range(-radius_buckets, radius_buckets + 1):
		for dz in range(-radius_buckets, radius_buckets + 1):
			var k := Vector2i(key.x + dx, key.y + dz)
			if not _buckets.has(k):
				continue
			for i: int in _buckets[k]:
				var p: Vector3 = track.points[i]
				var d := (p.x - x) * (p.x - x) + (p.z - z) * (p.z - z)
				if d < best:
					best = d
					best_i = i
	return {"dist": sqrt(best) if best_i >= 0 else 1e9, "index": best_i}


## Height of the dune field, blended down to the road shoulder near the ribbon.
func terrain_height(x: float, z: float) -> float:
	var nearest := nearest_track(x, z, 4)
	var dune := _noise.get_noise_2d(x, z) * 15.0 + _detail.get_noise_2d(x, z) * 1.4
	var base := -3.0 + dune
	var dist: float = nearest["dist"]
	if nearest["index"] >= 0 and dist < 90.0:
		var road_y: float = track.points[nearest["index"]].y
		if dist < 7.2:
			return road_y - 1.4
		var shoulder := road_y - 0.45
		var t := clampf((dist - 7.2) / 70.0, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		var h := lerpf(shoulder, maxf(base, shoulder - 4.0), t)
		var w := canyon_weight(float(nearest["index"]) * track.step)
		if w > 0.0:
			var wall_y := road_y + lerpf(14.0, 25.0, _detail.get_noise_2d(x * 0.3, z * 0.3) * 0.5 + 0.5)
			var prof := smoothstep(8.5, 14.0, dist) * (1.0 - smoothstep(34.0, 64.0, dist))
			h = maxf(h, lerpf(h, wall_y, prof * w))
		return h
	return base


## 0..1 canyon strength at track distance s (40 m ramps at both ends).
func canyon_weight(s: float) -> float:
	return smoothstep(CANYON_FROM - 40.0, CANYON_FROM, s) * (1.0 - smoothstep(CANYON_TO, CANYON_TO + 40.0, s))


# ---------------------------------------------------------------------------
# mesh helpers
# ---------------------------------------------------------------------------
func _surface_tool(material: Material) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if material != null:
		st.set_material(material)
	return st


## Emits a quad whose front face points along `want`.
## Godot treats clockwise winding (seen from the front) as the front face, so
## the front normal of triangle (a, b, c) is (c - a) x (b - a).
func _emit_quad(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		want: Vector3, uvs: Array) -> void:
	var normal := (c - a).cross(b - a)
	if normal.dot(want) < 0.0:
		var tb := b
		b = d
		d = tb
		var tu: Variant = uvs[1]
		uvs[1] = uvs[3]
		uvs[3] = tu
		normal = (c - a).cross(b - a)
	normal = normal.normalized()
	var verts := [a, b, c, a, c, d]
	var order := [0, 1, 2, 0, 2, 3]
	for k in 6:
		st.set_normal(normal)
		st.set_uv(uvs[order[k]])
		st.add_vertex(verts[k])
	faces.append(a)
	faces.append(b)
	faces.append(c)
	faces.append(a)
	faces.append(c)
	faces.append(d)


func _static_body(node_name: String, faces: PackedVector3Array, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = layer
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body


func _mesh_instance(node_name: String, st: SurfaceTool, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = st.commit()
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _flat_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.72
	return mat


func _shader_material(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


const ROAD_SHADER := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec3 surface : source_color = vec3(0.36, 0.30, 0.26);
uniform vec3 sand : source_color = vec3(0.82, 0.66, 0.43);
uniform vec3 curb_red : source_color = vec3(0.72, 0.13, 0.10);
uniform vec3 curb_white : source_color = vec3(0.92, 0.90, 0.85);
uniform float curb_width = 0.05;
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
// smooth value noise: no hard cell edges (T5)
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
// band-limited noise: fades to its mean (0.5) once a cell gets smaller than a pixel
float grain_at(vec2 p) {
	vec2 w = fwidth(p);
	float fade = 1.0 - smoothstep(0.35, 1.0, max(w.x, w.y));
	return mix(0.5, vnoise(p), fade);
}
// anti-aliased step for stripes
float aa_step(float edge, float x) {
	float w = max(fwidth(x), 1e-4);
	return smoothstep(edge - w, edge + w, x);
}
void fragment() {
	vec2 uv = UV;
	float grain = 0.6 * grain_at(uv * vec2(180.0, 110.0)) + 0.4 * grain_at(uv * vec2(45.0, 28.0));
	float patches = vnoise(uv * vec2(7.0, 4.0));
	vec3 base = mix(surface, sand, 0.28 * (0.25 + 0.75 * patches));
	base *= 0.86 + 0.28 * grain;
	float edge = min(uv.x, 1.0 - uv.x);
	float curb = 1.0 - aa_step(curb_width, edge);
	float gutter = (1.0 - aa_step(curb_width * 1.6, edge)) * (1.0 - curb);
	float stripe = fract(uv.y * 2.4);
	float band = aa_step(0.5, stripe) * (1.0 - aa_step(0.98, stripe));
	vec3 curb_col = mix(curb_red, curb_white, band) * (0.9 + 0.16 * grain);
	base = mix(base, curb_col, curb);
	base *= 1.0 - 0.42 * gutter;
	float centre = abs(uv.x - 0.5);
	float dashp = fract(uv.y * 0.9);
	float dash = aa_step(0.5, dashp) * (1.0 - aa_step(0.98, dashp)) * (1.0 - aa_step(0.006, centre));
	base = mix(base, vec3(0.93, 0.86, 0.62), 0.75 * dash);
	ALBEDO = base;
	ROUGHNESS = 0.88;
	SPECULAR = 0.16;
}
"""

const WALL_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 rock : source_color = vec3(0.74, 0.58, 0.38);
uniform vec3 warn : source_color = vec3(0.84, 0.45, 0.17);
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
void fragment() {
	float blocks = step(0.5, fract(UV.y * 0.5));
	vec2 gp = UV * vec2(24.0, 5.0);
	vec2 gw = fwidth(gp);
	float grain = mix(0.5, hash12(floor(gp)), 1.0 - smoothstep(0.35, 1.0, max(gw.x, gw.y)));
	vec3 base = mix(rock, warn, 0.32 * blocks);
	base *= 0.8 + 0.3 * grain;
	ALBEDO = base;
	ROUGHNESS = 0.93;
}
"""

const TERRAIN_SHADER := """
shader_type spatial;
render_mode diffuse_burley;
uniform vec3 sand_light : source_color = vec3(0.89, 0.76, 0.54);
uniform vec3 sand_dark : source_color = vec3(0.66, 0.50, 0.31);
uniform vec3 crest : source_color = vec3(0.97, 0.89, 0.71);
varying vec3 world_pos;
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float big = vnoise(world_pos.xz * 0.02);
	float ripple = sin(world_pos.x * 0.9 + vnoise(world_pos.xz * 0.15) * 6.0) * 0.5 + 0.5;
	vec3 col = mix(sand_dark, sand_light, 0.35 + 0.65 * big);
	col = mix(col, crest, smoothstep(2.0, 12.0, world_pos.y) * 0.5);
	col *= 0.93 + 0.1 * ripple;
	// T3: steep faces (canyon walls) read as layered sandstone
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float rock = 1.0 - smoothstep(0.72, 0.93, wn.y);
	float band = sin(world_pos.y * 1.7 + vnoise(world_pos.xz * 0.08) * 3.0) * 0.5 + 0.5;
	vec3 stone = mix(vec3(0.62, 0.36, 0.22), vec3(0.80, 0.54, 0.34), band);
	col = mix(col, stone, rock);
	ALBEDO = col;
	ROUGHNESS = 0.97;
}
"""


# ---------------------------------------------------------------------------
# road + walls
# ---------------------------------------------------------------------------
func _build_road() -> void:
	var st := _surface_tool(_shader_material(ROAD_SHADER))
	var faces := PackedVector3Array()
	var half := track.road_width * 0.5
	for i in range(track.points.size() - 1):
		var p0 := track.points[i]
		var p1 := track.points[i + 1]
		var r0 := track.rights[i]
		var r1 := track.rights[i + 1]
		var v0 := track.cum[i] / 9.0
		var v1 := track.cum[i + 1] / 9.0
		_emit_quad(st, faces,
				p0 - r0 * half, p0 + r0 * half, p1 + r1 * half, p1 - r1 * half,
				Vector3.UP,
				[Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)])
	_mesh_instance("Road", st)
	_static_body("RoadBody", faces, LAYER_WORLD)


func _build_walls() -> void:
	var st := _surface_tool(_shader_material(WALL_SHADER))
	var visual := PackedVector3Array()
	var collision := PackedVector3Array()
	var n := track.points.size()
	var half := track.road_width * 0.5
	var inner_h := track.wall_height
	var outer_h := track.wall_height * 0.7
	var thick := 0.9
	var up := Vector3.UP
	for side in [-1.0, 1.0]:
		for i in range(n - 1):
			var p0 := track.points[i]
			var p1 := track.points[i + 1]
			var r0: Vector3 = track.rights[i] * side
			var r1: Vector3 = track.rights[i + 1] * side
			var i0 := p0 + r0 * half
			var i1 := p1 + r1 * half
			var o0 := p0 + r0 * (half + thick)
			var o1 := p1 + r1 * (half + thick)
			var v0: float = track.cum[i] / 3.0
			var v1: float = track.cum[i + 1] / 3.0
			var inward: Vector3 = -(r0 + r1).normalized()
			var uvs := [Vector2(0, v0), Vector2(0, v1), Vector2(1, v1), Vector2(1, v0)]
			_emit_quad(st, visual, i0, i1, i1 + up * inner_h, i0 + up * inner_h, inward, uvs.duplicate())
			_emit_quad(st, visual, i0 + up * inner_h, i1 + up * inner_h, o1 + up * outer_h, o0 + up * outer_h, up, uvs.duplicate())
			_emit_quad(st, visual, o0 + up * outer_h, o1 + up * outer_h, o1 - up * 2.2, o0 - up * 2.2, -inward, uvs.duplicate())
			# tall invisible barrier on the inner face
			collision.append(i0 - up * 0.6)
			collision.append(i1 - up * 0.6)
			collision.append(i1 + up * WALL_COLLISION_HEIGHT)
			collision.append(i0 - up * 0.6)
			collision.append(i1 + up * WALL_COLLISION_HEIGHT)
			collision.append(i0 + up * WALL_COLLISION_HEIGHT)
	# end caps so nobody can drive off either end of the ribbon
	for cap_i in [0, n - 1]:
		var p := track.points[cap_i]
		var r := track.rights[cap_i]
		var t := track.tangents[cap_i]
		var outward := -t if cap_i == 0 else t
		var a := p - r * (half + thick)
		var b := p + r * (half + thick)
		_emit_quad(st, visual, a, b, b + up * 1.6, a + up * 1.6, -outward,
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		collision.append(a - up * 0.6)
		collision.append(b - up * 0.6)
		collision.append(b + up * WALL_COLLISION_HEIGHT)
		collision.append(a - up * 0.6)
		collision.append(b + up * WALL_COLLISION_HEIGHT)
		collision.append(a + up * WALL_COLLISION_HEIGHT)
	_mesh_instance("Walls", st)
	_static_body("WallBody", collision, LAYER_WALL)


func _build_road_marks() -> void:
	_add_checker_band(track.start_offset)
	_add_checker_band(track.finish_offset)
	for r in track.ramps:
		_add_chevrons(r)


func _add_checker_band(s: float) -> void:
	var st := _surface_tool(_flat_material(Color(0.95, 0.94, 0.90)))
	var half := track.road_width * 0.5
	var depth := 2.6
	var cols := 10
	var rows := 4
	var lift := Vector3.UP * 0.03
	for k in rows:
		var a_s := s + (k / float(rows)) * depth
		var b_s := s + ((k + 1) / float(rows)) * depth
		for c in cols:
			if (k + c) % 2 != 0:
				continue
			var t0 := -half + (c / float(cols)) * track.road_width
			var t1 := -half + ((c + 1) / float(cols)) * track.road_width
			_emit_quad(st, PackedVector3Array(),
					track.position_at(a_s) + track.right_at(a_s) * t0 + lift,
					track.position_at(a_s) + track.right_at(a_s) * t1 + lift,
					track.position_at(b_s) + track.right_at(b_s) * t1 + lift,
					track.position_at(b_s) + track.right_at(b_s) * t0 + lift,
					Vector3.UP, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	_mesh_instance("CheckerBand", st, false)


func _add_chevrons(s: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.6, 0.15)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.26, 0.04)
	mat.emission_energy_multiplier = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := _surface_tool(mat)
	var half := track.road_width * 0.5
	for k in 5:
		var base_s := s + k * 2.4
		var tip_s := base_s + 1.6
		var lift := Vector3.UP * 0.05
		var p := track.position_at(base_s) + lift
		var r := track.right_at(base_s)
		var tip := track.position_at(tip_s) + lift
		var l := p - r * (half * 0.55)
		var rr := p + r * (half * 0.55)
		var inner_l := l.lerp(tip, 0.45)
		var inner_r := rr.lerp(tip, 0.45)
		for tri in [[l, tip, inner_l], [rr, inner_r, tip]]:
			for v: Vector3 in tri:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(v)
	_mesh_instance("RampChevrons", st, false)


# ---------------------------------------------------------------------------
# terrain
# ---------------------------------------------------------------------------
func _build_terrain() -> void:
	var bbox := AABB(track.points[0], Vector3.ZERO)
	for p in track.points:
		bbox = bbox.expand(p)
	bbox = bbox.grow(340.0)
	var cols := int(bbox.size.x / TERRAIN_CELL) + 1
	var rows := int(bbox.size.z / TERRAIN_CELL) + 1
	var heights := PackedFloat32Array()
	heights.resize((cols + 1) * (rows + 1))
	for ix in cols + 1:
		for iz in rows + 1:
			var x := bbox.position.x + ix * TERRAIN_CELL
			var z := bbox.position.z + iz * TERRAIN_CELL
			heights[ix * (rows + 1) + iz] = terrain_height(x, z)
	var st := _surface_tool(_shader_material(TERRAIN_SHADER))
	var none := PackedVector3Array()
	for ix in cols:
		for iz in rows:
			var x0 := bbox.position.x + ix * TERRAIN_CELL
			var z0 := bbox.position.z + iz * TERRAIN_CELL
			var x1 := x0 + TERRAIN_CELL
			var z1 := z0 + TERRAIN_CELL
			_emit_quad(st, none,
					Vector3(x0, heights[ix * (rows + 1) + iz], z0),
					Vector3(x1, heights[(ix + 1) * (rows + 1) + iz], z0),
					Vector3(x1, heights[(ix + 1) * (rows + 1) + iz + 1], z1),
					Vector3(x0, heights[ix * (rows + 1) + iz + 1], z1),
					Vector3.UP, [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	st.index()                 # T4: share vertices so normals are smooth, not faceted
	st.generate_normals()
	_mesh_instance("Terrain", st, false)


# ---------------------------------------------------------------------------
# gates
# ---------------------------------------------------------------------------
func _build_gates() -> void:
	_add_gate(track.start_offset, "StartGate", Color(0.14, 0.52, 0.30), false)
	_add_gate(track.finish_offset, "FinishGate", Color(0.86, 0.72, 0.20), true)


func _add_gate(s: float, gate_name: String, tint: Color, checkered: bool) -> void:
	var root := Node3D.new()
	root.name = gate_name
	var p := track.position_at(s)
	var t := track.tangent_at(s)
	var half := track.road_width * 0.5 + 1.3
	root.transform = Transform3D(Basis.looking_at(t, Vector3.UP), p)
	add_child(root)
	var stone := _flat_material(Color(0.66, 0.50, 0.32))
	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.9, 7.6, 0.9)
		pillar.mesh = pm
		pillar.material_override = stone
		pillar.position = Vector3(side * half, 3.8, 0.0)
		root.add_child(pillar)
		var cap := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(1.4, 0.5, 1.4)
		cap.mesh = cm
		cap.material_override = _flat_material(tint)
		cap.position = Vector3(side * half, 7.8, 0.0)
		root.add_child(cap)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(half * 2.0 + 0.9, 0.9, 1.0)
	beam.mesh = bm
	beam.material_override = _flat_material(tint)
	beam.position = Vector3(0.0, 7.2, 0.0)
	root.add_child(beam)
	if checkered:
		for k in 12:
			var tile := MeshInstance3D.new()
			var tm := BoxMesh.new()
			tm.size = Vector3(half * 2.0 / 12.0, 0.5, 1.05)
			tile.mesh = tm
			tile.material_override = _flat_material(Color(0.06, 0.06, 0.06) if k % 2 == 0 else Color(0.96, 0.96, 0.96))
			tile.position = Vector3(-half + (k + 0.5) * (half * 2.0 / 12.0), 6.45, 0.0)
			root.add_child(tile)
	var label := Label3D.new()
	label.text = "终点 FINISH" if checkered else "起点 START"
	label.font_size = 96
	label.pixel_size = 0.01
	label.outline_size = 18
	label.modulate = Color(1, 0.97, 0.88)
	label.position = Vector3(0.0, 7.2, 0.55)
	label.rotation_degrees = Vector3(0, 180, 0)
	root.add_child(label)
	var back := label.duplicate() as Label3D
	back.position = Vector3(0.0, 7.2, -0.55)
	back.rotation_degrees = Vector3.ZERO
	root.add_child(back)


# ---------------------------------------------------------------------------
# boost pads + item boxes
# ---------------------------------------------------------------------------
const BOOST_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled;
uniform vec3 tint : source_color = vec3(0.15, 0.72, 0.98);
void fragment() {
	vec2 uv = UV;
	float chevron = fract((1.0 - uv.y) * 3.0 + abs(uv.x - 0.5) * 1.6 - TIME * 2.2);
	float band = smoothstep(0.0, 0.1, chevron) * smoothstep(0.5, 0.3, chevron);
	float border = step(0.42, abs(uv.x - 0.5)) + step(0.46, abs(uv.y - 0.5));
	vec3 col = mix(tint * 0.55, vec3(0.85, 0.98, 1.0), band);
	col = mix(col, vec3(1.0, 0.85, 0.2), clamp(border, 0.0, 1.0));
	ALBEDO = col;
	EMISSION = col * 1.2;
	ALPHA = 0.88;
}
"""


func _build_boost_pads() -> void:
	var mat := _shader_material(BOOST_SHADER)
	var half := track.road_width * 0.5
	var flip := false
	for s in track.boosts:
		var lateral := (half * 0.42) * (-1.0 if flip else 1.0)
		flip = not flip
		var root := Node3D.new()
		root.name = "BoostPad"
		var base_p := track.position_at(s) + track.right_at(s) * lateral
		root.transform = Transform3D(Basis.looking_at(track.tangent_at(s), Vector3.UP), base_p + Vector3.UP * 0.06)
		add_child(root)
		var quad := MeshInstance3D.new()
		var qm := PlaneMesh.new()
		qm.size = Vector2(4.2, 8.0)
		quad.mesh = qm
		quad.material_override = mat
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(quad)
		var area := Area3D.new()
		area.name = "Trigger"
		area.collision_layer = LAYER_TRIGGER
		area.collision_mask = LAYER_KART
		area.monitorable = false
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.2, 3.0, 8.0)
		cs.shape = box
		cs.position = Vector3(0, 1.2, 0)
		area.add_child(cs)
		root.add_child(area)
		area.body_entered.connect(func(body: Node3D) -> void: boost_pad_entered.emit(body))


const ITEM_BOX_SHADER := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled;
uniform vec3 tint : source_color = vec3(0.98, 0.72, 0.16);
void fragment() {
	vec2 c = abs(UV - vec2(0.5)) * 2.0;
	float rim = smoothstep(0.7, 0.95, max(c.x, c.y));
	float shimmer = 0.5 + 0.5 * sin(TIME * 4.0 + UV.x * 6.0 + UV.y * 4.0);
	vec3 col = mix(tint * (0.8 + 0.4 * shimmer), vec3(1.0, 0.98, 0.9), rim);
	ALBEDO = col;
	EMISSION = col * (0.6 + rim);
	ALPHA = mix(0.55, 0.95, rim);
}
"""


const ITEM_ROW_A := [-4.6, -2.1, 2.1, 4.6]   ## lateral metres (for a 12 m road): centre gap
const ITEM_ROW_B := [-3.7, 0.0, 3.7]          ## staggered: gaps between the boxes
const ITEM_TRIGGER_RADIUS := 0.5   # K11: karts are 1.7 m wide now; keeps reach ~1.35 m


func _build_item_rows() -> void:
	var mat := _shader_material(ITEM_BOX_SHADER)
	var half := track.road_width * 0.5
	var row_i := -1
	for s in track.item_rows:
		row_i += 1
		# I1: not a wall of boxes any more — 4 / 3 boxes, staggered row to row,
		# small triggers, so some lines miss and picking boxes is a choice.
		var laterals: Array = ITEM_ROW_A if row_i % 2 == 0 else ITEM_ROW_B
		for slot in laterals.size():
			var lateral: float = laterals[slot] * half / 6.0
			var base := track.position_at(s) + track.right_at(s) * lateral
			var holder := Node3D.new()
			holder.name = "ItemBox"
			holder.position = base + Vector3.UP * 1.25
			holder.set_meta("base_y", holder.position.y)
			holder.set_meta("phase", float(slot) * 1.3 + s * 0.01)
			holder.set_meta("active", true)
			holder.set_meta("s", s)
			holder.set_meta("lateral", lateral)
			add_child(holder)
			var mi := MeshInstance3D.new()
			mi.name = "Mesh"
			var bm := BoxMesh.new()
			bm.size = Vector3(1.05, 1.05, 1.05)
			mi.mesh = bm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)
			var mark := Label3D.new()
			mark.name = "Mark"
			mark.text = "?"
			mark.font_size = 72
			mark.pixel_size = 0.012
			mark.outline_size = 14
			mark.modulate = Color(1, 1, 1)
			mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			mark.no_depth_test = false
			holder.add_child(mark)
			var area := Area3D.new()
			area.name = "Trigger"
			area.collision_layer = LAYER_TRIGGER
			area.collision_mask = LAYER_KART
			area.monitorable = false
			var cs := CollisionShape3D.new()
			var sphere := SphereShape3D.new()
			sphere.radius = ITEM_TRIGGER_RADIUS
			cs.shape = sphere
			area.add_child(cs)
			holder.add_child(area)
			area.body_entered.connect(_on_item_box_body.bind(holder))
			holder.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # animated in _process
			item_box_nodes.append(holder)


func _on_item_box_body(body: Node3D, holder: Node3D) -> void:
	if not holder.get_meta("active", false):
		return
	if not body.has_method("receive_item_box"):
		return
	if body is Kart and (body as Kart).items.size() >= Kart.MAX_ITEMS:
		return   # I2: full slots leave the box for someone else
	holder.set_meta("active", false)
	(holder.get_node("Mesh") as Node3D).visible = false
	(holder.get_node("Mark") as Node3D).visible = false
	item_box_collected.emit(body)
	get_tree().create_timer(ITEM_RESPAWN, false).timeout.connect(func() -> void:
		if is_instance_valid(holder):
			holder.set_meta("active", true)
			(holder.get_node("Mesh") as Node3D).visible = true
			(holder.get_node("Mark") as Node3D).visible = true)


var _bob_t := 0.0


func _process(delta: float) -> void:
	# Only the visuals spin and bob; the holder (and its trigger) stays put, so
	# pickups don't depend on the bob phase / frame timing (that made the same
	# seed pass or fail between runs).
	_bob_t += delta
	for holder in item_box_nodes:
		var phase: float = holder.get_meta("phase", 0.0)
		var y := sin(_bob_t * 2.0 + phase) * 0.18
		var m := holder.get_node("Mesh") as Node3D
		m.rotate_y(delta * 1.6)
		m.position.y = y
		(holder.get_node("Mark") as Node3D).position.y = y


## Lateral offset of the active item box closest to `lateral` in the first row
## found within [s_from, s_to] (NAN when none). Used by AI to aim for boxes.
func box_lateral_ahead(s_from: float, s_to: float, lateral: float) -> float:
	var best := NAN
	var best_s := INF
	for h in item_box_nodes:
		if not h.get_meta("active", false):
			continue
		var hs: float = h.get_meta("s", -1.0)
		if hs < s_from or hs > s_to or hs > best_s + 1.0:
			continue
		var hl: float = h.get_meta("lateral", 0.0)
		if hs < best_s - 1.0 or is_nan(best) or absf(hl - lateral) < absf(best - lateral):
			best = hl
			best_s = hs
	return best


## All active boxes of the first row within [s_from, s_to]: [[s, lateral], ...]
func boxes_in_row(s_from: float, s_to: float) -> Array:
	var row_s := INF
	for h in item_box_nodes:
		var hs: float = h.get_meta("s", -1.0)
		if hs >= s_from and hs <= s_to and hs < row_s:
			row_s = hs
	var out := []
	if row_s == INF:
		return out
	for h in item_box_nodes:
		if h.get_meta("active", false) and absf(float(h.get_meta("s", -1.0)) - row_s) < 1.0:
			out.append([row_s, float(h.get_meta("lateral", 0.0))])
	return out


## Nearest active item box lateral offsets within [s_from, s_to]; used by AI.
func item_row_ahead(s_from: float, s_to: float) -> float:
	for s in track.item_rows:
		if s >= s_from and s <= s_to:
			return s
	return -1.0


# ---------------------------------------------------------------------------
# scenery
# ---------------------------------------------------------------------------
## Town = from the start gate to just past the first ramp (飞跃进凹地);
## everything after is open dunes. Manifest entries carry a `scale` (the cloud
## models are authored at very different sizes) and a `zone` (town/dunes/any).
func town_end() -> float:
	return (track.ramps[0] + 60.0) if track.ramps.size() > 0 else track.length * 0.25


func _build_scenery() -> void:
	var grape := _load_manifest("res://data/grape_props.json")
	var cloud := _load_manifest("res://data/assets_manifest.json")
	var town_pool: Array = []
	var dune_pool: Array = []
	var far_pool: Array = []
	var near_keys := ["mud_house_a", "mud_house_b", "mud_house_c", "ruin_pillar_a", "ruin_pillar_b",
			"column_broken", "obelisk", "sand_rock_a", "sand_rock_b",
			"cactus_a", "cactus_b", "cactus_c", "cactus_d", "cactus_e", "cactus_f",
			"palm_a", "palm_b", "palm_c", "palm_d", "rock_a", "rock_b", "rock_c"]
	for key in near_keys:
		var entry := _manifest_entry(key, grape, cloud)
		if entry.is_empty():
			continue
		var zone := str(entry.get("zone", "any"))
		# houses are weighted up in town, cacti/rocks in the dunes
		var weight := 3 if key.begins_with("mud_house") else (2 if key.begins_with("cactus") else 1)
		for w in weight:
			if zone != "dunes":
				town_pool.append(entry)
			if zone != "town":
				dune_pool.append(entry)
	for key in ["pyramid", "obelisk", "sand_rock_a", "rock_a", "rock_b", "rock_c", "mud_house_b"]:
		var entry := _manifest_entry(key, grape, cloud)
		if not entry.is_empty():
			far_pool.append(entry.merged({"key": key}))
	if town_pool.is_empty() and dune_pool.is_empty():
		push_warning("TrackBuilder: no scenery assets found, using blockout rocks")
		for k in 3:
			dune_pool.append({"scene": _blockout_rock(k), "scale": 1.0})
	if town_pool.is_empty():
		town_pool = dune_pool
	if dune_pool.is_empty():
		dune_pool = town_pool
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var t_end := town_end()
	var s := 20.0
	var side := 1.0
	while s < track.length - 20.0:
		var in_town := s < t_end
		var pool: Array = town_pool if in_town else dune_pool
		var count := rng.randi_range(1, 3) if in_town else rng.randi_range(1, 2)
		for k in count:
			var at := s + k * 7.0
			if canyon_weight(at) > 0.1:
				continue      # T3: the canyon walls replace the roadside props there
			var lateral := side * (rng.randf_range(11.5, 20.0) if in_town else rng.randf_range(12.0, 34.0))
			var pos := track.position_at(at) + track.right_at(at) * lateral
			var near := nearest_track(pos.x, pos.z, 2)
			if float(near["dist"]) < 11.0:
				continue
			pos.y = terrain_height(pos.x, pos.z) - 0.1
			var entry: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			var node := _spawn_prop(entry["scene"], pos, rng, 0.9 * float(entry["scale"]), 1.25 * float(entry["scale"]))
			if node != null and in_town and str(entry.get("key", "")).begins_with("mud_house"):
				# face the road
				var to_road := track.position_at(at) - pos
				node.rotation.y = atan2(to_road.x, to_road.z)
		side = -side
		s += rng.randf_range(14.0, 22.0) if in_town else rng.randf_range(22.0, 38.0)
	_place_town_arches(grape, cloud)
	_place_backdrop(far_pool, dune_pool, rng)


# ---------------------------------------------------------------------------
# T7: near-roadside band
# ---------------------------------------------------------------------------
const BAND_FLAG_COLORS := [Color(0.85, 0.18, 0.12), Color(0.97, 0.80, 0.25), Color(0.16, 0.45, 0.80), Color(0.95, 0.95, 0.9)]
var band_counts := {}    ## T7: instance counts per band layer (for tests)
var band_origins := {}   ## T7: instance positions per layer (the headless renderer can't read MultiMesh back)


func _band_mm(node_name: String, mesh: Mesh, mat: Material, xforms: Array, colors: Array) -> void:
	if xforms.is_empty():
		return
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = node_name
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	band_counts[node_name] = xforms.size()
	band_origins[node_name] = xforms.map(func(x: Transform3D) -> Vector3: return x.origin)


## Markers 8-11 m from the centreline (just outside the walls), no collision:
## pennant posts every 6-10 m, red/white boards on the outside of corners
## tighter than R45, torches in town, the canyon and around start/finish.
## All MultiMesh - four draw calls for the whole band.
func _build_roadside_band() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9107
	var posts := []
	var flags := []
	var flag_cols := []
	var boards := []
	var board_cols := []
	var flames := []
	var t_end := town_end()
	var s := 6.0
	var side := 1.0
	var board_i := 0
	while s < track.length - 4.0:
		var near_gate := absf(s - track.start_offset) < 9.0 or absf(s - track.finish_offset) < 9.0
		var t := track.tangent_at(s)
		var turn := signf(track.tangent_at(s - 3.0).cross(track.tangent_at(s + 3.0)).y)   # +1 left
		var r := track.radius_at(s)
		if not near_gate and r < 45.0:
			# corner: boards on the outside (left turn -> right side)
			var out_side := -turn
			var pos := track.position_at(s) + track.right_at(s) * out_side * 8.6
			pos.y = maxf(terrain_height(pos.x, pos.z), track.position_at(s).y) - 0.05
			var face := Basis.looking_at(-track.right_at(s) * out_side, Vector3.UP)   # board faces the road
			boards.append(Transform3D(face, pos + Vector3.UP * 0.75))
			board_cols.append(Color(0.88, 0.14, 0.1) if board_i % 2 == 0 else Color(0.96, 0.95, 0.9))
			board_i += 1
			s += 5.0
			continue
		if not near_gate:
			var lateral := side * rng.randf_range(8.4, 10.8)
			var pos := track.position_at(s) + track.right_at(s) * lateral
			pos.y = maxf(terrain_height(pos.x, pos.z), track.position_at(s).y - 1.5) - 0.05
			var torch := s < t_end or canyon_weight(s) > 0.3 or absf(s - track.finish_offset) < 70.0 \
					or absf(s - track.start_offset) < 50.0
			var h := 1.9 if torch else 1.6
			posts.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, h / 1.6, 1.0)), pos + Vector3.UP * h * 0.5))
			if torch:
				flames.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, PI)), pos + Vector3.UP * (h + 0.16)))
			else:
				# pennant hangs off the road side of the post, along the travel direction
				var fb := Basis.looking_at(t, Vector3.UP)
				flags.append(Transform3D(fb, pos + Vector3.UP * (h - 0.22) + t * 0.3))
				flag_cols.append(BAND_FLAG_COLORS[rng.randi_range(0, BAND_FLAG_COLORS.size() - 1)])
		side = -side
		s += rng.randf_range(6.0, 10.0) * 0.5   # alternating sides -> 6-10 m per side
	var vc := func(tint: Color, emit: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.albedo_color = tint
		m.roughness = 0.8
		if emit > 0.0:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return m
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.06; post_mesh.bottom_radius = 0.08; post_mesh.height = 1.6
	post_mesh.radial_segments = 6; post_mesh.rings = 1
	var pm := _flat_material(Color(0.36, 0.25, 0.16))
	_band_mm("BandPosts", post_mesh, pm, posts, [])
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.03, 0.34, 0.6)
	_band_mm("BandFlags", flag_mesh, vc.call(Color.WHITE, 0.0), flags, flag_cols)
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.5, 0.9, 0.08)
	_band_mm("BandBoards", board_mesh, vc.call(Color.WHITE, 0.0), boards, board_cols)
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.16; flame_mesh.height = 0.42
	flame_mesh.radial_segments = 6; flame_mesh.rings = 3
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.62, 0.18)
	_band_mm("BandTorches", flame_mesh, fm, flames, [])


func _place_town_arches(grape: Dictionary, cloud: Dictionary) -> void:
	var entry := _manifest_entry("arch_ruin", grape, cloud)
	if entry.is_empty():
		return
	var t_end := town_end()
	for f in [0.18, 0.55, 0.92]:
		var s := lerpf(track.start_offset + 60.0, t_end - 40.0, f)
		var node := (entry["scene"] as PackedScene).instantiate() as Node3D
		if node == null:
			continue
		if "span" in node:
			node.set("span", track.road_width + 3.0)
		var t := track.tangent_at(s)
		node.transform = Transform3D(Basis.looking_at(t, Vector3.UP), track.position_at(s) - Vector3.UP * 0.2)
		node.name = "TownArch"
		add_child(node)


func _manifest_entry(key: String, grape: Dictionary, cloud: Dictionary) -> Dictionary:
	var entry: Dictionary = {}
	if grape.has(key):
		entry = grape[key]
	elif cloud.has(key):
		entry = cloud[key]
	if entry.is_empty():
		return {}
	var path := str(entry.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		return {}
	return {"key": key, "scene": packed, "scale": float(entry.get("scale", 1.0)), "zone": str(entry.get("zone", "any"))}


func _manifest_scene(key: String, grape: Dictionary, cloud: Dictionary) -> PackedScene:
	var entry := _manifest_entry(key, grape, cloud)
	if entry.is_empty():
		return null
	return entry["scene"] as PackedScene


var shadow_casters_off := 0   ## T9: prop meshes with shadows disabled (backdrop / far roadside)


## T9: props further than 22 m from the road never get a visible shadow inside
## the 80 m shadow range at race speed - stop them casting.
func _no_shadows(node: Node3D) -> void:
	for g in node.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shadow_casters_off += 1


func _spawn_prop(packed: PackedScene, pos: Vector3, rng: RandomNumberGenerator, lo: float, hi: float) -> Node3D:
	var inst := packed.instantiate()
	if not (inst is Node3D):
		inst.free()
		return null
	var node := inst as Node3D
	node.position = pos
	node.rotation.y = rng.randf_range(-PI, PI)
	node.scale = Vector3.ONE * rng.randf_range(lo, hi)
	add_child(node)
	if float(nearest_track(pos.x, pos.z, 3)["dist"]) > 22.0:
		_no_shadows(node)
	return node


func _place_backdrop(far_pool: Array, near_pool: Array, rng: RandomNumberGenerator) -> void:
	var center := Vector3.ZERO
	for p in track.points:
		center += p
	center /= float(track.points.size())
	# a couple of pyramids on the horizon
	for entry: Dictionary in far_pool:
		if entry["key"] != "pyramid":
			continue
		for k in 3:
			var ang := -0.9 + k * 0.7
			var pos := center + Vector3(cos(ang) * 620.0, 0, sin(ang) * 620.0)
			pos.y = terrain_height(pos.x, pos.z) - 2.0
			var node := _spawn_prop(entry["scene"], pos, rng, 2.2 - k * 0.4, 2.4 - k * 0.4)
			if node != null:
				node.rotation.y = rng.randf_range(0, PI)
	if near_pool.is_empty():
		return
	for k in 18:
		var ang := rng.randf_range(-PI, PI)
		var dist := rng.randf_range(230.0, 440.0)
		var pos := center + Vector3(cos(ang) * dist, 0, sin(ang) * dist)
		if float(nearest_track(pos.x, pos.z, 2)["dist"]) < 40.0:
			continue
		pos.y = terrain_height(pos.x, pos.z) - 0.3
		var entry: Dictionary = near_pool[rng.randi_range(0, near_pool.size() - 1)]
		_spawn_prop(entry["scene"], pos, rng, 1.8 * float(entry["scale"]), 2.8 * float(entry["scale"]))


func _load_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	var out := {}
	var props: Variant = d.get("props", {})
	if typeof(props) == TYPE_DICTIONARY:
		for key: String in props:
			var entry: Variant = props[key]
			if typeof(entry) == TYPE_DICTIONARY:
				out[key] = entry
	return out


func _blockout_rock(variant: int) -> PackedScene:
	var root := Node3D.new()
	root.name = "BlockoutRock%d" % variant
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.6 + variant * 0.6
	sphere.height = 2.2 + variant * 0.8
	sphere.radial_segments = 8
	sphere.rings = 4
	mi.mesh = sphere
	mi.material_override = _flat_material(Color(0.68, 0.53, 0.36))
	mi.position.y = 1.0
	root.add_child(mi)
	mi.owner = root
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed
