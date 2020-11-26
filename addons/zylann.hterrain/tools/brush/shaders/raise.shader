shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_brush_texture;
uniform float u_factor = 1.0;

void fragment() {
	float brush_value = texture(u_brush_texture, SCREEN_UV).r;
	
	float src_h = texture(TEXTURE, UV).r;
	float h = src_h + u_factor * brush_value;
	COLOR = vec4(h, 0.0, 0.0, 1.0);
}
