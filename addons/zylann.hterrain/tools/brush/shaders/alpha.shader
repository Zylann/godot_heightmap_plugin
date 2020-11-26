shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_brush_texture;
uniform float u_factor = 1.0;
uniform float u_value = 1.0;

void fragment() {
	float brush_value = texture(u_brush_texture, SCREEN_UV).r;
	
	vec4 src = texture(TEXTURE, UV);
	COLOR = vec4(src.rgb, mix(src.a, u_value, u_factor * brush_value));
}
