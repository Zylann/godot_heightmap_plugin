shader_type canvas_item;
render_mode blend_disabled;

#include "res://addons/zylann.hterrain/shaders/include/heightmap_rgb8_encoding.gdshaderinc"

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform float u_factor = 1.0;

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

void fragment() {
	float brush_value = u_factor * u_opacity * texture(TEXTURE, UV).r;
	
	float src_h = decode_height_from_rgb8_unorm(texture(u_src_texture, get_src_uv(SCREEN_UV)).rgb);
	float h = src_h + brush_value;
	COLOR = vec4(encode_height_to_rgb8_unorm(h), 1.0);
}
