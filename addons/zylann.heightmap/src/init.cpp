#include <core/Godot.hpp>

#include "height_map.h"

extern "C" void godot_gdnative_init(godot_gdnative_init_options *o) {

	godot::Godot::gdnative_init(o);
}

extern "C" void godot_gdnative_terminate(godot_gdnative_terminate_options *o) {

	godot::Godot::gdnative_terminate(o);
}

extern "C" void godot_nativescript_init(void *handle) {

	godot::Godot::nativescript_init(handle);

	godot::register_class<HeightMap>();
}
