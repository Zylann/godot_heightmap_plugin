shader_type spatial;

// This is a shader with less textures, in case the main one doesn't run on your GPU.
// It's mostly a big copy/paste, because Godot doesn't support #include or #ifdef...

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_normalmap;
uniform sampler2D u_terrain_colormap : hint_albedo;
uniform sampler2D u_terrain_splatmap;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

uniform sampler2D u_ground_albedo_bump_0 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_1 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_2 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_3 : hint_albedo;

uniform float u_ground_uv_scale = 20.0;
uniform bool u_depth_blending = true;
uniform bool u_triplanar = false;

varying vec4 v_tint;
varying vec4 v_splat;
varying vec3 v_ground_uv;


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
	vec2 cell_coords = (u_terrain_inverse_transform * WORLD_MATRIX * vec4(VERTEX, 1)).xz;

	// Normalized UV
	UV = cell_coords / vec2(textureSize(u_terrain_heightmap, 0));
	
	// Height displacement
	float h = texture(u_terrain_heightmap, UV).r;
	VERTEX.y = h;

	v_ground_uv = vec3(cell_coords.x, h * WORLD_MATRIX[1][1], cell_coords.y) / u_ground_uv_scale;
	
	// Putting this in vertex saves 2 fetches from the fragment shader,
	// which is good for performance at a negligible quality cost,
	// provided that geometry is a regular grid that decimates with LOD.
	// (downside is LOD will also decimate tint and splat, but it's not bad overall)
	v_tint = texture(u_terrain_colormap, UV);
	v_splat = texture(u_terrain_splatmap, UV);
	
	// Need to use u_terrain_normal_basis to handle scaling.
	// For some reason I also had to invert Z when sampling terrain normals... not sure why
	NORMAL = u_terrain_normal_basis * (unpack_normal(texture(u_terrain_normalmap, UV)) * vec3(1,1,-1));
}

void fragment() {

	if(v_tint.a < 0.5)
		// TODO Add option to use vertex discarding instead, using NaNs
		discard;
	
	vec3 terrain_normal_world = u_terrain_normal_basis * (unpack_normal(texture(u_terrain_normalmap, UV)) * vec3(1,1,-1));
	terrain_normal_world = normalize(terrain_normal_world);

	// TODO Detail should only be rasterized on nearby chunks (needs proximity management to switch shaders)
	
	vec2 ground_uv = v_ground_uv.xz;
	
	vec4 ab3;
	if (u_triplanar) {
		// Only do triplanar on one texture slot,
		// because otherwise it would be very expensive and cost many more ifs.
		// I chose the last slot because first slot is the default on new splatmaps,
		// and that's a feature used for cliffs, which are usually designed later.

		vec3 blending = get_triplanar_blend(terrain_normal_world);

		ab3 = texture_triplanar(u_ground_albedo_bump_3, v_ground_uv, blending);

	} else {
		ab3 = texture(u_ground_albedo_bump_3, ground_uv);
	}

	vec4 ab0 = texture(u_ground_albedo_bump_0, ground_uv);
	vec4 ab1 = texture(u_ground_albedo_bump_1, ground_uv);
	vec4 ab2 = texture(u_ground_albedo_bump_2, ground_uv);
	
	vec3 col0 = ab0.rgb;
	vec3 col1 = ab1.rgb;
	vec3 col2 = ab2.rgb;
	vec3 col3 = ab3.rgb;
	
	vec4 w;
	// TODO An #ifdef macro would be nice! Or copy/paste everything in a different shader...
	if (u_depth_blending) {
		w = get_depth_blended_weights(v_splat, vec4(ab0.a, ab1.a, ab2.a, ab3.a));
	} else {
		w = v_splat.rgba;
	}
	
	float w_sum = (w.r + w.g + w.b + w.a);
	
	ALBEDO = v_tint.rgb * (
		w.r * col0.rgb + 
		w.g * col1.rgb + 
		w.b * col2.rgb + 
		w.a * col3.rgb) / w_sum;
	
	ROUGHNESS = 1.0;
	
	NORMAL = (INV_CAMERA_MATRIX * (vec4(terrain_normal_world, 0.0))).xyz;

	//ALBEDO = w.rgb;
	//ALBEDO = v_ground_uv.xyz;
}

