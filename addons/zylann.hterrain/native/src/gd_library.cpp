#include "image_utils.h"
#include "quad_tree_lod.h"

extern "C" {

void GDN_EXPORT godot_gdnative_init(godot_gdnative_init_options *o) {
#ifdef _DEBUG
    printf("godot_gdnative_init hterrain_native\n");
#endif
    godot::Godot::gdnative_init(o);
}

void GDN_EXPORT godot_gdnative_terminate(godot_gdnative_terminate_options *o) {
#ifdef _DEBUG
    printf("godot_gdnative_terminate hterrain_native\n");
#endif
    godot::Godot::gdnative_terminate(o);
}

void GDN_EXPORT godot_nativescript_init(void *handle) {
#ifdef _DEBUG
    printf("godot_nativescript_init hterrain_native\n");
#endif
    godot::Godot::nativescript_init(handle);

    godot::register_tool_class<godot::ImageUtils>();
    godot::register_tool_class<godot::QuadTreeLod>();
}

} // extern "C"
