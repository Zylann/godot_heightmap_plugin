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

void fragment() {
	float brush_value = u_factor * u_opacity * texture(TEXTURE, UV).r;
	
	float src_h = sample_heightmap(u_src_texture, get_src_uv(SCREEN_UV));
	float h = src_h + brush_value;
	COLOR = encode_height_to_viewport(h);
}
