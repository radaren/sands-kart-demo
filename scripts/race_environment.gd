extends Node3D
## Desert sky, sun with shadows, warm fog.

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.55, 0.88)
	sm.sky_horizon_color = Color(0.96, 0.84, 0.64)
	sm.ground_horizon_color = Color(0.9, 0.76, 0.55)
	sm.ground_bottom_color = Color(0.72, 0.56, 0.38)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.95, 0.84, 0.66)
	env.fog_density = 0.0012
	# The Compatibility renderer (Web build) has no HDR headroom: bright sky
	# ambient + sun clip the sand to white. Use gentler values there.
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	if compat:
		env.ambient_light_energy = 0.42
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.light_energy = 0.78 if compat else 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
