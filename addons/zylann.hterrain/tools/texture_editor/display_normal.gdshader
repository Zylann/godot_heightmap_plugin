shader_type canvas_item;

uniform float u_strength = 1.0;
uniform bool u_flip_y = false;

vec3 unpack_normal(vec4 rgba) {
	vec3 n = rgba.xzy * 2.0 - vec3(1.0);
	// Had to negate Z because it comes from Y in the normal map,
	// and OpenGL-style normal maps are Y-up.
	n.z *= -1.0;
	return n;
}

vec3 pack_normal(vec3 n) {
	n.z *= -1.0;
	return 0.5 * (n.xzy + vec3(1.0));
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	vec3 n = unpack_normal(col);
	n = normalize(mix(n, vec3(-n.x, n.y, -n.z), 0.5 - 0.5 * u_strength));
	if (u_flip_y) {
		n.z = -n.z;
	}
	col.rgb = pack_normal(n);
	COLOR = vec4(col.rgb, 1.0);
}
