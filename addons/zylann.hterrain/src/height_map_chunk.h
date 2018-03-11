#ifndef HEIGHT_MAP_CHUNK_H
#define HEIGHT_MAP_CHUNK_H

#include <Spatial.hpp>
#include <Material.hpp>
#include <ArrayMesh.hpp>
#include <core/Ref.hpp>
#include <core/Transform.hpp>
#include <core/RID.hpp>

#include "util/point2i.h"

// Container for chunk objects
class HeightMapChunk {
public:
	Point2i cell_origin;

	HeightMapChunk(godot::Spatial *p_parent, Point2i p_cell_pos, godot::Ref<godot::Material> p_material);
	~HeightMapChunk();

	void set_mesh(godot::Ref<godot::ArrayMesh> mesh);
	void clear();
	void set_material(godot::Ref<godot::Material> material);
	void enter_world(godot::World &world);
	void exit_world();
	void parent_transform_changed(const godot::Transform &parent_transform);

	void set_visible(bool visible);
	bool is_visible() const { return _visible; }

	void set_active(bool p_active) { _active = p_active; }
	bool is_active() const { return _active; }

	bool is_pending_update() const { return _pending_update; }
	void set_pending_update(bool pending_update) { _pending_update = pending_update; }

	void set_aabb(godot::AABB aabb);

private:
	bool _visible;
	bool _active;
	bool _pending_update;

	godot::RID _mesh_instance;
	// Need to keep a reference so that the mesh RID doesn't get freed
	// TODO Use RID directly, no need to keep all those meshes in memory
	godot::Ref<godot::ArrayMesh> _mesh;
};

#endif // HEIGHT_MAP_CHUNK_H
