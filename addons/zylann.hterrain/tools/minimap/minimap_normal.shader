shader_type canvas_item;

uniform sampler2D u_normalmap;
uniform vec3 u_light_direction = vec3(0.5, -0.7, 0.2);

vec3 unpack_normal(vec4 rgba) {
	return rgba.xzy * 2.0 - vec3(1.0);
}

void fragment() {
	vec3 normal = unpack_normal(texture(u_normalmap, UV));
	float g = max(-dot(u_light_direction, normal), 0.0);
	g *= 0.7;
	COLOR = vec4(g, g, g, 1.0);
}

