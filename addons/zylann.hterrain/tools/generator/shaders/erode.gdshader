shader_type canvas_item;
render_mode blend_disabled;

#include "res://addons/zylann.hterrain/shaders/include/heightmap.gdshaderinc"

uniform vec2 u_slope_up = vec2(0, 0);
uniform float u_slope_factor = 1.0;
uniform bool u_slope_invert = false;
uniform float u_weight = 0.5;
uniform float u_dilation = 0.0;
//uniform sampler2D u_screen_texture : hint_screen_texture;
uniform sampler2D u_previous_pass;

float get_height(sampler2D tex, vec2 uv) {
	return sample_height_from_viewport(tex, uv);
}

void fragment() {
	float r = 3.0;
	
	// Divide so the shader stays neighbor dependent 1 pixel across.
	// For this to work, filtering must be enabled.
	vec2 eps = SCREEN_PIXEL_SIZE / (0.99 * r);
	
	vec2 uv = SCREEN_UV;
	float h = get_height(u_previous_pass, uv);
	float eh = h;
	float dh = h;
	
	// Morphology with circular structuring element
	for (float y = -r; y <= r; ++y) {
		for (float x = -r; x <= r; ++x) {
			
			vec2 p = vec2(float(x), float(y));
			float nh = get_height(u_previous_pass, uv + p * eps);
			
			float s = max(length(p) - r, 0);
			eh = min(eh, nh + s);

			s = min(r - length(p), 0);
			dh = max(dh, nh + s);
		}
	}
	
	eh = mix(h, eh, u_weight);
	dh = mix(h, dh, u_weight);
	
	float ph = mix(eh, dh, u_dilation);
	
	if (u_slope_factor > 0.0) {
		vec2 ps = SCREEN_PIXEL_SIZE;
		
		float left = get_height(u_previous_pass, uv + vec2(-ps.x, 0.0));
		float right = get_height(u_previous_pass, uv + vec2(ps.x, 0.0));
		float top = get_height(u_previous_pass, uv + vec2(0.0, ps.y));
		float bottom = get_height(u_previous_pass, uv + vec2(0.0, -ps.y));
		
		vec3 normal = normalize(vec3(left - right, ps.x + ps.y, bottom - top));
		vec3 up = normalize(vec3(u_slope_up.x, 1.0, u_slope_up.y));
		
		float f = max(dot(normal, up), 0);
		if (u_slope_invert) {
			f = 1.0 - f;
		}
		
		ph = mix(h, ph, mix(1.0, f, u_slope_factor));
		//COLOR = vec4(f, f, f, 1.0);
	}
	
	//COLOR = vec4(0.5 * normal + 0.5, 1.0);
	
	//eh = 0.5 * (eh + texture(SCREEN_TEXTURE, uv + mp * ps * k).r);
	//eh = mix(h, eh, (1.0 - h) / r);
	
	COLOR = encode_height_to_viewport(ph);
}
