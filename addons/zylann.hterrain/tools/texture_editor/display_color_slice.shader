shader_type canvas_item;

uniform sampler2DArray u_texture_array;
uniform float u_index;

void fragment() {
	vec4 col = texture(u_texture_array, vec3(UV.x, UV.y, u_index));
	COLOR = vec4(col.rgb, 1.0);
}
