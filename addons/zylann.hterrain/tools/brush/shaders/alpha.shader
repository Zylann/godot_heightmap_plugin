shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform float u_value = 1.0;

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

void fragment() {
	float brush_value = u_opacity * texture(TEXTURE, UV).r;
	
	vec4 src = texture(u_src_texture, get_src_uv(SCREEN_UV));
	COLOR = vec4(src.rgb, mix(src.a, u_value, brush_value));
}
