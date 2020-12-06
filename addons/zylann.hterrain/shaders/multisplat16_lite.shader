shader_type spatial;

// WIP
// This shader uses a texture array with multiple splatmaps, allowing up to 16 textures.
// Only the 4 textures having highest blending weight are sampled.

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_normalmap;
// I had to remove `hint_albedo` from colormap because it makes sRGB conversion kick in,
// which snowballs to black when doing GPU painting on that texture...
uniform sampler2D u_terrain_colormap;
uniform sampler2D u_terrain_splatmap;
uniform sampler2D u_terrain_splatmap_1;
uniform sampler2D u_terrain_splatmap_2;
uniform sampler2D u_terrain_splatmap_3;
uniform sampler2D u_terrain_globalmap : hint_albedo;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

uniform sampler2DArray u_ground_albedo_bump_array : hint_albedo;

uniform float u_ground_uv_scale = 20.0;
uniform bool u_depth_blending = true;
uniform float u_globalmap_blend_start;
uniform float u_globalmap_blend_distance;

varying float v_hole;
varying vec3 v_tint;
varying vec2 v_terrain_uv;
varying vec3 v_ground_uv;
varying float v_distance_to_camera;

// TODO Can't put this in a constant: https://github.com/godotengine/godot/issues/44145
//const int TEXTURE_COUNT = 16;


vec3 unpack_normal(vec4 rgba) {
	vec3 n = rgba.xzy * 2.0 - vec3(1.0);
	// Had to negate Z because it comes from Y in the normal map,
	// and OpenGL-style normal maps are Y-up.
	n.z *= -1.0;
	return n;
}

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

vec3 get_triplanar_blend(vec3 world_normal) {
	vec3 blending = abs(world_normal);
	blending = normalize(max(blending, vec3(0.00001))); // Force weights to sum to 1.0
	float b = blending.x + blending.y + blending.z;
	return blending / vec3(b, b, b);
}

vec4 texture_triplanar(sampler2D tex, vec3 world_pos, vec3 blend) {
	vec4 xaxis = texture(tex, world_pos.yz);
	vec4 yaxis = texture(tex, world_pos.xz);
	vec4 zaxis = texture(tex, world_pos.xy);
	// blend the results of the 3 planar projections.
	return xaxis * blend.x + yaxis * blend.y + zaxis * blend.z;
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
	vec2 cell_coords = (u_terrain_inverse_transform * wpos).xz;
	// Must add a half-offset so that we sample the center of pixels,
	// otherwise bilinear filtering of the textures will give us mixed results (#183)
	cell_coords += vec2(0.5);

	// Normalized UV
	UV = cell_coords / vec2(textureSize(u_terrain_heightmap, 0));

	// Height displacement
	float h = texture(u_terrain_heightmap, UV).r;
	VERTEX.y = h;
	wpos.y = h;

	vec3 base_ground_uv = vec3(cell_coords.x, h * WORLD_MATRIX[1][1], cell_coords.y);
	v_ground_uv = base_ground_uv / u_ground_uv_scale;

	// Putting this in vertex saves a fetch from the fragment shader,
	// which is good for performance at a negligible quality cost,
	// provided that geometry is a regular grid that decimates with LOD.
	// (downside is LOD will also decimate it, but it's not bad overall)
	vec4 tint = texture(u_terrain_colormap, UV);
	v_hole = tint.a;
	v_tint = tint.rgb;
	
	// Need to use u_terrain_normal_basis to handle scaling.
	// For some reason I also had to invert Z when sampling terrain normals... not sure why
	NORMAL = u_terrain_normal_basis * unpack_normal(texture(u_terrain_normalmap, UV));

	v_distance_to_camera = distance(wpos.xyz, CAMERA_MATRIX[3].xyz);
}

void fragment() {
	if (v_hole < 0.5) {
		// TODO Add option to use vertex discarding instead, using NaNs
		discard;
	}

	vec3 terrain_normal_world = 
		u_terrain_normal_basis * (unpack_normal(texture(u_terrain_normalmap, UV)) * vec3(1,1,-1));
	terrain_normal_world = normalize(terrain_normal_world);

	float globalmap_factor = clamp((v_distance_to_camera - u_globalmap_blend_start)
		 * u_globalmap_blend_distance, 0.0, 1.0);
	globalmap_factor *= globalmap_factor; // slower start, faster transition but far away
	vec3 global_albedo = texture(u_terrain_globalmap, UV).rgb;
	ALBEDO = global_albedo;

	// Doing this branch allows to spare a bunch of texture fetches for distant pixels.
	// Eventually, there could be a split between near and far shaders in the future,
	// if relevant on high-end GPUs
	if (globalmap_factor < 1.0) {
		vec4 high_indices;
		vec4 high_weights;
		get_splat_weights(UV, high_indices, high_weights);
		
		vec4 ab0 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv.xz, high_indices.x));
		vec4 ab1 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv.xz, high_indices.y));
		vec4 ab2 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv.xz, high_indices.z));
		vec4 ab3 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv.xz, high_indices.w));
		
		vec3 col0 = ab0.rgb * v_tint;
		vec3 col1 = ab1.rgb * v_tint;
		vec3 col2 = ab2.rgb * v_tint;
		vec3 col3 = ab3.rgb * v_tint;

		vec4 w;
		// TODO An #ifdef macro would be nice! Or copy/paste everything in a different shader...
		if (u_depth_blending) {
			w = get_depth_blended_weights(high_weights, vec4(ab0.a, ab1.a, ab2.a, ab3.a));
		} else {
			w = high_weights;
		}

		float w_sum = (w.r + w.g + w.b + w.a);

		ALBEDO = (
			w.r * col0.rgb +
			w.g * col1.rgb +
			w.b * col2.rgb +
			w.a * col3.rgb) / w_sum;

		ALBEDO = mix(ALBEDO, global_albedo, globalmap_factor);
		ROUGHNESS = mix(ROUGHNESS, 1.0, globalmap_factor);

//		if(count < 3) {
//			ALBEDO = vec3(1.0, 0.0, 0.0);
//		}
		// Show splatmap weights
		//ALBEDO = w.rgb;
	}
	// Highlight all pixels undergoing no splatmap at all
//	else {
//		ALBEDO = vec3(1.0, 0.0, 0.0);
//	}

	NORMAL = (INV_CAMERA_MATRIX * (vec4(terrain_normal_world, 0.0))).xyz;
}
