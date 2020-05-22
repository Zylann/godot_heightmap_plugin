shader_type canvas_item;

void fragment() {
	// TODO Have an option to "undo" sRGB, for funzies?
	vec4 col = texture(TEXTURE, UV);
	COLOR = vec4(col.rgb, 1.0);
}
