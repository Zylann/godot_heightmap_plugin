shader_type spatial;

// This is a very simple shader for a low-poly coloured visual, without textures

#include "res://addons/zylann.hterrain/shaders/include/heightmap.gdshaderinc"

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_normalmap;
// I had to remove `hint_albedo` from colormap in Godot 3 because it makes sRGB conversion kick in,
// which snowballs to black when doing GPU painting on that texture...
uniform sampler2D u_terrain_colormap;// : hint_albedo;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

varying flat vec4 v_tint;


vec3 unpack_normal(vec4 rgba) {
	vec3 n = rgba.xzy * 2.0 - vec3(1.0);
	// Had to negate Z because it comes from Y in the normal map,
	// and OpenGL-style normal maps are Y-up.
	n.z *= -1.0;
	return n;
}

void vertex() {
	vec2 cell_coords = (u_terrain_inverse_transform * MODEL_MATRIX * vec4(VERTEX, 1)).xz;
	// Must add a half-offset so that we sample the center of pixels,
	// otherwise bilinear filtering of the textures will give us mixed results (#183)
	cell_coords += vec2(0.5);

	// Normalized UV
	UV = cell_coords / vec2(textureSize(u_terrain_heightmap, 0));
	
	// Height displacement
	float h = sample_heightmap(u_terrain_heightmap, UV);
	VERTEX.y = h;
	
	// Putting this in vertex saves 2 fetches from the fragment shader,
	// which is good for performance at a negligible quality cost,
	// provided that geometry is a regular grid that decimates with LOD.
	// (downside is LOD will also decimate tint and splat, but it's not bad overall)
	v_tint = texture(u_terrain_colormap, UV);
	
	// Need to use u_terrain_normal_basis to handle scaling.
	NORMAL = u_terrain_normal_basis * unpack_normal(texture(u_terrain_normalmap, UV));
}

void fragment() {
	if (v_tint.a < 0.5) {
		// TODO Add option to use vertex discarding instead, using NaNs
		discard;
	}
	
	vec3 terrain_normal_world = 
		u_terrain_normal_basis * unpack_normal(texture(u_terrain_normalmap, UV));
	terrain_normal_world = normalize(terrain_normal_world);
	
	ALBEDO = v_tint.rgb;
	ROUGHNESS = 1.0;
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
}

