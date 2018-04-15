shader_type canvas_item;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	COLOR = vec4(col.rgb, 1.0);
}
