shader_type canvas_item;

uniform sampler2D noise_texture;
uniform vec2 u_offset;
uniform float u_base_height = 0.0;
uniform float u_height_range = 100.0;
uniform int u_seed;
uniform float u_scale = 0.02;
uniform int u_octaves = 5;
uniform float u_roughness = 0.5;
uniform float u_curve = 1.0;

float get_noise(vec2 uv) {
	return texture(noise_texture, uv).r;
}

float get_smooth_noise(vec2 uv, int extra_magic_rot) {
	float scale = u_scale;
	float sum = 0.0;
	float amp = 0.0;
	int octaves = u_octaves;
	float p = 1.0;
	
	for (int i = 0; i < octaves; ++i) {
		// Rotate and translate lookups to reduce directional artifacts
		vec2 vx = vec2(cos(float(i * 543 + extra_magic_rot)), sin(float(i * 543 + extra_magic_rot)));
		vec2 vy = vec2(-vx.y, vx.x);
		mat2 magic_rotation = mat2(vx, vy);
		vec2 magic_offset = vec2(-0.113 * float(i + u_seed), 0.0538 * float(i - u_seed));
		
		sum += p * get_noise((magic_rotation * uv) * scale + magic_offset);
		amp += p;
		scale *= 2.0;
		p *= u_roughness;
	}

	float gs = sum / amp;
	return gs;
}

void fragment() {
	vec2 uv = UV + u_offset;
	
	float gs = get_smooth_noise(uv, 0);
//	gs = 1.0 * abs(gs - 0.5);
//	gs += 0.5 * get_smooth_noise(uv + vec2(123.0, 456.0), 33);
	gs = pow(gs, u_curve);
	gs = u_base_height + gs * u_height_range;
	
	//gs = step(gs, 0.25);
	
	COLOR = vec4(gs, gs, gs, 1.0);
}
