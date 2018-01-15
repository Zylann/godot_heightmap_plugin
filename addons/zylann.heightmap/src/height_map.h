#ifndef HEIGHT_MAP_H
#define HEIGHT_MAP_H

#include <core/Godot.hpp>
#include <Reference.hpp>

class HeightMap : public godot::GodotScript<godot::Reference> {
	GODOT_CLASS(HeightMap)

public:
	static void _register_methods();

	void _init();

	godot::String get_data() const;

private:
	godot::String data;
};

#endif // HEIGHT_MAP_H
