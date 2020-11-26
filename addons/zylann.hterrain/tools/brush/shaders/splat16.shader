shader_type canvas_item;
render_mode blend_disabled;

uniform sampler2D u_brush_texture;
uniform float u_factor = 1.0;
uniform vec4 u_splat = vec4(1.0, 0.0, 0.0, 0.0);
uniform sampler2D u_other_splatmap_1;
uniform sampler2D u_other_splatmap_2;
uniform sampler2D u_other_splatmap_3;

float sum(vec4 v) {
	return v.x + v.y + v.z + v.w;
}

void fragment() {
	float brush_value = texture(u_brush_texture, SCREEN_UV).r;

	// It is assumed 3 other renders are done the same with the other 3
	vec4 src0 = texture(TEXTURE, UV);
	vec4 src1 = texture(u_other_splatmap_1);
	vec4 src2 = texture(u_other_splatmap_2);
	vec4 src3 = texture(u_other_splatmap_3);
	float t = u_factor * brush_value;
	vec4 s0 = mix(src, u_splat, t);
	vec4 s1 = mix(src, vec4(0.0), t);
	vec4 s2 = mix(src, vec4(0.0), t);
	vec4 s3 = mix(src, vec4(0.0), t);
	float sum = sum(s0) + sum(s1) + sum(s2) + sum(s3);
	s0 /= sum;
	s1 /= sum;
	s2 /= sum;
	s3 /= sum;
	COLOR = s0;
}
