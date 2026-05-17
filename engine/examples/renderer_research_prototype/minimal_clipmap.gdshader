// Minimal clipmap shader — vertex-shader heightmap displacement.
//
// Per spec 15a section E: proves Texture2D heightmap sampling in
// vertex shader works in Godot 4.5. Production version (Phase 4)
// uses Texture2DRD + multi-ring + LOD morph; this is the minimum.

shader_type spatial;
render_mode unshaded;  // skip lighting for prototype — measure raw render cost

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform float height_scale = 100.0;
uniform float extent_m = 1000.0;
uniform vec3 albedo_low : source_color = vec3(0.3, 0.5, 0.2);
uniform vec3 albedo_high : source_color = vec3(0.9, 0.9, 0.95);

varying float v_height_t;
varying vec2 v_uv;

void vertex() {
	// Sample heightmap (R channel) — UV already 0..1 from MinimalClipmap.gd
	float h_norm = texture(heightmap, UV).r;
	VERTEX.y = h_norm * height_scale;
	v_height_t = h_norm;
	v_uv = UV;
}

void fragment() {
	// Simple height-based color: dark green low, white high
	vec3 base = mix(albedo_low, albedo_high, v_height_t);
	// Gentle UV-based stripe for visual interest (so we can see if
	// the grid renders correctly)
	float stripe = step(0.5, fract(v_uv.x * 50.0)) * 0.05;
	ALBEDO = base + vec3(stripe);
}
