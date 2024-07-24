#include <godot_cpp/godot.hpp>
#include "image_utils.h"
#include "quad_tree_lod.h"

 using namespace godot;

void godot_gdextension_initialize(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
#ifdef _DEBUG
    printf("godot_gdnative_init hterrain_native\n");
#endif
    ClassDB::register_class<ImageUtils>();
    ClassDB::register_class<QuadTreeLod>();
}

void godot_gdextension_terminate(ModuleInitializationLevel p_level) {
    	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
#ifdef _DEBUG
    printf("godot_gdnative_terminate hterrain_native\n");
#endif
    // todo: unregister classes, if possible...
}

extern "C"{
GDExtensionBool GDE_EXPORT terrain_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
#ifdef _DEBUG
    printf("godot_nativescript_init hterrain_native\n");
#endif
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(godot_gdextension_initialize);
	init_obj.register_terminator(godot_gdextension_terminate);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}

} // extern "C"
