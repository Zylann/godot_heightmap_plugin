#include "height_map.h"

void HeightMap::_register_methods() {

	godot::register_method("get_data", &HeightMap::get_data);
}

void HeightMap::_init() {

	data = "Hello World from C++";
}

godot::String HeightMap::get_data() const {

	return data;
}
