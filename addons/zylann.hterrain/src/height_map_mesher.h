#ifndef HEIGHT_MAP_MESHER_H
#define HEIGHT_MAP_MESHER_H

#include <core/Ref.hpp>
#include <core/PoolArrays.hpp>
#include <Mesh.hpp>
#include <ArrayMesh.hpp>

#include "util/point2i.h"

class HeightMapMesher {

public:
	enum SeamFlag {
		SEAM_LEFT = 1,
		SEAM_RIGHT = 2,
		SEAM_BOTTOM = 4,
		SEAM_TOP = 8,
		SEAM_CONFIG_COUNT = 16
	};

	HeightMapMesher();

	void configure(Point2i chunk_size, int lod_count);
	godot::Ref<godot::ArrayMesh> get_chunk(int lod, int seams);

private:
	void precalculate();
	godot::Ref<godot::ArrayMesh> make_flat_chunk(Point2i chunk_size, int stride, int seams);
	godot::PoolIntArray make_indices(Point2i chunk_size, unsigned int seams);

private:
	// TODO This is an internal limit. Need vector for non-POD types heh
	static const size_t MAX_LODS = 16;

	// [seams_mask][lod]
	godot::Ref<godot::ArrayMesh> _mesh_cache[SEAM_CONFIG_COUNT][MAX_LODS];
	int _mesh_cache_size;
	Point2i _chunk_size;
};

#endif // HEIGHT_MAP_MESHER_H
