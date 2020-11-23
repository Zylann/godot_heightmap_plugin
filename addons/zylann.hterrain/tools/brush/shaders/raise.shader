shader_type canvas_item;
render_mode blend_disabled;

uniform float u_factor = 1.0;

float get_brush_value(vec2 np) {
	return clamp(1.0 - length(np), 0.0, 1.0);
}

void fragment() {
	vec2 np = SCREEN_UV * 2.0 - vec2(1.0);
	float v = get_brush_value(np);
	
	float src_h = texture(TEXTURE, UV).r;
	src_h += u_factor * v;
	COLOR = vec4(src_h, 0.0, 0.0, 0.0);
}
