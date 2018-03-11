
#include "height_map_mesher.h"
#include "util/macros.h"
#include "util/pod_vector.h"

using namespace godot;

static void copy_to(PoolIntArray &to, PodVector<int> &from) {

	to.resize(from.size());

	PoolIntArray::Write w = to.write();

	for (int i = 0; i < from.size(); ++i) {
		w[i] = from[i];
	}
}


HeightMapMesher::HeightMapMesher() {
	_mesh_cache_size = 0;
}

void HeightMapMesher::configure(Point2i chunk_size, int lod_count) {
	ERR_FAIL_COND(chunk_size.x < 2 || chunk_size.y < 2);
	ERR_FAIL_COND(lod_count >= MAX_LODS);

	if(chunk_size == _chunk_size && lod_count == _mesh_cache_size)
		return;

	_chunk_size = chunk_size;

	// TODO Will reduce the size of this cache, but need index buffer swap feature
	for(int seams = 0; seams < SEAM_CONFIG_COUNT; ++seams) {
		//_mesh_cache[seams].resize(lod_count);
		_mesh_cache_size = lod_count;
		for(int lod = 0; lod < lod_count; ++lod) {
			_mesh_cache[seams][lod] = make_flat_chunk(_chunk_size, 1 << lod, seams);
		}
	}
}

Ref<ArrayMesh> HeightMapMesher::get_chunk(int lod, int seams) {
	return _mesh_cache[seams][lod];
}

godot::Ref<ArrayMesh> HeightMapMesher::make_flat_chunk(Point2i chunk_size, int stride, int seams) {

	PoolVector3Array positions;
	positions.resize((chunk_size.x+1) * (chunk_size.y+1));

	{
		Point2i pos;
		int i = 0;
		PoolVector3Array::Write w = positions.write();

		for (pos.y = 0; pos.y <= chunk_size.y; ++pos.y) {
			for (pos.x = 0; pos.x <= chunk_size.x; ++pos.x) {
				w[i] = Vector3(pos.x * stride, 0, pos.y * stride);
				++i;
			}
		}
	}

	PoolIntArray indices = make_indices(chunk_size, seams);

	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = positions;
	arrays[Mesh::ARRAY_INDEX] = indices;

	Ref<ArrayMesh> mesh_ref(memnew(ArrayMesh));
	mesh_ref->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);

	return mesh_ref;
}

// size: chunk size in quads (there are N+1 vertices)
// seams: Bitfield for which seams are present
PoolIntArray HeightMapMesher::make_indices(Point2i chunk_size, unsigned int seams) {

	PodVector<int> output_indices;

	// LOD seams can't be made properly on uneven chunk sizes
	ERR_FAIL_COND_V(chunk_size.x % 2 != 0 || chunk_size.y % 2 != 0, PoolIntArray());

	Point2i reg_origin;
	Point2i reg_size = chunk_size;
	int reg_hstride = 1;

	if(seams & SEAM_LEFT) {
		reg_origin.x += 1;
		reg_size.x -= 1;
		++reg_hstride;
	}
	if(seams & SEAM_BOTTOM) {
		reg_origin.y += 1;
		reg_size.y -= 1;
	}
	if(seams & SEAM_RIGHT) {
		reg_size.x -= 1;
		++reg_hstride;
	}
	if(seams & SEAM_TOP) {
		reg_size.y -= 1;
	}

	// Regular triangles
	int i = reg_origin.x + reg_origin.y * (chunk_size.x + 1);
	Point2i pos;
	for (pos.y = 0; pos.y < reg_size.y; ++pos.y) {
		for (pos.x = 0; pos.x < reg_size.x; ++pos.x) {

			int i00 = i;
			int i10 = i + 1;
			int i01 = i + chunk_size.x + 1;
			int i11 = i01 + 1;

			// 01---11
			//  |  /|
			//  | / |
			//  |/  |
			// 00---10

			// This flips the pattern to make the geometry orientation-free.
			// Not sure if it helps in any way though
			bool flip = ((pos.x + reg_origin.x) + (pos.y + reg_origin.y) % 2) % 2 != 0;

			if(flip) {

				output_indices.push_back( i00 );
				output_indices.push_back( i10 );
				output_indices.push_back( i01 );

				output_indices.push_back( i10 );
				output_indices.push_back( i11 );
				output_indices.push_back( i01 );

			} else {
				output_indices.push_back( i00 );
				output_indices.push_back( i11 );
				output_indices.push_back( i01 );

				output_indices.push_back( i00 );
				output_indices.push_back( i10 );
				output_indices.push_back( i11 );
			}

			++i;
		}
		i += reg_hstride;
	}

	// Left seam
	if(seams & SEAM_LEFT) {

		//     4 . 5
		//     |\  .
		//     | \ .
		//     |  \.
		//  (2)|   3
		//     |  /.
		//     | / .
		//     |/  .
		//     0 . 1

		int i = 0;
		int n = chunk_size.y / 2;

		for(int j = 0; j < n; ++j) {

			int i0 = i;
			int i1 = i + 1;
			int i3 = i + chunk_size.x + 2;
			int i4 = i + 2 * (chunk_size.x + 1);
			int i5 = i4 + 1;

			output_indices.push_back( i0 );
			output_indices.push_back( i3 );
			output_indices.push_back( i4 );

			if(j != 0 || (seams & SEAM_BOTTOM) == 0) {
				output_indices.push_back( i0 );
				output_indices.push_back( i1 );
				output_indices.push_back( i3 );
			}

			if(j != n-1 || (seams & SEAM_TOP) == 0) {
				output_indices.push_back( i3 );
				output_indices.push_back( i5 );
				output_indices.push_back( i4 );
			}

			i = i4;
		}
	}

	if(seams & SEAM_RIGHT) {

		//     4 . 5
		//     .  /|
		//     . / |
		//     ./  |
		//     2   |(3)
		//     .\  |
		//     . \ |
		//     .  \|
		//     0 . 1

		int i = chunk_size.x - 1;
		int n = chunk_size.y / 2;

		for(int j = 0; j < n; ++j) {

			int i0 = i;
			int i1 = i + 1;
			int i2 = i + chunk_size.x + 1;
			int i4 = i + 2 * (chunk_size.x + 1);
			int i5 = i4 + 1;

			output_indices.push_back( i1 );
			output_indices.push_back( i5 );
			output_indices.push_back( i2 );

			if(j != 0 || (seams & SEAM_BOTTOM) == 0) {
				output_indices.push_back( i0 );
				output_indices.push_back( i1 );
				output_indices.push_back( i2 );
			}

			if(j != n-1 || (seams & SEAM_TOP) == 0) {
				output_indices.push_back( i2 );
				output_indices.push_back( i5 );
				output_indices.push_back( i4 );
			}

			i = i4;
		}
	}

	if(seams & SEAM_BOTTOM) {

		//  3 . 4 . 5
		//  .  / \  .
		//  . /   \ .
		//  ./     \.
		//  0-------2
		//     (1)

		int i = 0;
		int n = chunk_size.x / 2;

		for(int j = 0; j < n; ++j) {

			int i0 = i;
			int i2 = i + 2;
			int i3 = i + chunk_size.x + 1;
			int i4 = i3 + 1;
			int i5 = i4 + 1;

			output_indices.push_back( i0 );
			output_indices.push_back( i2 );
			output_indices.push_back( i4 );

			if(j != 0 || (seams & SEAM_LEFT) == 0) {
				output_indices.push_back( i0 );
				output_indices.push_back( i4 );
				output_indices.push_back( i3 );
			}

			if(j != n-1 || (seams & SEAM_RIGHT) == 0) {
				output_indices.push_back( i2 );
				output_indices.push_back( i5 );
				output_indices.push_back( i4 );
			}

			i = i2;
		}
	}

	if(seams & SEAM_TOP) {

		//     (4)
		//  3-------5
		//  .\     /.
		//  . \   / .
		//  .  \ /  .
		//  0 . 1 . 2

		int i = (chunk_size.y - 1) * (chunk_size.x + 1);
		int n = chunk_size.x / 2;

		for(int j = 0; j < n; ++j) {

			int i0 = i;
			int i1 = i + 1;
			int i2 = i + 2;
			int i3 = i + chunk_size.x + 1;
			int i5 = i3 + 2;

			output_indices.push_back( i3 );
			output_indices.push_back( i1 );
			output_indices.push_back( i5 );

			if(j != 0 || (seams & SEAM_LEFT) == 0) {
				output_indices.push_back( i0 );
				output_indices.push_back( i1 );
				output_indices.push_back( i3 );
			}

			if(j != n-1 || (seams & SEAM_RIGHT) == 0) {
				output_indices.push_back( i1 );
				output_indices.push_back( i2 );
				output_indices.push_back( i5 );
			}

			i = i2;
		}
	}

	PoolIntArray indices;
	copy_to(indices, output_indices);
	return indices;
}

