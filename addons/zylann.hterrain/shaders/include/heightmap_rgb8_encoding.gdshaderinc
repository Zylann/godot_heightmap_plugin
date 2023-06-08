
const float V2_UNIT_STEPS = 100.0;
const float V2_MIN = -8192.0;

float decode_height_from_rgb8_unorm_2(vec3 c) {
	int res = int(c.b * 255.0);
	res <<= 8;
	res |= int(c.g * 255.0);
	res <<= 8;
	res |= int(c.r * 255.0);

	return (float(res) / V2_UNIT_STEPS) + V2_MIN;
}

vec3 encode_height_to_rgb8_unorm_2(float h) {
	// TODO Check if this has float precision issues
	h -= V2_MIN;
	int hi = int(h * V2_UNIT_STEPS);
	float r = float(hi&0xff) / 255.0;
	float g = float((hi>>8)&0xff) / 255.0;
	float b = float((hi>>16)&0xff) / 255.0;
	return vec3(r, g, b);
}

float decode_height_from_rgb8_unorm(vec3 c) {
	return decode_height_from_rgb8_unorm_2(c);
}

vec3 encode_height_to_rgb8_unorm(float h) {
	return encode_height_to_rgb8_unorm_2(h);
}

// TODO Remove for now?
// Bilinear filtering appears to work well enough without doing this.
// There are some artifacts, but we could easily live with them,
// and I suspect they could be easy to patch somehow in the encoding/decoding.
//
// In case bilinear filtering is required.
// This is slower than if we had a native float format.
// Unfortunately, Godot 4 removed support for 2D HDR viewports. They were used
// to edit this format natively. Using compute shaders would force users to
// have Vulkan. So we had to downgrade performance a bit using a technique from the GLES2 era...
float sample_height_bilinear_rgb8_unorm(sampler2D heightmap, vec2 uv) {
	vec2 ts = vec2(textureSize(heightmap, 0));
	vec2 p00f = uv * ts;
	ivec2 p00 = ivec2(p00f);

	vec3 s00 = texelFetch(heightmap, p00, 0).rgb;
	vec3 s10 = texelFetch(heightmap, p00 + ivec2(1, 0), 0).rgb;
	vec3 s01 = texelFetch(heightmap, p00 + ivec2(0, 1), 0).rgb;
	vec3 s11 = texelFetch(heightmap, p00 + ivec2(1, 1), 0).rgb;

	float h00 = decode_height_from_rgb8_unorm(s00);
	float h10 = decode_height_from_rgb8_unorm(s10);
	float h01 = decode_height_from_rgb8_unorm(s01);
	float h11 = decode_height_from_rgb8_unorm(s11);

	vec2 f = p00f - vec2(p00);
	return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
}
