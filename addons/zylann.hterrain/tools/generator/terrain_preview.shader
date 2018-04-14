shader_type canvas_item;

uniform float u_base_height = 0.0;
uniform float u_height_range = 100.0;

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE;
	float k = 1.0;
	
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	
	float h = texture(TEXTURE, uv).r;
	
	float left = texture(TEXTURE, uv + vec2(-ps.x, 0)).r * k;
	float right = texture(TEXTURE, uv + vec2(ps.x, 0)).r * k;
	float back = texture(TEXTURE, uv + vec2(0, -ps.y)).r * k;
	float fore = texture(TEXTURE, uv + vec2(0, ps.y)).r * k;

	vec3 n = normalize(vec3(left - right, 2.0, back - fore));
	
	vec3 light_dir = normalize(vec3(0.5, -1.0, -0.5));
	float d = clamp(-dot(light_dir, n), 0.0, 1.0);
	
	float nh = (h - u_base_height) / u_height_range;
	float gs = d * mix(0.5, 1.0, nh);
	COLOR = mix(vec4(gs, gs, gs, 1.0), vec4(1.0, 0.0, 0.0, 1.0), 0.0);
}

