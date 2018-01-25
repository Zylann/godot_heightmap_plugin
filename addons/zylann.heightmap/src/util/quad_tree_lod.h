#ifndef QUAD_TREE_LOD_H
#define QUAD_TREE_LOD_H

#include <core/Vector3.hpp>
#include <core/Godot.hpp>

#include "point2i.h"
#include "macros.h"

// Independent quad tree designed to handle LOD
template <typename T>
class QuadTreeLod {

private:
	struct Node {
		Node *children[4];
		Point2i origin;

		// Userdata.
		// Note: the tree doesn't own this field,
		// if it's a pointer make sure you free it when you don't need it anymore,
		// using the recycling callback
		T chunk;

		Node() {
			chunk = T();
			for (int i = 0; i < 4; ++i) {
				children[i] = NULL;
			}
		}

		~Node() {
			clear_children();
		}

		void clear() {
			clear_children();
			chunk = T();
		}

		void clear_children() {
			if (has_children()) {
				for (int i = 0; i < 4; ++i) {
					memdelete(children[i]);
					children[i] = NULL;
				}
			}
		}

		bool has_children() {
			return children[0] != NULL;
		}
	};

public:
	// TODO There could be a way to get rid of those filthy void*
	typedef T (*MakeFunc)(void *context, Point2i origin, int lod);
	typedef void (*QueryFunc)(void *context, T chunk, Point2i origin, int lod);
	typedef QueryFunc RecycleFunc;

	QuadTreeLod() {

		_max_depth = 0;
		_base_size = 0;
		_split_scale = 2;

		_callbacks_context = NULL;
		_make_func = NULL;
		_recycle_func = NULL;
	}

	void set_callbacks(MakeFunc make_cb, RecycleFunc recycle_cb, void *context) {
		_make_func = make_cb;
		_recycle_func = recycle_cb;
		_callbacks_context = context;
	}

	void clear() {
		join_recursively(_tree, _max_depth);

		_tree.clear_children();

		_max_depth = 0;
		_base_size = 0;
	}

	int compute_lod_count(int base_size, int full_size) {
		int po = 0;
		while (full_size > base_size) {
			full_size = full_size >> 1;
			++po;
		}
		return po;
	}

	void create_from_sizes(int base_size, int full_size) {

		clear();
		_base_size = base_size;
		_max_depth = compute_lod_count(base_size, full_size);
	}

	inline int get_lod_count() const {
		// TODO _max_depth is a maximum, not a count. Would be better for it to be a count (+1)
		return _max_depth + 1;
	}

	// The higher, the longer LODs will spread and higher the quality.
	// The lower, the shorter LODs will spread and lower the quality.
	void set_split_scale(float p_split_scale) {
		const float min = 2.0;
		const float max = 5.0;

		// Split scale must be greater than a threshold,
		// otherwise lods will decimate too fast and it will look messy
		if (p_split_scale < min)
			p_split_scale = min;
		if (p_split_scale > max)
			p_split_scale = max;

		_split_scale = p_split_scale;
	}

	inline float get_split_scale() const {
		return _split_scale;
	}

	void update(godot::Vector3 viewer_pos) {
		update_nodes_recursive(_tree, _max_depth, viewer_pos);
		make_chunks_recursively(_tree, _max_depth);
	}

	// TODO Should be renamed get_lod_factor
	inline int get_lod_size(int lod) const {
		return 1 << lod;
	}

	inline int get_split_distance(int lod) const {
		return _base_size * get_lod_size(lod) * _split_scale;
	}

private:
	T make_chunk(int lod, Point2i origin) {
		T chunk = T();
		if (_make_func) {
			chunk = _make_func(_callbacks_context, origin, lod);
		}
		return chunk;
	}

	void recycle_chunk(T chunk, Point2i origin, int lod) {
		if (_recycle_func)
			_recycle_func(_callbacks_context, chunk, origin, lod);
	}

	void join_recursively(Node &node, int lod) {
		if (node.has_children()) {
			for (int i = 0; i < 4; ++i) {
				Node *child = node.children[i];
				join_recursively(*child, lod - 1);
			}
			node.clear_children();
		} else if (node.chunk) {
			recycle_chunk(node.chunk, node.origin, lod);
			node.chunk = T();
		}
	}

	void update_nodes_recursive(Node &node, int lod, godot::Vector3 viewer_pos) {
		//print_line(String("update_nodes_recursive lod={0}, o={1}, {2} ").format(varray(lod, node.origin.x, node.origin.y)));

		int lod_size = get_lod_size(lod);
		godot::Vector3 world_center = (_base_size * lod_size) * (godot::Vector3(node.origin.x, 0, node.origin.y) + godot::Vector3(0.5, 0, 0.5));
		real_t split_distance = get_split_distance(lod);

		if (node.has_children()) {
			// Test if it should be joined
			// TODO Distance should take the chunk's Y dimension into account
			if (world_center.distance_to(viewer_pos) > split_distance) {
				join_recursively(node, lod);
			}

		} else if (lod > 0) {
			// Test if it should split
			if (world_center.distance_to(viewer_pos) < split_distance) {
				// Split

				for (int i = 0; i < 4; ++i) {
					Node *child = memnew(Node);
					Point2i origin = node.origin * 2 + Point2i(i & 1, (i & 2) >> 1);
					child->origin = origin;
					node.children[i] = child;
				}

				if (node.chunk) {
					recycle_chunk(node.chunk, node.origin, lod);
				}

				node.chunk = T();
			}
		}

		// TODO This will check all chunks every frame,
		// we could find a way to recursively update chunks as they get joined/split,
		// but in C++ that would be not even needed.
		if (node.has_children()) {
			for (int i = 0; i < 4; ++i) {
				update_nodes_recursive(*node.children[i], lod - 1, viewer_pos);
			}
		}
	}

	void make_chunks_recursively(Node &node, int lod) {
		assert(lod >= 0);
		if (node.has_children()) {
			for (int i = 0; i < 4; ++i) {
				Node *child = node.children[i];
				make_chunks_recursively(*child, lod - 1);
			}
		} else {
			if (!node.chunk) {
				node.chunk = make_chunk(lod, node.origin);
				// Note: if you don't return anything here,
				// make_chunk will continue being called
			}
		}
	}

private:
	Node _tree;
	int _max_depth;
	int _base_size;
	float _split_scale;

	MakeFunc _make_func;
	RecycleFunc _recycle_func;
	void *_callbacks_context;
};

#endif // QUAD_TREE_LOD_H
