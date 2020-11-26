shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_brush_texture;
uniform float u_factor = 1.0;
uniform vec4 u_color = vec4(1.0);

void fragment() {
	float brush_value = texture(u_brush_texture, SCREEN_UV).r;
	
	vec4 src = texture(TEXTURE, UV);

	// Despite hints, albedo textures render darker.
	// Trying to undo sRGB does not work because of 8-bit precision loss
	// that would occur either in texture, or on the source image.
	// So it's not possible to use viewports to paint albedo...
	//src.rgb = pow(src.rgb, vec3(0.4545));

	vec4 col = vec4(mix(src.rgb, u_color.rgb, brush_value * u_factor), src.a);
	COLOR = col;
}
