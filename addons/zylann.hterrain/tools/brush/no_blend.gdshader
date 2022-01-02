shader_type canvas_item;
render_mode blend_disabled;

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
