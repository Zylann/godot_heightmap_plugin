shader_type canvas_item;

vec4 pack_normal(vec3 n) {
	return vec4((0.5 * (n + 1.0)).xzy, 1.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 ps = TEXTURE_PIXEL_SIZE;
	float left = texture(TEXTURE, uv + vec2(-ps.x, 0)).r;
	float right = texture(TEXTURE, uv + vec2(ps.x, 0)).r;
	float back = texture(TEXTURE, uv + vec2(0, -ps.y)).r;
	float fore = texture(TEXTURE, uv + vec2(0, ps.y)).r;
	vec3 n = normalize(vec3(left - right, 2.0, fore - back));
	COLOR = pack_normal(n);
	// DEBUG
	//COLOR.r = fract(TIME * 100.0);
}

