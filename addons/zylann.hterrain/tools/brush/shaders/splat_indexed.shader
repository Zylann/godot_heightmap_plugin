shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform int u_texture_index;
uniform int u_mode; // 0: output index, 1: output weight
uniform sampler2D u_index_map;
uniform sampler2D u_weight_map;

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

void fragment() {
	float brush_value = u_opacity * texture(TEXTURE, UV).r;
	
	vec2 src_uv = get_src_uv(SCREEN_UV);
	vec4 iv = texture(u_index_map, src_uv);
	vec4 wv = texture(u_weight_map, src_uv);

	float i[3] = {iv.r, iv.g, iv.b};
	float w[3] = {wv.r, wv.g, wv.b};
	
	if (brush_value > 0.0) {
		float texture_index_f = float(u_texture_index) / 255.0;
		int ci = u_texture_index % 3;

		float cm[3] = {-1.0, -1.0, -1.0};
		cm[ci] = 1.0;

		// Decompress third weight to make computations easier
		w[2] = 1.0 - w[0] - w[1];

		if (abs(i[ci] - texture_index_f) > 0.001) {
			// Pixel does not have our texture index,
			// transfer its weight to other components first
			if (w[ci] > brush_value) {
				w[0] -= cm[0] * brush_value;
				w[1] -= cm[1] * brush_value;
				w[2] -= cm[2] * brush_value;

			} else if (w[ci] >= 0.f) {
				w[ci] = 0.f;
				i[ci] = texture_index_f;
			}

		} else {
			// Pixel has our texture index, increase its weight
			if (w[ci] + brush_value < 1.f) {
				w[0] += cm[0] * brush_value;
				w[1] += cm[1] * brush_value;
				w[2] += cm[2] * brush_value;

			} else {
				// Pixel weight is full, we can set all components to the same index.
				// Need to nullify other weights because they would otherwise never reach
				// zero due to normalization
				w[0] = 0.0;
				w[1] = 0.0;
				w[2] = 0.0;
				
				w[ci] = 1.0;

				i[0] = texture_index_f;
				i[1] = texture_index_f;
				i[2] = texture_index_f;
			}
		}

		w[0] = clamp(w[0], 0.0, 1.0);
		w[1] = clamp(w[1], 0.0, 1.0);
		w[2] = clamp(w[2], 0.0, 1.0);

		// Renormalize
		float sum = w[0] + w[1] + w[2];
		w[0] /= sum;
		w[1] /= sum;
		w[2] /= sum;
	}

	if (u_mode == 0) {
		COLOR = vec4(i[0], i[1], i[2], 1.0);
	} else {
		COLOR = vec4(w[0], w[1], w[2], 1.0);
	}
}
