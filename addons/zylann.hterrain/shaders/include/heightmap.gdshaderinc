
// Use functions from this file everywhere a heightmap is used,
// so it is easy to track and change the format

float sample_heightmap(sampler2D spl, vec2 pos) {
	// RF
	return texture(spl, pos).r;
}

vec4 encode_height_to_viewport(float h) {
	//return vec4(encode_height_to_rgb8_unorm(h), 1.0);

	// Encode regular floats into an assumed RGBA8 output color.
	// This is used because Godot 4.0 doesn't support RF viewports,
	// and the irony is, even if float viewports get supported, it's likely it will end up RGBAF,
	// which is wasting bandwidth because we are only interested in R...
	uint u = floatBitsToUint(h);
	return vec4(
		float((u >> 0u) & 255u),
		float((u >> 8u) & 255u),
		float((u >> 16u) & 255u),
		float((u >> 24u) & 255u)
	) / vec4(255.0);
}

float decode_height_from_viewport(vec4 c) {
	uint u = uint(c.r * 255.0) 
		| (uint(c.g * 255.0) << 8u) 
		| (uint(c.b * 255.0) << 16u) 
		| (uint(c.a * 255.0) << 24u);
	return uintBitsToFloat(u);
}

float sample_height_from_viewport(sampler2D screen, vec2 uv) {
	ivec2 ts = textureSize(screen, 0);
	vec2 norm_to_px = vec2(ts);
	
	// Convert to pixels and apply a small offset so we interpolate from pixel centers
	vec2 uv_px_f = uv * norm_to_px - vec2(0.5);

	ivec2 uv_px = ivec2(uv_px_f);

	// Get interpolation pixel positions
	ivec2 p00 = uv_px;
	ivec2 p10 = uv_px + ivec2(1, 0);
	ivec2 p01 = uv_px + ivec2(0, 1);
	ivec2 p11 = uv_px + ivec2(1, 1);

	// Get pixels
	vec4 c00 = texelFetch(screen, p00, 0);
	vec4 c10 = texelFetch(screen, p10, 0);
	vec4 c01 = texelFetch(screen, p01, 0);
	vec4 c11 = texelFetch(screen, p11, 0);
	
	// Decode heights
	float h00 = decode_height_from_viewport(c00);
	float h10 = decode_height_from_viewport(c10);
	float h01 = decode_height_from_viewport(c01);
	float h11 = decode_height_from_viewport(c11);
	
	// Linear filter
	vec2 f = fract(uv_px_f);
	float h = mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
	
	return h;
}
