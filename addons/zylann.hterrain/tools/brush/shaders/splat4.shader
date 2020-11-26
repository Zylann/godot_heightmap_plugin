shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_brush_texture;
uniform float u_factor = 1.0;
uniform vec4 u_splat = vec4(1.0, 0.0, 0.0, 0.0);

void fragment() {
	float brush_value = texture(u_brush_texture, SCREEN_UV).r;
	
	vec4 src = texture(TEXTURE, UV);
	vec4 s = mix(src, u_splat, u_factor * brush_value);
	s = s / (s.r + s.g + s.b + s.a);
	COLOR = s;
}
