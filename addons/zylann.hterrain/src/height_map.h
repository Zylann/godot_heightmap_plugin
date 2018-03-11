#ifndef HEIGHT_MAP_H
#define HEIGHT_MAP_H

#include <core/Godot.hpp>
#include <core/Ref.hpp>
#include <Spatial.hpp>
#include <ShaderMaterial.hpp>

#include "height_map_mesher.h"
#include "height_map_data.h"
#include "height_map_chunk.h"
#include "util/quad_tree_lod.h"
#include "util/pod_grid.h"

class HeightMap : public godot::GodotScript<godot::Spatial> {
	GODOT_CLASS(HeightMap)

public:
	static void _register_methods();

	static const int CHUNK_SIZE = 16;

	static const char *SHADER_PARAM_HEIGHT_TEXTURE;
	static const char *SHADER_PARAM_NORMAL_TEXTURE;
	static const char *SHADER_PARAM_COLOR_TEXTURE;
	static const char *SHADER_PARAM_SPLAT_TEXTURE;
	static const char *SHADER_PARAM_MASK_TEXTURE;
	static const char *SHADER_PARAM_RESOLUTION;
	static const char *SHADER_PARAM_INVERSE_TRANSFORM;

	HeightMap();
	~HeightMap();

	void _init();

	void set_data(godot::Ref<godot::Resource> new_data_ref);
	godot::Ref<godot::Resource> get_data() const;

	void set_custom_material(godot::Ref<godot::ShaderMaterial> p_material);
	inline godot::Ref<godot::ShaderMaterial> get_custom_material() const { return _custom_material; }

	void set_collision_enabled(bool enabled);
	inline bool is_collision_enabled() const { return _collision_enabled; }

	void set_lod_scale(float lod_scale);
	float get_lod_scale() const;

	void set_area_dirty(Point2i origin_in_cells, Point2i size_in_cells);
	bool cell_raycast(godot::Vector3 origin_world, godot::Vector3 dir_world, Point2i &out_cell_pos);

	static void init_default_resources();
	static void free_default_resources();

	godot::Vector3 _manual_viewer_pos;

protected:
	void _notification(int p_what);

private:
	void _process();

	void update_material();
	void update_material_params();

	HeightMapChunk *_make_chunk_cb(Point2i cpos, int lod);
	void _recycle_chunk_cb(HeightMapChunk *chunk);

	void add_chunk_update(HeightMapChunk &chunk, Point2i pos, int lod);
	void update_chunk(HeightMapChunk &chunk, int lod);

	Point2i local_pos_to_cell(godot::Vector3 local_pos) const;

	void _on_data_resolution_changed();
	void _on_data_region_changed(int min_x, int min_y, int max_x, int max_y, int channel);

	void clear_all_chunks();

	HeightMapChunk *get_chunk_at(Point2i pos, int lod) const;

	static HeightMapChunk *s_make_chunk_cb(void *context, Point2i origin, int lod);
	static void s_recycle_chunk_cb(void *context, HeightMapChunk *chunk, Point2i origin, int lod);

	inline bool has_data() const { return _data != nullptr; }

	template <typename Action_T>
	void for_all_chunks(Action_T action) {
		for(int lod = 0; lod < MAX_LODS; ++lod) {
			int area = _chunks[lod].area();
			for(int i = 0; i < area; ++i) {
				HeightMapChunk *chunk = _chunks[lod][i];
				if(chunk)
					action(*chunk);
			}
		}
	}

private:
	godot::Ref<godot::ShaderMaterial> _custom_material;
	godot::Ref<godot::ShaderMaterial> _material;
	bool _collision_enabled;

	// TODO Have a cleaner way to store this, as Ref<T> doesn't support custom classes
	godot::Ref<godot::Resource> _data_ref;
	HeightMapData *_data;

	HeightMapMesher _mesher;
	QuadTreeLod<HeightMapChunk *> _lodder;

	struct PendingChunkUpdate {
		Point2i pos;
		int lod;
		PendingChunkUpdate() : lod(0) {}
	};

	PodVector<PendingChunkUpdate> _pending_chunk_updates;

	// TODO Need non-POD vector
	static const unsigned int MAX_LODS = 16;

	// [lod][pos]
	// This container owns chunks, so will be used to free them
	PodGrid2D<HeightMapChunk*> _chunks[MAX_LODS];

	// Stats
	int _updated_chunks;
};

#endif // HEIGHT_MAP_H
