shader_type spatial;

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_normalmap;
uniform sampler2D u_terrain_colormap : hint_albedo;
uniform sampler2D u_terrain_splat_index_map;
uniform sampler2D u_terrain_splat_weight_map;
uniform sampler2D u_terrain_globalmap : hint_albedo;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

uniform sampler2DArray u_ground_albedo_bump_array : hint_albedo;
uniform sampler2DArray u_ground_normal_roughness_array;

// TODO Have UV scales for each texture in an array?
uniform float u_ground_uv_scale;
uniform float u_globalmap_blend_start;
uniform float u_globalmap_blend_distance;
uniform bool u_depth_blending = true;

varying float v_hole;
varying vec3 v_tint;
varying vec2 v_ground_uv;
varying float v_distance_to_camera;


vec3 unpack_normal(vec4 rgba) {
	return rgba.xzy * 2.0 - vec3(1.0);
}

vec3 get_depth_blended_weights(vec3 splat, vec3 bumps) {
	float dh = 0.2;

	vec3 h = bumps + splat;

	// TODO Keep improving multilayer blending, there are still some edge cases...
	// Mitigation: nullify layers with near-zero splat
	h *= smoothstep(0, 0.05, splat);

	vec3 d = h + dh;
	d.r -= max(h.g, h.b);
	d.g -= max(h.r, h.b);
	d.b -= max(h.g, h.r);

	vec3 w = clamp(d, 0, 1);
	// Had to normalize, since this approach does not preserve components summing to 1
	return w / (w.x + w.y + w.z);
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
	v_ground_uv = base_ground_uv.xz / u_ground_uv_scale;

	// Putting this in vertex saves 2 fetches from the fragment shader,
	// which is good for performance at a negligible quality cost,
	// provided that geometry is a regular grid that decimates with LOD.
	// (downside is LOD will also decimate tint and splat, but it's not bad overall)
	vec4 tint = texture(u_terrain_colormap, UV);
	v_hole = tint.a;
	v_tint = tint.rgb;

	// Need to use u_terrain_normal_basis to handle scaling.
	// For some reason I also had to invert Z when sampling terrain normals... not sure why
	NORMAL = u_terrain_normal_basis * (unpack_normal(texture(u_terrain_normalmap, UV)) * vec3(1,1,-1));

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
	vec3 normal = terrain_normal_world;

	float globalmap_factor = 
		clamp((v_distance_to_camera - u_globalmap_blend_start) * u_globalmap_blend_distance, 0.0, 1.0);
	globalmap_factor *= globalmap_factor; // slower start, faster transition but far away
	vec3 global_albedo = texture(u_terrain_globalmap, UV).rgb;
	ALBEDO = global_albedo;

	// Doing this branch allows to spare a bunch of texture fetches for distant pixels.
	// Eventually, there could be a split between near and far shaders in the future,
	// if relevant on high-end GPUs
	if (globalmap_factor < 1.0) {
		vec4 tex_splat_indexes = texture(u_terrain_splat_index_map, UV);
		vec4 tex_splat_weights = texture(u_terrain_splat_weight_map, UV);
		// TODO Can't use texelFetch!
		// https://github.com/godotengine/godot/issues/31732
		
		vec3 splat_indexes = tex_splat_indexes.rgb * 255.0;
		vec3 splat_weights = vec3(
			tex_splat_weights.r, 
			tex_splat_weights.g,
			1.0 - tex_splat_weights.r - tex_splat_weights.g
		);

		vec4 ab0 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv, splat_indexes.x));
		vec4 ab1 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv, splat_indexes.y));
		vec4 ab2 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv, splat_indexes.z));

		vec4 nr0 = texture(u_ground_normal_roughness_array, vec3(v_ground_uv, splat_indexes.x));
		vec4 nr1 = texture(u_ground_normal_roughness_array, vec3(v_ground_uv, splat_indexes.y));
		vec4 nr2 = texture(u_ground_normal_roughness_array, vec3(v_ground_uv, splat_indexes.z));

		// TODO An #ifdef macro would be nice! Or copy/paste everything in a different shader...
		if (u_depth_blending) {
			splat_weights = get_depth_blended_weights(splat_weights, vec3(ab0.a, ab1.a, ab2.a));
		}

		ALBEDO = v_tint * (
			  ab0.rgb * splat_weights.x 
			+ ab1.rgb * splat_weights.y
			+ ab2.rgb * splat_weights.z
		);
			
		ROUGHNESS = 
			  nr0.a * splat_weights.x
			+ nr1.a * splat_weights.y
			+ nr2.a * splat_weights.z;

		vec3 normal0 = unpack_normal(nr0);
		vec3 normal1 = unpack_normal(nr1);
		vec3 normal2 = unpack_normal(nr2);
		
		vec3 ground_normal = 
			  normal0 * splat_weights.x
			+ normal1 * splat_weights.y
			+ normal2 * splat_weights.z;

		// Combine terrain normals with detail normals (not sure if correct but looks ok)
		normal = normalize(vec3(
			terrain_normal_world.x + ground_normal.x,
			terrain_normal_world.y,
			terrain_normal_world.z + ground_normal.z));

		normal = mix(normal, terrain_normal_world, globalmap_factor);

		ALBEDO = mix(ALBEDO, global_albedo, globalmap_factor);
		//ALBEDO = vec3(splat_weight0, splat_weight1, splat_weight2);
		ROUGHNESS = mix(ROUGHNESS, 1.0, globalmap_factor);
	}

	NORMAL = (INV_CAMERA_MATRIX * (vec4(normal, 0.0))).xyz;
}
