shader_type canvas_item;

uniform sampler2D u_screen_texture : hint_screen_texture;

vec4 pack_normal(vec3 n) {
	return vec4((0.5 * (n + 1.0)).xzy, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 ps = SCREEN_PIXEL_SIZE;
	float left = texture(u_screen_texture, uv + vec2(-ps.x, 0)).r;
	float right = texture(u_screen_texture, uv + vec2(ps.x, 0)).r;
	float back = texture(u_screen_texture, uv + vec2(0, -ps.y)).r;
	float fore = texture(u_screen_texture, uv + vec2(0, ps.y)).r;
	vec3 n = normalize(vec3(left - right, 2.0, fore - back));
	COLOR = pack_normal(n);
}

