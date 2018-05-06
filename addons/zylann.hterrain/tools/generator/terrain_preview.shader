shader_type canvas_item;

uniform sampler2D u_normal_texture;
uniform float u_base_height = 0.0;
uniform float u_height_range = 100.0;

vec3 unpack_normal(vec4 rgba) {
	return rgba.xyz * 2.0 - vec3(1.0);
}

void fragment() {
	vec2 ps = TEXTURE_PIXEL_SIZE;
	vec2 uv = vec2(UV.x, 1.0 - UV.y);

	float h = texture(TEXTURE, uv).r;
	
	/*float k = 1.0;
	float left = texture(TEXTURE, uv + vec2(-ps.x, 0)).r * k;
	float right = texture(TEXTURE, uv + vec2(ps.x, 0)).r * k;
	float back = texture(TEXTURE, uv + vec2(0, -ps.y)).r * k;
	float fore = texture(TEXTURE, uv + vec2(0, ps.y)).r * k;
	vec3 n = normalize(vec3(left - right, 2.0, back - fore));*/
	vec3 n = unpack_normal(texture(u_normal_texture, uv));
	
	vec3 light_dir = normalize(vec3(0.5, -1.0, -0.5));
	float d = clamp(-dot(light_dir, n), 0.0, 1.0);
	
	float nh = (h - u_base_height) / u_height_range;
	float gs = d * mix(0.5, 1.0, nh);
	COLOR = mix(vec4(gs, gs, gs, 1.0), vec4(1.0, 0.0, 0.0, 1.0), 0.0);

	// TODO Have a mode to choose what to output
	//COLOR = vec4(nh, nh, nh, 1.0);
	//COLOR = vec4(n.x, n.y, n.z, 1.0);
}

