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

void fragment() {
	float brush_value = u_factor * u_opacity * texture(TEXTURE, UV).r;
	
	vec2 src_pixel_size = 1.0 / vec2(textureSize(u_src_texture, 0));
	vec2 src_uv = get_src_uv(SCREEN_UV);
	vec2 offset = src_pixel_size;
	float src_nx = get_height(u_src_texture, src_uv - vec2(offset.x, 0.0));
	float src_px = get_height(u_src_texture, src_uv + vec2(offset.x, 0.0));
	float src_ny = get_height(u_src_texture, src_uv - vec2(0.0, offset.y));
	float src_py = get_height(u_src_texture, src_uv + vec2(0.0, offset.y));
	float src_h = get_height(u_src_texture, src_uv);
	float dst_h = (src_h + src_nx + src_px + src_ny + src_py) * 0.2;
	float h = mix(src_h, dst_h, brush_value);
	COLOR = encode_height_to_viewport(h);
}
