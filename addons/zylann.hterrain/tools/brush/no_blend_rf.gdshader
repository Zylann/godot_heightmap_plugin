shader_type canvas_item;
render_mode blend_disabled;

#include "res://addons/zylann.hterrain/shaders/include/heightmap.gdshaderinc"

void fragment() {
	float h = sample_heightmap(TEXTURE, UV);
	COLOR = encode_height_to_viewport(h);
}
