shader_type canvas_item;
render_mode blend_disabled;

#include "res://addons/zylann.hterrain/shaders/include/heightmap.gdshaderinc"

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform vec4 u_splat = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D u_heightmap;
uniform float u_normal_min_y = 0.0;
uniform float u_normal_max_y = 1.0;
//uniform float u_normal_falloff = 0.0;

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

float get_height(sampler2D heightmap, vec2 uv) {
	return sample_heightmap(heightmap, uv);
}

vec3 get_normal(sampler2D heightmap, vec2 pos) {
	vec2 ps = vec2(1.0) / vec2(textureSize(heightmap, 0));
	float hnx = get_height(heightmap, pos + vec2(-ps.x, 0.0));
	float hpx = get_height(heightmap, pos + vec2(ps.x, 0.0));
	float hny = get_height(heightmap, pos + vec2(0.0, -ps.y));
	float hpy = get_height(heightmap, pos + vec2(0.0, ps.y));
	return normalize(vec3(hnx - hpx, 2.0, hpy - hny));
}

// Limits painting based on the slope, with a bit of falloff
float apply_slope_limit(float brush_value, vec3 normal, float normal_min_y, float normal_max_y) {
	float normal_falloff = 0.2;

	// If an edge is at min/max, make sure it won't be affected by falloff
	normal_min_y = normal_min_y <= 0.0 ? -2.0 : normal_min_y;
	normal_max_y = normal_max_y >= 1.0 ? 2.0 : normal_max_y;

	brush_value *= 1.0 - smoothstep(
		normal_max_y - normal_falloff,
		normal_max_y + normal_falloff, normal.y);

	brush_value *= smoothstep(
		normal_min_y - normal_falloff,
		normal_min_y + normal_falloff, normal.y);

	return brush_value;
}

void fragment() {
	float brush_value = u_opacity * texture(TEXTURE, UV).r;

	vec2 src_uv = get_src_uv(SCREEN_UV);
	vec3 normal = get_normal(u_heightmap, src_uv);
	brush_value = apply_slope_limit(brush_value, normal, u_normal_min_y, u_normal_max_y);

	vec4 src_splat = texture(u_src_texture, src_uv);
	vec4 s = mix(src_splat, u_splat, brush_value);
	s = s / (s.r + s.g + s.b + s.a);
	COLOR = s;
}
