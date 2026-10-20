shader_type canvas_item;
// Cloud / ink hit overlay (I7): dark ink blots with ragged edges that leave the
// centre of the screen readable. amount 0..1 fades it in/out; seed varies blots.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform vec2 aspect = vec2(1.777, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 p = (UV - 0.5) * aspect;
	float r = length(p);
	float n = fbm(UV * aspect * 3.0 + vec2(seed * 7.3, seed * 3.1) + TIME * 0.05);
	// blots grow from the edges; centre radius ~0.22 stays clear
	float edge = smoothstep(0.2, 0.75, r + (n - 0.5) * 0.55);
	float blot = smoothstep(0.42, 0.5, edge * amount + n * 0.25 * amount);
	float speck = step(0.83, vnoise(UV * aspect * 26.0 + seed)) * smoothstep(0.25, 0.5, r) * amount;
	float a = clamp(max(blot, speck * 0.8), 0.0, 1.0) * smoothstep(0.0, 0.15, amount);
	COLOR = vec4(0.06, 0.04, 0.1, a * 0.96);
}
