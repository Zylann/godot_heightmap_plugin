shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform vec4 u_color = vec4(1.0);

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

void fragment() {
	float brush_value = u_opacity * texture(TEXTURE, UV).r;
	
	vec4 src = texture(u_src_texture, get_src_uv(SCREEN_UV));

	// Despite hints, albedo textures render darker.
	// Trying to undo sRGB does not work because of 8-bit precision loss
	// that would occur either in texture, or on the source image.
	// So it's not possible to use viewports to paint albedo...
	//src.rgb = pow(src.rgb, vec3(0.4545));

	vec4 col = vec4(mix(src.rgb, u_color.rgb, brush_value), src.a);
	COLOR = col;
}
