shader_type spatial;

// This shader is used to bake the global albedo map.
// It exposes a subset of the main shader API, so uniform names were not modified.

uniform sampler2D u_terrain_colormap : hint_albedo;
uniform sampler2D u_terrain_splatmap;

uniform sampler2D u_ground_albedo_bump_0 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_1 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_2 : hint_albedo;
uniform sampler2D u_ground_albedo_bump_3 : hint_albedo;

// Keep depth blending because it has a high effect on the final result
uniform bool u_depth_blending = true;
uniform float u_ground_uv_scale = 20.0;


vec4 get_depth_blended_weights(vec4 splat, vec4 bumps) {
	float dh = 0.2;

	vec4 h = bumps + splat;
	
	h *= smoothstep(0, 0.05, splat);
	
	vec4 d = h + dh;
	d.r -= max(h.g, max(h.b, h.a));
	d.g -= max(h.r, max(h.b, h.a));
	d.b -= max(h.g, max(h.r, h.a));
	d.a -= max(h.g, max(h.b, h.r));
	
	return clamp(d, 0, 1);
}

void vertex() {
	vec4 wpos = WORLD_MATRIX * vec4(VERTEX, 1);
	vec2 cell_coords = wpos.xz;
	// Must add a half-offset so that we sample the center of pixels,
	// otherwise bilinear filtering of the textures will give us mixed results (#183)
	cell_coords += vec2(0.5);

	// Normalized UV
	UV = (cell_coords / vec2(textureSize(u_terrain_splatmap, 0)));
}

void fragment() {
	// These were moved from vertex to fragment,
	// so we can generate part of the global map with just one quad and we get full quality
	vec4 tint = texture(u_terrain_colormap, UV);
	vec4 splat = texture(u_terrain_splatmap, UV);

	// Get bump at normal resolution so depth blending is accurate
	vec2 ground_uv = UV / u_ground_uv_scale;
	float b0 = texture(u_ground_albedo_bump_0, ground_uv).a;
	float b1 = texture(u_ground_albedo_bump_1, ground_uv).a;
	float b2 = texture(u_ground_albedo_bump_2, ground_uv).a;
	float b3 = texture(u_ground_albedo_bump_3, ground_uv).a;

	// Take the center of the highest mip as color, because we can't see details from far away.
	vec2 ndc_center = vec2(0.5, 0.5);
	vec3 col0 = textureLod(u_ground_albedo_bump_0, ndc_center, 10.0).rgb;
	vec3 col1 = textureLod(u_ground_albedo_bump_1, ndc_center, 10.0).rgb;
	vec3 col2 = textureLod(u_ground_albedo_bump_2, ndc_center, 10.0).rgb;
	vec3 col3 = textureLod(u_ground_albedo_bump_3, ndc_center, 10.0).rgb;
	
	vec4 w;
	if (u_depth_blending) {
		w = get_depth_blended_weights(splat, vec4(b0, b1, b2, b3));
	} else {
		w = splat.rgba;
	}
	
	float w_sum = (w.r + w.g + w.b + w.a);
	
	ALBEDO = tint.rgb * (
		w.r * col0 + 
		w.g * col1 + 
		w.b * col2 + 
		w.a * col3) / w_sum;
}

