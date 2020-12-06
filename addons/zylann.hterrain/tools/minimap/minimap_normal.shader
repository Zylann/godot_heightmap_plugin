shader_type canvas_item;

uniform sampler2D u_normalmap;
uniform sampler2D u_globalmap;
uniform vec3 u_light_direction = vec3(0.5, -0.7, 0.2);

vec3 unpack_normal(vec4 rgba) {
	return rgba.xzy * 2.0 - vec3(1.0);
}

void fragment() {
	vec3 albedo = texture(u_globalmap, UV).rgb;
	// Undo sRGB
	// TODO I don't know what is correct tbh, this didn't work well
	//albedo *= pow(albedo, vec3(0.4545));
	//albedo *= pow(albedo, vec3(1.0 / 0.4545));
	albedo = sqrt(albedo);
	
	vec3 normal = unpack_normal(texture(u_normalmap, UV));
	float g = max(-dot(u_light_direction, normal), 0.0);
	
	COLOR = vec4(albedo * g, 1.0);
}

