// MagicLomix Development
// Authors:
//   pariszhou:
//     1. Keep fixed-R surface sampling, Separate defaults of 0/1/1, white packed defaults, MR independent AO and indirect-only AO.

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// MagicLomix Begin
// Opaque standard PBR. Separate maps read R; empty M/R/AO slots sample 0/1/1.
// Merged formats: MRO (R=M, G=R, B=AO), ORM (R=AO, G=R, B=M), MR (G=R, B=M).
// MR reads the separate AO map (R), defaulting to white. All surface multipliers default to 1.
// MagicLomix End

// MagicLomix Begin
const int TEXTURE_MODE_SEPARATE = 1;
const int PACKED_FORMAT_MRO = 0;
const int PACKED_FORMAT_MR = 2;
// MagicLomix End

group_uniforms UV;
uniform vec2 uv_tiling = vec2(1.0);   // 平铺次数
uniform vec2 uv_offset = vec2(0.0);   // 偏移

// MagicLomix Begin
group_uniforms Albedo;
// MagicLomix End
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec4 albedo_color : source_color = vec4(1.0);   // 叠加色 / Tint

// MagicLomix Begin
group_uniforms Albedo.Adjust;
// MagicLomix End
uniform float albedo_brightness : hint_range(0.0, 4.0) = 1.0;   // 亮度 (乘): 1=不变
uniform float albedo_contrast : hint_range(0.0, 4.0) = 1.0;     // 对比度: 1=不变
uniform float albedo_saturation : hint_range(0.0, 4.0) = 1.0;   // 饱和度: 0=灰度, 1=不变

group_uniforms Normal;
uniform sampler2D normal_tex : hint_normal;
uniform float normal_scale : hint_range(0.0, 4.0) = 1.0;
// MagicLomix Begin
uniform bool flip_normal_y = false;   // Unreal Engine/DirectX 法线(Y反向)勾选此项转为 Godot(OpenGL) 约定
// MagicLomix End

group_uniforms Surface;
// MagicLomix Begin
uniform int texture_mode : hint_enum("Merged", "Separate") = 1;
uniform float metallic_mul : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float roughness_mul : hint_range(0.0, 4.0, 0.01) = 1.0;
uniform float ao_mul : hint_range(0.0, 4.0, 0.01) = 1.0;
// MagicLomix End

// MagicLomix Begin
group_uniforms Surface.Merged;
uniform int packed_format : hint_enum("MRO", "ORM", "MR") = 0;
uniform sampler2D packed_tex : hint_default_white;

group_uniforms Surface.Separate;
uniform sampler2D metallic_tex : hint_default_black;
uniform sampler2D roughness_tex : hint_default_white;
uniform sampler2D ao_tex : hint_default_white;

// MagicLomix End

// MagicLomix Begin
// 采样切线空间法线(0~1), 可选翻转 Y 以兼容 Unreal Engine/DirectX 约定
// MagicLomix End
vec3 sample_normal(sampler2D tex, vec2 uv) {
	vec3 n = texture(tex, uv).rgb;
	if (flip_normal_y) {
		n.g = 1.0 - n.g;
	}
	return n;
}

// 基础色调节: 亮度 -> 对比度 -> 饱和度
vec3 adjust_color(vec3 c, float brightness, float contrast, float saturation) {
	c = c * brightness;                          // 亮度: 直接乘
	c = (c - 0.5) * contrast + 0.5;              // 对比度: 绕中灰 0.5 缩放
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));  // Rec.709 亮度
	c = mix(vec3(luma), c, saturation);          // 饱和度: 在灰度与原色间插值
	return max(c, vec3(0.0));                     // 防止负值
}

void fragment() {
	vec2 uv = UV * uv_tiling + uv_offset;

	// MagicLomix Begin
	vec3 base_rgb = texture(albedo_tex, uv).rgb * albedo_color.rgb;
	// MagicLomix End
	ALBEDO = adjust_color(base_rgb, albedo_brightness, albedo_contrast, albedo_saturation);

	// MagicLomix Begin
	float m;
	float r;
	float o;
	if (texture_mode == TEXTURE_MODE_SEPARATE) {
		m = texture(metallic_tex, uv).r;
		r = texture(roughness_tex, uv).r;
		o = texture(ao_tex, uv).r;
	} else {
		vec3 packed = texture(packed_tex, uv).rgb;
		m = packed_format == PACKED_FORMAT_MRO ? packed.r : packed.b;
		r = packed.g;
		o = packed_format == PACKED_FORMAT_MR ? texture(ao_tex, uv).r : (packed_format == PACKED_FORMAT_MRO ? packed.b : packed.r);
	}
	METALLIC = clamp(m * metallic_mul, 0.0, 1.0);
	ROUGHNESS = clamp(r * roughness_mul, 0.0, 1.0);
	AO = clamp(o * ao_mul, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.0; // AO affects indirect lighting only.
	// MagicLomix End

	NORMAL_MAP = sample_normal(normal_tex, uv);
	NORMAL_MAP_DEPTH = normal_scale;
}
