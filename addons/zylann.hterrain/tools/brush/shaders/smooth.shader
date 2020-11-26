shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_brush_texture;
uniform float u_factor = 1.0;

void fragment() {
	float brush_value = texture(u_brush_texture, SCREEN_UV).r;
	
	vec2 offset = TEXTURE_PIXEL_SIZE;
	float src_nx = texture(TEXTURE, UV - vec2(offset.x, 0.0)).r;
	float src_px = texture(TEXTURE, UV + vec2(offset.x, 0.0)).r;
	float src_ny = texture(TEXTURE, UV - vec2(0.0, offset.y)).r;
	float src_py = texture(TEXTURE, UV + vec2(0.0, offset.y)).r;
	float src_h = texture(TEXTURE, UV).r;
	float dst_h = (src_h + src_nx + src_px + src_ny + src_py) * 0.2;
	float h = mix(src_h, dst_h, u_factor * brush_value);
	COLOR = vec4(h, 0.0, 0.0, 1.0);
}
