shader_type canvas_item;

uniform bool u_invert; // If true, will "inflate" terrain rather than carve it
uniform bool u_moore; // If true, 8-ways blur will be used instead of 4-ways.
uniform bool u_slope = true; // Take slope into account

vec3 get_cell(sampler2D sampler, vec2 uv) {
	return vec3(uv.x, texture(sampler, uv).r, uv.y);
}

vec4 get_corners(sampler2D sampler, vec2 uv, vec2 ps) {
	vec3 left_top = get_cell(sampler, uv + vec2(-ps.x, ps.y));
	vec3 right_top = get_cell(sampler, uv + ps);
	vec3 left_bottom = get_cell(sampler, uv - ps);
	vec3 right_bottom = get_cell(sampler, uv + vec2(ps.x, -ps.y));
	return vec4(left_top.y, right_top.y, left_bottom.y, right_bottom.y);
}

void fragment() {
	//float force_update_canvas = TIME;
	vec2 ps = SCREEN_PIXEL_SIZE;
	vec2 uv = SCREEN_UV;
	
	vec3 pos = get_cell(SCREEN_TEXTURE, uv);
	
	vec3 left = get_cell(SCREEN_TEXTURE, uv + vec2(-ps.x, 0.0));
	vec3 right = get_cell(SCREEN_TEXTURE, uv + vec2(ps.x, 0.0));
	vec3 top = get_cell(SCREEN_TEXTURE, uv + vec2(0.0, ps.y));
	vec3 bottom = get_cell(SCREEN_TEXTURE, uv + vec2(0.0, -ps.y));
	
	float count = 1.0;
	float sum = pos.y;
	float result;
	
	vec4 edges = vec4(left.y, right.y, top.y, bottom.y);
	
	if (u_invert) {
		vec4 comparison = vec4(greaterThan(edges, vec4(pos.y)));
		count += dot(comparison, comparison);
		sum += dot(comparison, edges);
		
		if (u_moore) {
			vec4 corners = get_corners(SCREEN_TEXTURE, uv, ps);
			comparison = vec4(greaterThan(corners, vec4(pos.y)));
			count += dot(comparison, comparison);
			sum += dot(comparison, corners);
		}
	} else {
		vec4 comparison = vec4(lessThan(edges, vec4(pos.y)));
		count += dot(comparison, comparison);
		sum += dot(comparison, edges);
		
		if (u_moore) {
			vec4 corners = get_corners(SCREEN_TEXTURE, uv, ps);
			comparison = vec4(lessThan(corners, vec4(pos.y)));
			count += dot(comparison, comparison);
			sum += dot(comparison, corners);
		}
	}
	
	if (u_slope) {
		vec3 normal = normalize(vec3(left.y - right.y, ps.x + ps.y, bottom.y - top.y));
		float factor = dot(normal, vec3(0.0, 1.0, 0.0));
		factor = factor - 0.1 * count;
		result = mix(sum / count, pos.y, factor);
	} else {
		result = sum / count;
	}
	
	COLOR = vec4(result, result, result, 1.0);
}
