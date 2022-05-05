shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform float u_flatten_value;

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

void fragment() {
	float brush_value = u_opacity * texture(TEXTURE, UV).r;
	
	float src_h = texture(u_src_texture, get_src_uv(SCREEN_UV)).r;
	float h = mix(src_h, u_flatten_value, brush_value);
	COLOR = vec4(h, 0.0, 0.0, 1.0);
}
