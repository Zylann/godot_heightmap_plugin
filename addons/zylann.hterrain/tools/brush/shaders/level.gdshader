shader_type canvas_item;
render_mode blend_disabled;

#include "res://addons/zylann.hterrain/shaders/include/heightmap.gdshaderinc"

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform float u_factor = 1.0;

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

float get_height(sampler2D heightmap, vec2 uv) {
	return sample_heightmap(heightmap, uv);
}

// TODO Could actually level to whatever height the brush was at the beginning of the stroke?

void fragment() {
	float brush_value = u_factor * u_opacity * texture(TEXTURE, UV).r;

	// The heightmap does not have mipmaps,
	// so we need to use an approximation of average.
	// This is not a very good one though...
	float dst_h = 0.0;
	vec2 uv_min = vec2(u_src_rect.xy);
	vec2 uv_max = vec2(u_src_rect.xy + u_src_rect.zw);
	for (int i = 0; i < 5; ++i) {
		for (int j = 0; j < 5; ++j) {
			float x = mix(uv_min.x, uv_max.x, float(i) / 4.0);
			float y = mix(uv_min.y, uv_max.y, float(j) / 4.0);
			float h = get_height(u_src_texture, vec2(x, y));
			dst_h += h;
		}
	}
	dst_h /= (5.0 * 5.0);
	
	// TODO I have no idea if this will check out
	float src_h = get_height(u_src_texture, get_src_uv(SCREEN_UV));
	float h = mix(src_h, dst_h, brush_value);
	COLOR = encode_height_to_viewport(h);
}
