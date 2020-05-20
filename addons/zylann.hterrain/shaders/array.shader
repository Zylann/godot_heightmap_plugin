shader_type spatial;

// This is the reference shader of the plugin, and has the most features.
// it should be preferred for high-end graphics cards.
// For less features but lower-end targets, see the lite version.

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_normalmap;
uniform sampler2D u_terrain_colormap : hint_albedo;
uniform sampler2D u_terrain_indexed_splatmap;
uniform sampler2D u_terrain_globalmap : hint_albedo;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

uniform sampler2DArray u_ground_albedo_bump_array;

uniform float u_ground_uv_scale;

uniform float u_globalmap_blend_start;
uniform float u_globalmap_blend_distance;

varying float v_hole;
varying vec3 v_tint;
varying float v_splat_weight;
varying flat vec2 v_splat_indexes;
varying vec2 v_ground_uv;
varying float v_distance_to_camera;


vec3 unpack_normal(vec4 rgba) {
	return rgba.xzy * 2.0 - vec3(1.0);
}

void vertex() {
	vec4 wpos = WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 cell_coords = (u_terrain_inverse_transform * wpos).xz;

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
	// TODO Considering some blends are illegal, shouldn't this be in fragment?
	vec4 iw = texture(u_terrain_indexed_splatmap, UV);
	v_splat_indexes = vec2(iw.r, iw.g) * 255.0;
	v_splat_weight = iw.b;

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
		// TODO Sampling a texture array with a varying index is something Godot needs to support!
		vec4 ab0 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv, v_splat_indexes.x));
		vec4 ab1 = texture(u_ground_albedo_bump_array, vec3(v_ground_uv, v_splat_indexes.y));

		vec3 col0 = ab0.rgb * v_tint;
		vec3 col1 = ab1.rgb * v_tint;

		ALBEDO = mix(col0, col1, v_splat_weight);

		ROUGHNESS = 0.0;

		vec3 ground_normal = vec3(0, 1, 0);

		// Combine terrain normals with detail normals (not sure if correct but looks ok)
		normal = normalize(vec3(
			terrain_normal_world.x + ground_normal.x,
			terrain_normal_world.y,
			terrain_normal_world.z + ground_normal.z));

		normal = mix(normal, terrain_normal_world, globalmap_factor);

		ALBEDO = mix(ALBEDO, global_albedo, globalmap_factor);
		ROUGHNESS = mix(ROUGHNESS, 1.0, globalmap_factor);
	}

	NORMAL = (INV_CAMERA_MATRIX * (vec4(normal, 0.0))).xyz;
}
