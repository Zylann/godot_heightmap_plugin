shader_type spatial;
render_mode unshaded;//, depth_test_disable;

uniform sampler2D u_terrain_heightmap;
uniform mat4 u_terrain_inverse_transform;

void vertex() {
	vec2 ps = vec2(1.0) / vec2(textureSize(u_terrain_heightmap, 0));
	
	vec4 tv = u_terrain_inverse_transform * WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 uv = ps * vec2(tv.x, tv.z);
	
	// Get terrain normal
	float k = 1.0;
	float left = texture(u_terrain_heightmap, uv + vec2(-ps.x, 0)).r * k;
	float right = texture(u_terrain_heightmap, uv + vec2(ps.x, 0)).r * k;
	float back = texture(u_terrain_heightmap, uv + vec2(0, -ps.y)).r * k;
	float fore = texture(u_terrain_heightmap, uv + vec2(0, ps.y)).r * k;
	vec3 n = normalize(vec3(left - right, 2.0, back - fore));
	
	float h = texture(u_terrain_heightmap, uv).r;
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
