shader_type canvas_item;

uniform vec2 u_offset;
uniform float u_scale = 0.02;
uniform float u_base_height = 0.0;
uniform float u_height_range = 100.0;
uniform int u_seed;
uniform int u_octaves = 5;
uniform float u_roughness = 0.5;
uniform float u_curve = 1.0;
uniform float u_terrain_size = 513.0;
uniform float u_tile_size = 513.0;
uniform sampler2D u_additive_heightmap;
uniform float u_additive_heightmap_factor = 0.0;
uniform vec2 u_uv_offset;
uniform vec2 u_uv_scale = vec2(1.0, 1.0);

uniform float u_island_weight = 0.0;
// 0: smooth transition, 1: sharp transition
uniform float u_island_sharpness = 0.0;
// 0: edge is min height (island), 1: edge is max height (canyon)
uniform float u_island_height_ratio = 0.0;
// 0: round, 1: square
uniform float u_island_shape = 0.0;

////////////////////////////////////////////////////////////////////////////////
// Perlin noise source:
// https://github.com/curly-brace/Godot-3.0-Noise-Shaders
//
// GLSL textureless classic 2D noise \"cnoise\",
// with an RSL-style periodic variant \"pnoise\".
// Author:  Stefan Gustavson (stefan.gustavson@liu.se)
// Version: 2011-08-22
//
// Many thanks to Ian McEwan of Ashima Arts for the
// ideas for permutation and gradient selection.
//
// Copyright (c) 2011 Stefan Gustavson. All rights reserved.
// Distributed under the MIT license. See LICENSE file.
// https://github.com/stegu/webgl-noise
//

vec4 mod289(vec4 x) {
    return x - floor(x * (1.0 / 289.0)) * 289.0;
}

vec4 permute(vec4 x) {
    return mod289(((x * 34.0) + 1.0) * x);
}

vec4 taylorInvSqrt(vec4 r) {
    return 1.79284291400159 - 0.85373472095314 * r;
}

vec2 fade(vec2 t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// Classic Perlin noise
float cnoise(vec2 P) {
    vec4 Pi = floor(vec4(P, P)) + vec4(0.0, 0.0, 1.0, 1.0);
    vec4 Pf = fract(vec4(P, P)) - vec4(0.0, 0.0, 1.0, 1.0);
    Pi = mod289(Pi); // To avoid truncation effects in permutation
    vec4 ix = Pi.xzxz;
    vec4 iy = Pi.yyww;
    vec4 fx = Pf.xzxz;
    vec4 fy = Pf.yyww;

    vec4 i = permute(permute(ix) + iy);

    vec4 gx = fract(i * (1.0 / 41.0)) * 2.0 - 1.0 ;
    vec4 gy = abs(gx) - 0.5 ;
    vec4 tx = floor(gx + 0.5);
    gx = gx - tx;

    vec2 g00 = vec2(gx.x,gy.x);
    vec2 g10 = vec2(gx.y,gy.y);
    vec2 g01 = vec2(gx.z,gy.z);
    vec2 g11 = vec2(gx.w,gy.w);
    
    vec4 norm = taylorInvSqrt(vec4(dot(g00, g00), dot(g01, g01), dot(g10, g10), dot(g11, g11)));
    g00 *= norm.x;
    g01 *= norm.y;
    g10 *= norm.z;
    g11 *= norm.w;
    
    float n00 = dot(g00, vec2(fx.x, fy.x));
    float n10 = dot(g10, vec2(fx.y, fy.y));
    float n01 = dot(g01, vec2(fx.z, fy.z));
    float n11 = dot(g11, vec2(fx.w, fy.w));
    
    vec2 fade_xy = fade(Pf.xy);
    vec2 n_x = mix(vec2(n00, n01), vec2(n10, n11), fade_xy.x);
    float n_xy = mix(n_x.x, n_x.y, fade_xy.y);
    return 2.3 * n_xy;
}
////////////////////////////////////////////////////////////////////////////////

float get_fractal_noise(vec2 uv) {
	float scale = 1.0;
	float sum = 0.0;
	float amp = 0.0;
	int octaves = u_octaves;
	float p = 1.0;
	uv.x += float(u_seed) * 61.0;
	
	for (int i = 0; i < octaves; ++i) {
		sum += p * cnoise(uv * scale);
		amp += p;
		scale *= 2.0;
		p *= u_roughness;
	}

	float gs = sum / amp;
	return gs;
}

// x is a ratio in 0..1
float get_island_curve(float x) {
	return smoothstep(min(0.999, u_island_sharpness), 1.0, x);
//	float exponent = 1.0 + 10.0 * u_island_sharpness;
//	return pow(abs(x), exponent);
}

float smooth_union(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float squareish_distance(vec2 a, vec2 b, float r, float s) {
	vec2 v = b - a;
	// TODO This is brute force but this is the first attempt that gave me a "rounded square" distance,
	// where the "roundings" remained constant over distance (not the case with standard box SDF)
	float da = -smooth_union(v.x+s, v.y+s, r)+s;
	float db = -smooth_union(s-v.x, s-v.y, r)+s;
	float dc = -smooth_union(s-v.x, v.y+s, r)+s;
	float dd = -smooth_union(v.x+s, s-v.y, r)+s;
	return max(max(da, db), max(dc, dd));
}

// This is too sharp
//float squareish_distance(vec2 a, vec2 b) {
//	vec2 v = b - a;
//	// Manhattan distance would produce a "diamond-shaped distance".
//	// This gives "square-shaped" distance.
//	return max(abs(v.x), abs(v.y));
//}

float get_island_distance(vec2 pos, vec2 center, float terrain_size) {
	float rd = distance(pos, center);
	float sd = squareish_distance(pos, center, terrain_size * 0.1, terrain_size);
	return mix(rd, sd, u_island_shape);
}

// pos is in terrain space
float get_height(vec2 pos) {
	float h = 0.0;
	
	{
		// Noise (0..1)
		// Offset and scale for the noise itself
		vec2 uv_noise = (pos / u_terrain_size + u_offset) * u_scale;
		h = 0.5 + 0.5 * get_fractal_noise(uv_noise);
	}
	
	// Curve
	{
		h = pow(h, u_curve);
	}
	
	// Island
	{
		float terrain_size = u_terrain_size;
		vec2 island_center = vec2(0.5 * terrain_size);
		float island_height_ratio = 0.5 + 0.5 * u_island_height_ratio;
		float island_distance = get_island_distance(pos, island_center, terrain_size);
		float distance_ratio = clamp(island_distance / (0.5 * terrain_size), 0.0, 1.0);
		float island_ratio = u_island_weight * get_island_curve(distance_ratio);
		h = mix(h, island_height_ratio, island_ratio);
	}

	// Height remapping
	{
		h = u_base_height + h * u_height_range;
	}
	
	// Additive heightmap
	{
		h += u_additive_heightmap_factor * texture(u_additive_heightmap, pos / u_terrain_size).r;
	}
	
	return h;
}

void fragment() {
	// Handle screen padding: transform UV back into generation space.
	// This is in tile space actually...? it spans 1 unit across the viewport,
	// and starts from 0 when tile (0,0) is generated.
	// Maybe we could change this into world units instead?
	vec2 uv_tile = (SCREEN_UV + u_uv_offset) * u_uv_scale;

	float h = get_height(uv_tile * u_tile_size);
	
	COLOR = vec4(h, h, h, 1.0);
}
