shader_type spatial;

// This shader uses a texture array with multiple splatmaps, allowing up to 16 textures.
// Only the 4 textures having highest blending weight are sampled.

// I had to remove `hint_albedo` from colormap because it makes sRGB conversion kick in,
// which snowballs to black when doing GPU painting on that texture...
uniform sampler2D u_terrain_colormap;
uniform sampler2D u_terrain_splatmap;
uniform sampler2D u_terrain_splatmap_1;
uniform sampler2D u_terrain_splatmap_2;
uniform sampler2D u_terrain_splatmap_3;

uniform sampler2DArray u_ground_albedo_bump_array : hint_albedo;

uniform float u_ground_uv_scale = 20.0;
uniform bool u_depth_blending = true;

// TODO Can't put this in a constant: https://github.com/godotengine/godot/issues/44145
//const int TEXTURE_COUNT = 16;


// Blends weights according to the bump of detail textures,
// so for example it allows to have sand fill the gaps between pebbles
vec4 get_depth_blended_weights(vec4 splat, vec4 bumps) {
	float dh = 0.2;

	vec4 h = bumps + splat;

	// TODO Keep improving multilayer blending, there are still some edge cases...
	// Mitigation: nullify layers with near-zero splat
	h *= smoothstep(0, 0.05, splat);

	vec4 d = h + dh;
	d.r -= max(h.g, max(h.b, h.a));
	d.g -= max(h.r, max(h.b, h.a));
	d.b -= max(h.g, max(h.r, h.a));
	d.a -= max(h.g, max(h.b, h.r));

	return clamp(d, 0, 1);
}

void get_splat_weights(vec2 uv, out vec4 out_high_indices, out vec4 out_high_weights) {
	vec4 ew0 = texture(u_terrain_splatmap, uv);
	vec4 ew1 = texture(u_terrain_splatmap_1, uv);
	vec4 ew2 = texture(u_terrain_splatmap_2, uv);
	vec4 ew3 = texture(u_terrain_splatmap_3, uv);
	
	float weights[16] = {
		ew0.r, ew0.g, ew0.b, ew0.a,
		ew1.r, ew1.g, ew1.b, ew1.a,
		ew2.r, ew2.g, ew2.b, ew2.a,
		ew3.r, ew3.g, ew3.b, ew3.a
	};
	
//		float weights_sum = 0.0;
//		for (int i = 0; i < 16; ++i) {
//			weights_sum += weights[i];
//		}
//		for (int i = 0; i < 16; ++i) {
//			weights_sum /= weights_sum;
//		}
//		weights_sum=1.1;
	
	// Now we have to pick the 4 highest weights and use them to blend textures.

	// Using arrays because Godot's shader version doesn't support dynamic indexing of vectors
	// TODO We should not need to initialize, but apparently we don't always find 4 weights
	int high_indices_array[4] = {0, 0, 0, 0};
	float high_weights_array[4] = {0.0, 0.0, 0.0, 0.0};
	int count = 0;
	// We know weights are supposed to be normalized.
	// That means the highest value of the pivot above which we can find 4 results
	// is 1.0 / 4.0. However that would mean exactly 4 textures have exactly that weight,
	// which is very unlikely. If we consider 1.0 / 5.0, we are a bit more likely to find
	// 4 results, and finding 5 results remains almost impossible.
	float pivot = /*weights_sum*/1.0 / 5.0;
	
	for (int i = 0; i < 16; ++i) {
		if (weights[i] > pivot) {
			high_weights_array[count] = weights[i];
			high_indices_array[count] = i;
			weights[i] = 0.0;
			++count;
		}
	}
	
	while (count < 4 && pivot > 0.0) {
		float max_weight = 0.0;
		int max_index = 0;
		
		for (int i = 0; i < 16; ++i) {
			if (/*weights[i] <= pivot && */weights[i] > max_weight) {
				max_weight = weights[i];
				max_index = i;
				weights[i] = 0.0;
			}
		}
		
		high_indices_array[count] = max_index;
		high_weights_array[count] = max_weight;
		++count;
		pivot = max_weight;
	}
			
	out_high_weights = vec4(
		high_weights_array[0], high_weights_array[1], 
		high_weights_array[2], high_weights_array[3]);
	
	out_high_indices = vec4(
		float(high_indices_array[0]), float(high_indices_array[1]),
		float(high_indices_array[2]), float(high_indices_array[3]));
	
	out_high_weights /= 
		out_high_weights.r + out_high_weights.g + out_high_weights.b + out_high_weights.a;
}

void vertex() {
	vec4 wpos = WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 cell_coords = wpos.xz;
	// Must add a half-offset so that we sample the center of pixels,
	// otherwise bilinear filtering of the textures will give us mixed results (#183)
	cell_coords += vec2(0.5);

	// Normalized UV
	UV = cell_coords / vec2(textureSize(u_terrain_splatmap, 0));
}

void fragment() {
	// These were moved from vertex to fragment,
	// so we can generate part of the global map with just one quad and we get full quality
	vec3 tint = texture(u_terrain_colormap, UV).rgb;
	vec4 splat = texture(u_terrain_splatmap, UV);

	vec4 high_indices;
	vec4 high_weights;
	get_splat_weights(UV, high_indices, high_weights);
	
	// Get bump at normal resolution so depth blending is accurate
	vec2 ground_uv = UV / u_ground_uv_scale;
	float b0 = texture(u_ground_albedo_bump_array, vec3(ground_uv, high_indices.x)).a;
	float b1 = texture(u_ground_albedo_bump_array, vec3(ground_uv, high_indices.y)).a;
	float b2 = texture(u_ground_albedo_bump_array, vec3(ground_uv, high_indices.z)).a;
	float b3 = texture(u_ground_albedo_bump_array, vec3(ground_uv, high_indices.w)).a;
	
	// Take the center of the highest mip as color, because we can't see details from far away.
	vec2 ndc_center = vec2(0.5, 0.5);
	vec3 a0 = textureLod(u_ground_albedo_bump_array, vec3(ndc_center, high_indices.x), 10.0).rgb;
	vec3 a1 = textureLod(u_ground_albedo_bump_array, vec3(ndc_center, high_indices.y), 10.0).rgb;
	vec3 a2 = textureLod(u_ground_albedo_bump_array, vec3(ndc_center, high_indices.z), 10.0).rgb;
	vec3 a3 = textureLod(u_ground_albedo_bump_array, vec3(ndc_center, high_indices.w), 10.0).rgb;
	
	vec3 col0 = a0 * tint;
	vec3 col1 = a1 * tint;
	vec3 col2 = a2 * tint;
	vec3 col3 = a3 * tint;

	vec4 w;
	// TODO An #ifdef macro would be nice! Or copy/paste everything in a different shader...
	if (u_depth_blending) {
		w = get_depth_blended_weights(high_weights, vec4(b0, b1, b2, b3));
	} else {
		w = high_weights;
	}

	float w_sum = (w.r + w.g + w.b + w.a);

	ALBEDO = (
		w.r * col0.rgb +
		w.g * col1.rgb +
		w.b * col2.rgb +
		w.a * col3.rgb) / w_sum;
}
