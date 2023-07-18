shader_type canvas_item;

void fragment() {
	float a = texture(TEXTURE, UV).a;
	COLOR = vec4(a, a, a, 1.0);
}
