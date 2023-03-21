
// TODO Small discrepancy in encoding:
// 8-bit components are normalized using c / 255.0, therefore they can be 1,
// but the logic below assumes they are normalized with `c / 256.0`.
// We should test using an extra factor to smooth this out.
const float FROM_FIXED = 255.0 / 256.0;
const float TO_FIXED = 256.0 / 255.0;

// Decodes height from a normalized 8-bit RGB value.
// Tuned for heights in -8192.0 .. 8191.0
float decode_height_from_rgb8_unorm(vec3 c) {
	// Each component has 8-bit of precision, so 256 possible values.
	// More components gives us more values decomposed at higher ranges:
	// c.r + c.g * 256.0 + c.b * 65536.0
	// Adapting to our use case, we may divide each factor to fit the range and
	// step we need. Each factor remains a power of two.
	return c.r * 0.25 + c.g * 64.0 + c.b * 16384.0 - 8192.0;
}

// Encodes height into a normalized 8-bit RGB value.
// Tuned for heights in -8192.0 .. 8191.0. Values outside of this range are clamped.
vec3 encode_height_to_rgb8_unorm(float h) {
	h = clamp(h + 8192.0, 0.0, 16384.0);
	// Extract small component
	float r = mod(h, 0.25);
	h -= r;
	// Extract medium component
	float g = mod(h, 64.0);
	h -= g;
	// Remaining value is big component
	float b = h;
	// Normalize
	return vec3(r, g, b) / vec3(0.25, 64.0, 16384.0);
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
