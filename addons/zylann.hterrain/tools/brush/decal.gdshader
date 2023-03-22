shader_type spatial;
render_mode unshaded;//, depth_test_disable;

#include "res://addons/zylann.hterrain/shaders/include/heightmap_rgb8_encoding.gdshaderinc"

uniform sampler2D u_terrain_heightmap;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

float get_height(sampler2D heightmap, vec2 uv) {
	return decode_height_from_rgb8_unorm(texture(heightmap, uv).rgb);
}

void vertex() {
	vec2 cell_coords = (u_terrain_inverse_transform * MODEL_MATRIX * vec4(VERTEX, 1)).xz;

	vec2 ps = vec2(1.0) / vec2(textureSize(u_terrain_heightmap, 0));
	vec2 uv = ps * cell_coords;
	
	// Get terrain normal
	float k = 1.0;
	float left = get_height(u_terrain_heightmap, uv + vec2(-ps.x, 0)) * k;
	float right = get_height(u_terrain_heightmap, uv + vec2(ps.x, 0)) * k;
	float back = get_height(u_terrain_heightmap, uv + vec2(0, -ps.y)) * k;
	float fore = get_height(u_terrain_heightmap, uv + vec2(0, ps.y)) * k;
	vec3 n = normalize(vec3(left - right, 2.0, back - fore));

	n = u_terrain_normal_basis * n;
	
	float h = get_height(u_terrain_heightmap, uv);
	VERTEX.y = h;
	VERTEX += 1.0 * n;
	NORMAL = n;//vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float len = length(2.0 * UV - 1.0);
	float g = clamp(1.0 - 15.0 * abs(0.9 - len), 0.0, 1.0);
	ALBEDO = vec3(1.0, 0.1, 0.1);
	ALPHA = g;
}
