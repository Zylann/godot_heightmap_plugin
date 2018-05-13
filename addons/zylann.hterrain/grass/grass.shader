shader_type spatial;
render_mode cull_disabled;

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_grassmap;
uniform sampler2D u_albedo_alpha;
uniform float u_view_distance;
//uniform sampler2D u_terrain_normalmap;

float get_hash(vec2 c) {
	return fract(sin(dot(c.xy, vec2(12.9898,78.233))) * 43758.5453);
}

void vertex() {
	vec4 tv = /*heightmap_inverse_transform **/ WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 uv = vec2(tv.x, tv.z) / vec2(textureSize(u_terrain_heightmap, 0));

	//float density = 0.5 + 0.5 * sin(4.0*TIME); // test
	float density = texture(u_terrain_grassmap, uv).r;
	float hash = get_hash((WORLD_MATRIX * vec4(0, 0, 0, 1)).xz);
	
	if(density > hash) {
		float height = texture(u_terrain_heightmap, uv).r;
	
		// Snap model to the terrain
		VERTEX.y += height;
		
		vec3 wpos = (WORLD_MATRIX * vec4(VERTEX, 1)).xyz;
		vec3 campos = CAMERA_MATRIX[3].xyz;
		float distance_to_camera = distance(wpos, campos);
		float dr = distance_to_camera / u_view_distance;
		COLOR.a = clamp(1.0 - dr * dr * dr, 0.0, 1.0);
		
	} else {
		// Discard, output degenerate triangles
		VERTEX = vec3(0, 0, 0);
	}
}

void fragment() {
	NORMAL = vec3(0, 1, 0); // TODO Pick from terrain slope
	ALPHA_SCISSOR = 0.5;
	ROUGHNESS = 1.0;
	vec4 col = texture(u_albedo_alpha, UV);
	ALPHA = col.a * COLOR.a;// - clamp(1.4 - UV.y, 0.0, 1.0);//* 0.5 + 0.5*cos(2.0*TIME);
	ALBEDO = COLOR.rgb * col.rgb;
}
