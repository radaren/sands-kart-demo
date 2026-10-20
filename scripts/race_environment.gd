extends Node3D
## Desert sky, low warm sun with long shadows, cool fixed ambient, light fog.
## The whole project renders with the Compatibility renderer (same as the web
## build), so there is a single set of lighting values (W1).
## T8: fog no longer tints the sky (fog_sky_affect), warm sun vs cool ambient.

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.22, 0.47, 0.85)
	sm.sky_horizon_color = Color(0.86, 0.80, 0.70)
	sm.sky_curve = 0.12
	sm.ground_horizon_color = Color(0.86, 0.74, 0.56)
	sm.ground_bottom_color = Color(0.66, 0.52, 0.36)
	sm.sun_angle_max = 20.0
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.75)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.93, 0.84, 0.70)
	env.fog_density = 0.0007
	env.fog_sky_affect = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-35, -35, 0)
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140.0
	add_child(sun)
