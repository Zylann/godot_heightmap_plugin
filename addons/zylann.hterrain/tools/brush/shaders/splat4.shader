shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_brush_texture;
uniform float u_factor = 1.0;
uniform vec4 u_splat = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D u_heightmap;
uniform float u_normal_min_y = 0.0;
uniform float u_normal_max_y = 1.0;

vec3 get_normal(sampler2D heightmap, vec2 pos) {
	vec2 hp = vec2(1.0) / vec2(textureSize(heightmap, 0));
	float hnx = texture(heightmap, pos + vec2(-hp.x, 0.0)).r;
	float hpx = texture(heightmap, pos + vec2(hp.x, 0.0)).r;
	float hny = texture(heightmap, pos + vec2(0.0, -hp.y)).r;
	float hpy = texture(heightmap, pos + vec2(0.0, hp.y)).r;
	return normalize(vec3(hnx - hpx, 2.0, hpy - hny));
}

void fragment() {
	float brush_value = texture(u_brush_texture, SCREEN_UV).r;
	
	vec3 normal = get_normal(u_heightmap, UV);
	brush_value *= step(normal.y, u_normal_max_y);
	brush_value *= step(u_normal_min_y, normal.y);
	
	vec4 src = texture(TEXTURE, UV);
	vec4 s = mix(src, u_splat, u_factor * brush_value);
	s = s / (s.r + s.g + s.b + s.a);
	COLOR = s;
}
