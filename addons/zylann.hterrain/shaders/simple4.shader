shader_type spatial;

// This is the reference shader of the plugin, and has the most features.
// it should be preferred for high-end graphics cards.
// For less features but lower-end targets, see the lite version.

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_normalmap;
// I had to remove `hint_albedo` from colormap because it makes sRGB conversion kick in,
// which snowballs to black when doing GPU painting on that texture...
uniform sampler2D u_terrain_colormap;
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
// Each component corresponds to a ground texture. Set greater than zero to enable.
uniform vec4 u_tile_reduction = vec4(0.0, 0.0, 0.0, 0.0);

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
	vec3 n = rgba.xzy * 2.0 - vec3(1.0);
	// Had to negate Z because it comes from Y in the normal map,
	// and OpenGL-style normal maps are Y-up.
	n.z *= -1.0;
	return n;
}

vec4 pack_normal(vec3 n, float a) {
	n.z *= -1.0;
	return vec4((n.xzy + vec3(1.0)) * 0.5, a);
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

vec4 depth_blend2(vec4 a_value, float a_bump, vec4 b_value, float b_bump, float t) {
	// https://www.gamasutra.com
	// /blogs/AndreyMishkinis/20130716/196339/Advanced_Terrain_Texture_Splatting.php
	float d = 0.1;
	float ma = max(a_bump + (1.0 - t), b_bump + t) - d;
	float ba = max(a_bump + (1.0 - t) - ma, 0.0);
	float bb = max(b_bump + t - ma, 0.0);
	return (a_value * ba + b_value * bb) / (ba + bb);
}

vec2 rotate(vec2 v, float cosa, float sina) {
	return vec2(cosa * v.x - sina * v.y, sina * v.x + cosa * v.y);
}

vec4 texture_antitile(sampler2D albedo_tex, sampler2D normal_tex, vec2 uv, out vec4 out_normal) {
	float frequency = 2.0;
	float scale = 1.3;
	float sharpness = 0.7;
	
	// Rotate and scale UV
	float rot = 3.14 * 0.6;
	float cosa = cos(rot);
	float sina = sin(rot);
	vec2 uv2 = rotate(uv, cosa, sina) * scale;
	
	vec4 col0 = texture(albedo_tex, uv);
	vec4 col1 = texture(albedo_tex, uv2);
	vec4 nrm0 = texture(normal_tex, uv);
	vec4 nrm1 = texture(normal_tex, uv2);
	//col0 = vec4(0.0, 0.5, 0.5, 1.0); // Highlights variations

	// Normals have to be rotated too since we are rotating the texture...
	// TODO Probably not the most efficient but understandable for now
	vec3 n = unpack_normal(nrm1);
	// Had to negate the Y axis for some reason. I never remember the myriad of conventions around
	n.xz = rotate(n.xz, cosa, -sina);
	nrm1 = pack_normal(n, nrm1.a);
	
	// Periodically alternate between the two versions using a warped checker pattern
	float t = 1.2 + 
		  sin(uv2.x * frequency + sin(uv.x) * 2.0) 
		* cos(uv2.y * frequency + sin(uv.y) * 2.0); // Result in [0..2]
	t = smoothstep(sharpness, 2.0 - sharpness, t);

	// Using depth blend because classic alpha blending smoothes out details.
	out_normal = depth_blend2(nrm0, col0.a, nrm1, col1.a, t);
	return depth_blend2(col0, col0.a, col1, col1.a, t);
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
	NORMAL = u_terrain_normal_basis * unpack_normal(texture(u_terrain_normalmap, UV));

	v_distance_to_camera = distance(wpos.xyz, CAMERA_MATRIX[3].xyz);
}

void fragment() {
	if (v_hole < 0.5) {
		// TODO Add option to use vertex discarding instead, using NaNs
		discard;
	}

	vec3 terrain_normal_world = 
		u_terrain_normal_basis * unpack_normal(texture(u_terrain_normalmap, UV));
	terrain_normal_world = normalize(terrain_normal_world);
	vec3 normal = terrain_normal_world;

	float globalmap_factor = clamp((v_distance_to_camera - u_globalmap_blend_start) 
		* u_globalmap_blend_distance, 0.0, 1.0);
	globalmap_factor *= globalmap_factor; // slower start, faster transition but far away
	vec3 global_albedo = texture(u_terrain_globalmap, UV).rgb;
	ALBEDO = global_albedo;

	// Doing this branch allows to spare a bunch of texture fetches for distant pixels.
	// Eventually, there could be a split between near and far shaders in the future,
	// if relevant on high-end GPUs
	if (globalmap_factor < 1.0) {
		vec4 ab0, ab1, ab2, ab3;
		vec4 nr0, nr1, nr2, nr3;

		if (u_triplanar) {
			// Only do triplanar on one texture slot,
			// because otherwise it would be very expensive and cost many more ifs.
			// I chose the last slot because first slot is the default on new splatmaps,
			// and that's a feature used for cliffs, which are usually designed later.

			vec3 blending = get_triplanar_blend(terrain_normal_world);

			ab3 = texture_triplanar(u_ground_albedo_bump_3, v_ground_uv3, blending);
			nr3 = texture_triplanar(u_ground_normal_roughness_3, v_ground_uv3, blending);

		} else {
			if (u_tile_reduction[3] > 0.0) {
				ab3 = texture_antitile(
					u_ground_albedo_bump_3, u_ground_normal_roughness_3, v_ground_uv3.xz, nr3);
			} else {
				ab3 = texture(u_ground_albedo_bump_3, v_ground_uv3.xz);
				nr3 = texture(u_ground_normal_roughness_3, v_ground_uv3.xz);
			}
		}

		if (u_tile_reduction[0] > 0.0) {
			ab0 = texture_antitile(
				u_ground_albedo_bump_0, u_ground_normal_roughness_0, v_ground_uv0, nr0);
		} else {
			ab0 = texture(u_ground_albedo_bump_0, v_ground_uv0);
			nr0 = texture(u_ground_normal_roughness_0, v_ground_uv0);
		}
		if (u_tile_reduction[1] > 0.0) {
			ab1 = texture_antitile(
				u_ground_albedo_bump_1, u_ground_normal_roughness_1, v_ground_uv1, nr1);
		} else {
			ab1 = texture(u_ground_albedo_bump_1, v_ground_uv1);
			nr1 = texture(u_ground_normal_roughness_1, v_ground_uv1);
		}
		if (u_tile_reduction[2] > 0.0) {
			ab2 = texture_antitile(
				u_ground_albedo_bump_2, u_ground_normal_roughness_2, v_ground_uv2, nr2);
		} else {
			ab2 = texture(u_ground_albedo_bump_2, v_ground_uv2);
			nr2 = texture(u_ground_normal_roughness_2, v_ground_uv2);
		}

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
		// If no splat textures are defined, normal vectors will default to (1,1,1),
		// which is incorrect, and causes the terrain to be shaded wrongly in some directions.
		// However, this should not be a problem to fix in the shader,
		// because there MUST be at least one splat texture set.
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
