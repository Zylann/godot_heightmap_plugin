#include <VisualServer.hpp>
#include <World.hpp>

#include "height_map_chunk.h"

using namespace godot;


HeightMapChunk::HeightMapChunk(Spatial *p_parent, Point2i p_cell_pos, Ref<Material> p_material) {
	cell_origin = p_cell_pos;

	_mesh_instance = VisualServer::instance_create();

	parent_transform_changed(p_parent->get_global_transform());

	if (p_material.is_valid()) {
		VisualServer::instance_geometry_set_material_override(_mesh_instance, p_material->get_rid());
	}

	Ref<World> world = p_parent->get_world();
	if (world.is_valid()) {
		VisualServer::instance_set_scenario(_mesh_instance, world->get_scenario());
	}

	// TODO Is this needed?
	VisualServer::instance_set_visible(_mesh_instance, true);

	_visible = true;
	_active = true;
	_pending_update = false;

//	++s_chunk_count;
//	print_line(String("Chunk count: ") + String::num(s_chunk_count));
}

HeightMapChunk::~HeightMapChunk() {
	Godot::print("~HeightMapChunk");
	if (_mesh_instance.is_valid()) {
		Godot::print("Free rid");
		VisualServer::free_rid(_mesh_instance);
		_mesh_instance = RID();
	}
	//	if(collider)
	//		collider->queue_delete();
//	--s_chunk_count;
//	print_line(String("Chunk count: ") + String::num(s_chunk_count));
}

void HeightMapChunk::enter_world(World &world) {
	ERR_FAIL_COND(_mesh_instance.is_valid() == false);
	VisualServer::instance_set_scenario(_mesh_instance, world.get_scenario());
}

void HeightMapChunk::exit_world() {
	ERR_FAIL_COND(_mesh_instance.is_valid() == false);
	VisualServer::instance_set_scenario(_mesh_instance, RID());
}

void HeightMapChunk::parent_transform_changed(const Transform &parent_transform) {
	ERR_FAIL_COND(_mesh_instance.is_valid() == false);
	Transform local_transform(Basis(), Vector3(cell_origin.x, 0, cell_origin.y));
	Transform world_transform = parent_transform * local_transform;
	VisualServer::instance_set_transform(_mesh_instance, world_transform);
}

void HeightMapChunk::set_mesh(Ref<ArrayMesh> mesh) {
	ERR_FAIL_COND(_mesh_instance.is_valid() == false);
	if(mesh == _mesh)
		return;
	VisualServer::instance_set_base(_mesh_instance, mesh.is_valid() ? mesh->get_rid() : RID());
	_mesh = mesh;
}

void HeightMapChunk::set_material(Ref<Material> material) {
	ERR_FAIL_COND(_mesh_instance.is_valid() == false);
	VisualServer::instance_geometry_set_material_override(_mesh_instance, material.is_valid() ? material->get_rid() : RID());
}

void HeightMapChunk::set_visible(bool visible) {
	ERR_FAIL_COND(_mesh_instance.is_valid() == false);
	VisualServer::instance_set_visible(_mesh_instance, visible);
}

void HeightMapChunk::set_aabb(AABB aabb) {
	ERR_FAIL_COND(_mesh_instance.is_valid() == false);
	VisualServer::instance_set_custom_aabb(_mesh_instance, aabb);
}
