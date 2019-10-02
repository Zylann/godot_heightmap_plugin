shader_type spatial;
render_mode cull_disabled;

uniform sampler2D u_terrain_heightmap;
uniform sampler2D u_terrain_detailmap;
uniform sampler2D u_terrain_normalmap;
uniform sampler2D u_terrain_globalmap : hint_albedo;
uniform mat4 u_terrain_inverse_transform;
uniform mat3 u_terrain_normal_basis;

uniform sampler2D u_albedo_alpha : hint_albedo;
uniform float u_view_distance = 100.0;
uniform float u_globalmap_tint_bottom : hint_range(0.0, 1.0);
uniform float u_globalmap_tint_top : hint_range(0.0, 1.0);
uniform float u_bottom_ao : hint_range(0.0, 1.0);
uniform vec2 u_ambient_wind; // x: amplitude, y: time

varying vec3 v_normal;
varying vec2 v_map_uv;

float get_hash(vec2 c) {
	return fract(sin(dot(c.xy, vec2(12.9898,78.233))) * 43758.5453);
}

vec3 unpack_normal(vec4 rgba) {
	return rgba.xzy * 2.0 - vec3(1.0);
}

vec3 get_ambient_wind_displacement(vec2 uv, float hash) {
	// TODO This is an initial basic implementation. It may be improved in the future, especially for strong wind.
	float t = u_ambient_wind.y;
	float amp = u_ambient_wind.x * (1.0 - uv.y);
	// Main displacement
	vec3 disp = amp * vec3(cos(t), 0, sin(t * 1.2));
	// Fine displacement
	float fine_disp_frequency = 2.0;
	disp += 0.2 * amp * vec3(cos(t * (fine_disp_frequency + hash)), 0, sin(t * (fine_disp_frequency + hash) * 1.2));
	return disp;
}

void vertex() {
	vec4 obj_pos = WORLD_MATRIX * vec4(0, 1, 0, 1);
	vec3 cell_coords = (u_terrain_inverse_transform * obj_pos).xyz;
	vec2 map_uv = cell_coords.xz / vec2(textureSize(u_terrain_heightmap, 0));
	v_map_uv = map_uv;

	//float density = 0.5 + 0.5 * sin(4.0*TIME); // test
	float density = texture(u_terrain_detailmap, map_uv).r;
	float hash = get_hash(obj_pos.xz);
	
	if (density > hash) {
		// Snap model to the terrain
		float height = texture(u_terrain_heightmap, map_uv).r / cell_coords.y;
		VERTEX.y += height;
		
		VERTEX += get_ambient_wind_displacement(UV, hash);
		
		// Fade alpha with distance
		vec3 wpos = (WORLD_MATRIX * vec4(VERTEX, 1)).xyz;
		float dr = distance(wpos, CAMERA_MATRIX[3].xyz) / u_view_distance;
		COLOR.a = clamp(1.0 - dr * dr * dr, 0.0, 1.0);

		// When using billboards, the normal is the same as the terrain regardless of face orientation
		v_normal = normalize(u_terrain_normal_basis * (unpack_normal(texture(u_terrain_normalmap, map_uv)) * vec3(1, 1, -1)));

	} else {
		// Discard, output degenerate triangles
		VERTEX = vec3(0, 0, 0);
	}
}

void fragment() {
	NORMAL = (INV_CAMERA_MATRIX * (WORLD_MATRIX * vec4(v_normal, 0.0))).xyz;
	ALPHA_SCISSOR = 0.5;
	ROUGHNESS = 1.0;

	vec4 col = texture(u_albedo_alpha, UV);
	ALPHA = col.a * COLOR.a;// - clamp(1.4 - UV.y, 0.0, 1.0);//* 0.5 + 0.5*cos(2.0*TIME);
	
	ALBEDO = COLOR.rgb * col.rgb;

	// Blend with ground color
	float nh = sqrt(1.0 - UV.y);
	ALBEDO = mix(ALBEDO, texture(u_terrain_globalmap, v_map_uv).rgb, mix(u_globalmap_tint_bottom, u_globalmap_tint_top, nh));
	
	// Fake bottom AO
	ALBEDO = ALBEDO * mix(1.0, 1.0 - u_bottom_ao, UV.y * UV.y);
}
