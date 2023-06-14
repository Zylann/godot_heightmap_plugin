shader_type canvas_item;
render_mode blend_disabled;

#include "res://addons/zylann.hterrain/shaders/include/heightmap.gdshaderinc"

//uniform sampler2D u_screen_texture : hint_screen_texture;
uniform sampler2D u_previous_pass;

vec4 pack_normal(vec3 n) {
	return vec4((0.5 * (n + 1.0)).xzy, 1.0);
}

float get_height(sampler2D tex, vec2 uv) {
	return sample_height_from_viewport(tex, uv);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ps = SCREEN_PIXEL_SIZE;
	float left = get_height(u_previous_pass, uv + vec2(-ps.x, 0));
	float right = get_height(u_previous_pass, uv + vec2(ps.x, 0));
	float back = get_height(u_previous_pass, uv + vec2(0, -ps.y));
	float fore = get_height(u_previous_pass, uv + vec2(0, ps.y));
	vec3 n = normalize(vec3(left - right, 2.0, fore - back));
	COLOR = pack_normal(n);
}

