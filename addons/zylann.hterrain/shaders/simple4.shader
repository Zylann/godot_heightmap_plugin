shader_type spatial;

// This is the reference shader of the plugin, and has the most features.
// it should be preferred for high-end graphics cards.
// For less features but lower-end targets, see the lite version.

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_normalmap;
uniform sampler2D u_terrain_colormap : hint_albedo;
uniform sampler2D u_terrain_splatmap;
uniform sampler2D u_terrain_globalmap : hint_albedo;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

// the reason bump is preferred with albedo is, roughness looks better with normal maps.
// If we want no normal mapping, roughness would only give flat mirror surfaces,
// while bump still allows to do depth-blending for free.
uniform sampler2D u_ground_albedo_bump_0 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_1 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_2 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_3 : hint_albedo;

uniform sampler2D u_ground_normal_roughness_0;
uniform sampler2D u_ground_normal_roughness_1;
uniform sampler2D u_ground_normal_roughness_2;
uniform sampler2D u_ground_normal_roughness_3;

// Had to give this uniform a suffix, because it's declared as a simple float
// in other shaders, and its type cannot be inferred by the plugin.
// See https://github.com/godotengine/godot/issues/24488
uniform vec4 u_ground_uv_scale_per_texture = vec4(20.0, 20.0, 20.0, 20.0);

uniform bool u_depth_blending = true;
uniform bool u_triplanar = false;

uniform float u_globalmap_blend_start;
uniform float u_globalmap_blend_distance;

uniform vec4 u_colormap_opacity_per_texture = vec4(1.0, 1.0, 1.0, 1.0);

varying float v_hole;
varying vec3 v_tint0;
varying vec3 v_tint1;
varying vec3 v_tint2;
varying vec3 v_tint3;
varying vec4 v_splat;
varying vec2 v_ground_uv0;
varying vec2 v_ground_uv1;
varying vec2 v_ground_uv2;
varying vec3 v_ground_uv3;
varying float v_distance_to_camera;


vec3 unpack_normal(vec4 rgba) {
	return rgba.xzy * 2.0 - vec3(1.0);
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
	v_ground_uv0 = base_ground_uv.xz / u_ground_uv_scale_per_texture.x;
	v_ground_uv1 = base_ground_uv.xz / u_ground_uv_scale_per_texture.y;
	v_ground_uv2 = base_ground_uv.xz / u_ground_uv_scale_per_texture.z;
	v_ground_uv3 = base_ground_uv / u_ground_uv_scale_per_texture.w;

	// Putting this in vertex saves 2 fetches from the fragment shader,
	// which is good for performance at a negligible quality cost,
	// provided that geometry is a regular grid that decimates with LOD.
	// (downside is LOD will also decimate tint and splat, but it's not bad overall)
	vec4 tint = texture(u_terrain_colormap, UV);
	v_hole = tint.a;
	v_tint0 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.x);
	v_tint1 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.y);
	v_tint2 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.z);
	v_tint3 = mix(vec3(1.0), tint.rgb, u_colormap_opacity_per_texture.w);
	v_splat = texture(u_terrain_splatmap, UV);

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

	vec3 terrain_normal_world = u_terrain_normal_basis * (unpack_normal(texture(u_terrain_normalmap, UV)) * vec3(1,1,-1));
	terrain_normal_world = normalize(terrain_normal_world);
	vec3 normal = terrain_normal_world;

	float globalmap_factor = clamp((v_distance_to_camera - u_globalmap_blend_start) * u_globalmap_blend_distance, 0.0, 1.0);
	globalmap_factor *= globalmap_factor; // slower start, faster transition but far away
	vec3 global_albedo = texture(u_terrain_globalmap, UV).rgb;
	ALBEDO = global_albedo;

	// Doing this branch allows to spare a bunch of texture fetches for distant pixels.
	// Eventually, there could be a split between near and far shaders in the future, if relevant on high-end GPUs
	if (globalmap_factor < 1.0) {
		vec4 ab3;
		vec4 nr3;
		if (u_triplanar) {
			// Only do triplanar on one texture slot,
			// because otherwise it would be very expensive and cost many more ifs.
			// I chose the last slot because first slot is the default on new splatmaps,
			// and that's a feature used for cliffs, which are usually designed later.

			vec3 blending = get_triplanar_blend(terrain_normal_world);

			ab3 = texture_triplanar(u_ground_albedo_bump_3, v_ground_uv3, blending);
			nr3 = texture_triplanar(u_ground_normal_roughness_3, v_ground_uv3, blending);

		} else {
			ab3 = texture(u_ground_albedo_bump_3, v_ground_uv3.xz);
			nr3 = texture(u_ground_normal_roughness_3, v_ground_uv3.xz);
		}

		vec4 ab0 = texture(u_ground_albedo_bump_0, v_ground_uv0);
		vec4 ab1 = texture(u_ground_albedo_bump_1, v_ground_uv1);
		vec4 ab2 = texture(u_ground_albedo_bump_2, v_ground_uv2);

		vec4 nr0 = texture(u_ground_normal_roughness_0, v_ground_uv0);
		vec4 nr1 = texture(u_ground_normal_roughness_1, v_ground_uv1);
		vec4 nr2 = texture(u_ground_normal_roughness_2, v_ground_uv2);

		vec3 col0 = ab0.rgb * v_tint0;
		vec3 col1 = ab1.rgb * v_tint1;
		vec3 col2 = ab2.rgb * v_tint2;
		vec3 col3 = ab3.rgb * v_tint3;

		vec4 rough = vec4(nr0.a, nr1.a, nr2.a, nr3.a);

		vec3 normal0 = unpack_normal(nr0);
		vec3 normal1 = unpack_normal(nr1);
		vec3 normal2 = unpack_normal(nr2);
		vec3 normal3 = unpack_normal(nr3);

		vec4 w;
		// TODO An #ifdef macro would be nice! Or copy/paste everything in a different shader...
		if (u_depth_blending) {
			w = get_depth_blended_weights(v_splat, vec4(ab0.a, ab1.a, ab2.a, ab3.a));
		} else {
			w = v_splat.rgba;
		}

		float w_sum = (w.r + w.g + w.b + w.a);

		ALBEDO = (
			w.r * col0.rgb +
			w.g * col1.rgb +
			w.b * col2.rgb +
			w.a * col3.rgb) / w_sum;

		ROUGHNESS = (
			w.r * rough.r +
			w.g * rough.g +
			w.b * rough.b +
			w.a * rough.a) / w_sum;

		vec3 ground_normal = /*u_terrain_normal_basis **/ (
			w.r * normal0 +
			w.g * normal1 +
			w.b * normal2 +
			w.a * normal3) / w_sum;
		// If no splat textures are defined, normal vectors will default to (1,1,1), which is incorrect,
		// and causes the terrain to be shaded wrongly in some directions.
		// However, this should not be a problem to fix in the shader, because there MUST be at least one splat texture set.
		//ground_normal = normalize(ground_normal);
		// TODO Make the plugin insert a default normalmap if it's empty

		// Combine terrain normals with detail normals (not sure if correct but looks ok)
		normal = normalize(vec3(
			terrain_normal_world.x + ground_normal.x,
			terrain_normal_world.y,
			terrain_normal_world.z + ground_normal.z));

		normal = mix(normal, terrain_normal_world, globalmap_factor);

		ALBEDO = mix(ALBEDO, global_albedo, globalmap_factor);
		ROUGHNESS = mix(ROUGHNESS, 1.0, globalmap_factor);

		// Show splatmap weights
		//ALBEDO = w.rgb;
	}
	// Highlight all pixels undergoing no splatmap at all
//	else {
//		ALBEDO = vec3(1.0, 0.0, 0.0);
//	}

	NORMAL = (INV_CAMERA_MATRIX * (vec4(normal, 0.0))).xyz;
}
