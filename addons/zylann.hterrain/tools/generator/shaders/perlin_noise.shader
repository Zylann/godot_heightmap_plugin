shader_type canvas_item;

uniform sampler2D u_noise_texture;
uniform vec2 u_offset;
uniform float u_scale = 0.02;
uniform float u_base_height = 0.0;
uniform float u_height_range = 100.0;
uniform int u_seed;
uniform int u_octaves = 5;
uniform float u_roughness = 0.5;
uniform float u_curve = 1.0;

uniform vec2 u_uv_offset;
uniform vec2 u_uv_scale = vec2(1.0, 1.0);

float get_noise(vec2 uv) {

	vec2 ts = vec2(textureSize(u_noise_texture, 0));
	//vec2 ps = 1.0 / ts;

	vec2 puv = uv * ts;

	float c00 = texture(u_noise_texture, floor(puv) / ts).r;
	float c10 = texture(u_noise_texture, floor(puv + vec2(1.0, 0.0)) / ts).r;
	float c01 = texture(u_noise_texture, floor(puv + vec2(0.0, 1.0)) / ts).r;
	float c11 = texture(u_noise_texture, floor(puv + vec2(1.0, 1.0)) / ts).r;

	vec2 fuv = fract(puv);

	//return mix(mix(c00, c01, fuv.y), mix(c10, c11, fuv.y), fuv.x);

	vec2 u = fuv * fuv * (3.0 - 2.0 * fuv);
	return mix(c00, c10, u.x) + (c01 - c00) * u.y * (1.0 - u.x) + (c11 - c10) * u.x * u.y;

	// Normally, the filter offered by OpenGL should have done the job,
	// but for some reason it has 8-bit quality results, despite the texture being 32bit,
	// which produce aliasing when calculating normals...
	// something must be wrong between my driver and Godot
	//return texture(u_noise_texture, uv).r;
}

float get_smooth_noise(vec2 uv, int extra_magic_rot) {
	float scale = 1.0;
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

float get_height(vec2 uv) {
	float h = get_smooth_noise(uv, 0);
	h = pow(h, u_curve);
	h = u_base_height + h * u_height_range;
	return h;
}

vec3 pack_normal(vec3 n) {
	return (0.5 * (n + 1.0)).xzy;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// Handle screen padding: transform UV back into generation space
	uv = (uv + u_uv_offset) * u_uv_scale;

	// Offset and scale for the noise itself
	uv = (uv + u_offset) * u_scale;

	float h = get_height(uv);
	COLOR = vec4(h, h, h, 1.0);
}
