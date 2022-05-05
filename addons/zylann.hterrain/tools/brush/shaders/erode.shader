shader_type canvas_item;

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform vec4 u_color = vec4(1.0);

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

// float get_noise(vec2 pos) {
// 	return fract(sin(dot(pos.xy ,vec2(12.9898,78.233))) * 43758.5453);
// }

float erode(sampler2D heightmap, vec2 uv, vec2 pixel_size, float weight) {
	float r = 3.0;
	
	// Divide so the shader stays neighbor dependent 1 pixel across.
	// For this to work, filtering must be enabled.
	vec2 eps = pixel_size / (0.99 * r);
	
	float h = texture(heightmap, uv).r;
	float eh = h;
	//float dh = h;
	
	// Morphology with circular structuring element
	for (float y = -r; y <= r; ++y) {
		for (float x = -r; x <= r; ++x) {
			
			vec2 p = vec2(x, y);
			float nh = texture(heightmap, uv + p * eps).r;
			
			float s = max(length(p) - r, 0);
			eh = min(eh, nh + s);

			//s = min(r - length(p), 0);
			//dh = max(dh, nh + s);
		}
	}
	
	eh = mix(h, eh, weight);
	//dh = mix(h, dh, u_weight);
	
	float ph = eh;//mix(eh, dh, u_dilation);

	return ph;
}

void fragment() {
	float brush_value = u_opacity * texture(TEXTURE, UV).r;
	vec2 src_pixel_size = 1.0 / vec2(textureSize(u_src_texture, 0));
	float ph = erode(u_src_texture, get_src_uv(SCREEN_UV), src_pixel_size, brush_value);
	//ph += brush_value * 0.35;
	COLOR = vec4(ph, ph, ph, 1.0);
}
