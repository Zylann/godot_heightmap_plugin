shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_brush_texture;
uniform float u_factor = 1.0;
uniform vec4 u_texture_rect;

// TODO Could actually level to whatever height the brush was at the beginning of the stroke?

void fragment() {
	float brush_value = texture(u_brush_texture, SCREEN_UV).r;

	// The heightmap does not have mipmaps,
	// so we need to use an approximation of average.
	// This is not a very good one though...
	float dst_h = 0.0;
	vec2 uv_min = vec2(u_texture_rect.xy);
	vec2 uv_max = vec2(u_texture_rect.xy + u_texture_rect.zw);
	for (int i = 0; i < 5; ++i) {
		for (int j = 0; j < 5; ++j) {
			float x = mix(uv_min.x, uv_max.x, float(i) / 4.0);
			float y = mix(uv_min.y, uv_max.y, float(j) / 4.0);
			float h = texture(TEXTURE, vec2(x, y)).r;
			dst_h += h;
		}
	}
	dst_h /= (5.0 * 5.0);
	
	// TODO I have no idea if this will check out
	float src_h = texture(TEXTURE, UV).r;
	float h = mix(src_h, dst_h, u_factor * brush_value);
	COLOR = vec4(h, 0.0, 0.0, 1.0);
}
