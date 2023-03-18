shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_src_texture;
uniform vec4 u_src_rect;
uniform float u_opacity = 1.0;
uniform vec4 u_splat = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D u_other_splatmap_1;
uniform sampler2D u_other_splatmap_2;
uniform sampler2D u_other_splatmap_3;
uniform sampler2D u_heightmap;
uniform float u_normal_min_y = 0.0;
uniform float u_normal_max_y = 1.0;

vec2 get_src_uv(vec2 screen_uv) {
	vec2 uv = u_src_rect.xy + screen_uv * u_src_rect.zw;
	return uv;
}

float sum(vec4 v) {
	return v.x + v.y + v.z + v.w;
}

vec3 get_normal(sampler2D heightmap, vec2 pos) {
	vec2 ps = vec2(1.0) / vec2(textureSize(heightmap, 0));
	float hnx = texture(heightmap, pos + vec2(-ps.x, 0.0)).r;
	float hpx = texture(heightmap, pos + vec2(ps.x, 0.0)).r;
	float hny = texture(heightmap, pos + vec2(0.0, -ps.y)).r;
	float hpy = texture(heightmap, pos + vec2(0.0, ps.y)).r;
	return normalize(vec3(hnx - hpx, 2.0, hpy - hny));
}

// Limits painting based on the slope, with a bit of falloff
float apply_slope_limit(float brush_value, vec3 normal, float normal_min_y, float normal_max_y) {
	float normal_falloff = 0.2;

	// If an edge is at min/max, make sure it won't be affected by falloff
	normal_min_y = normal_min_y <= 0.0 ? -2.0 : normal_min_y;
	normal_max_y = normal_max_y >= 1.0 ? 2.0 : normal_max_y;

	brush_value *= 1.0 - smoothstep(
		normal_max_y - normal_falloff,
		normal_max_y + normal_falloff, normal.y);

	brush_value *= smoothstep(
		normal_min_y - normal_falloff,
		normal_min_y + normal_falloff, normal.y);

	return brush_value;
}

void fragment() {
	float brush_value = u_opacity * texture(TEXTURE, UV).r;
	
	vec2 src_uv = get_src_uv(SCREEN_UV);
	vec3 normal = get_normal(u_heightmap, src_uv);
	brush_value = apply_slope_limit(brush_value, normal, u_normal_min_y, u_normal_max_y);

	// It is assumed 3 other renders are done the same with the other 3
	vec4 src0 = texture(u_src_texture, src_uv);
	vec4 src1 = texture(u_other_splatmap_1, src_uv);
	vec4 src2 = texture(u_other_splatmap_2, src_uv);
	vec4 src3 = texture(u_other_splatmap_3, src_uv);
	float t = brush_value;
	vec4 s0 = mix(src0, u_splat, t);
	vec4 s1 = mix(src1, vec4(0.0), t);
	vec4 s2 = mix(src2, vec4(0.0), t);
	vec4 s3 = mix(src3, vec4(0.0), t);
	float sum = sum(s0) + sum(s1) + sum(s2) + sum(s3);
	s0 /= sum;
	s1 /= sum;
	s2 /= sum;
	s3 /= sum;
	COLOR = s0;
}
