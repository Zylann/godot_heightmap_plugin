shader_type spatial;
render_mode cull_disabled;

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_albedo_alpha;
//uniform sampler2D u_terrain_normalmap;

void vertex() {
	vec4 tv = /*heightmap_inverse_transform **/ WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 uv = vec2(tv.x, tv.z) / vec2(textureSize(u_terrain_heightmap, 0));

	float height = texture(u_terrain_heightmap, uv).r;
	
	// Snap model to the terrain
	VERTEX.y += height;
	
	/*vec3 wpos = (WORLD_MATRIX * vec4(VERTEX, 1)).xyz;
	vec3 campos = CAMERA_MATRIX[3].xyz;
	float distance_to_camera = distance(wpos, campos);
	float max_fade_distance = 100.0;
	COLOR.a = clamp(1.0 - distance_to_camera / max_fade_distance, 0.0, 1.0);*/
}

void fragment() {
	NORMAL = vec3(0, 1, 0); // TODO Pick from terrain slope
	ALPHA_SCISSOR = 0.5;
	ROUGHNESS = 1.0;
	vec4 col = texture(u_albedo_alpha, UV);
	ALPHA = col.a * COLOR.a;// - clamp(1.4 - UV.y, 0.0, 1.0);//* 0.5 + 0.5*cos(2.0*TIME);
	ALBEDO = COLOR.rgb * col.rgb;
}
