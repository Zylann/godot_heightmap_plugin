shader_type canvas_item;
render_mode blend_disabled;

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
	
	vec2 src_pixel_size = 1.0 / vec2(textureSize(u_src_texture, 0));
	vec2 src_uv = get_src_uv(SCREEN_UV);
	vec2 offset = src_pixel_size;
	float src_nx = texture(u_src_texture, src_uv - vec2(offset.x, 0.0)).r;
	float src_px = texture(u_src_texture, src_uv + vec2(offset.x, 0.0)).r;
	float src_ny = texture(u_src_texture, src_uv - vec2(0.0, offset.y)).r;
	float src_py = texture(u_src_texture, src_uv + vec2(0.0, offset.y)).r;
	float src_h = texture(u_src_texture, src_uv).r;
	float dst_h = (src_h + src_nx + src_px + src_ny + src_py) * 0.2;
	float h = mix(src_h, dst_h, brush_value);
	COLOR = vec4(h, 0.0, 0.0, 1.0);
}
