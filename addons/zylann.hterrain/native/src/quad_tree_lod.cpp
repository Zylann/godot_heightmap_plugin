#include "quad_tree_lod.h"

namespace godot {

void QuadTreeLod::set_callbacks(Ref<FuncRef> make_cb, Ref<FuncRef> recycle_cb, Ref<FuncRef> vbounds_cb) {
	_make_func = make_cb;
	_recycle_func = recycle_cb;
	_vertical_bounds_func = vbounds_cb;
}

int QuadTreeLod::get_lod_count() {
	// TODO make this a count, not max
	return _max_depth + 1;
}

int QuadTreeLod::get_lod_factor(int lod) {
	return 1 << lod;
}

int QuadTreeLod::compute_lod_count(int base_size, int full_size) {
	int po = 0;
	while (full_size > base_size) {
		full_size = full_size >> 1;
		po += 1;
	}
	return po;
}

// The higher, the longer LODs will spread and higher the quality.
// The lower, the shorter LODs will spread and lower the quality.
void QuadTreeLod::set_split_scale(real_t p_split_scale) {
	real_t MIN = 2.0f;
	real_t MAX = 5.0f;

	// Split scale must be greater than a threshold,
	// otherwise lods will decimate too fast and it will look messy
	if (p_split_scale < MIN)
		p_split_scale = MIN;
	if (p_split_scale > MAX)
		p_split_scale = MAX;

	_split_scale = p_split_scale;
}

real_t QuadTreeLod::get_split_scale() {
	return _split_scale;
}

void QuadTreeLod::clear() {
	_join_all_recursively(ROOT, _max_depth);
	_max_depth = 0;
	_base_size = 0;
}

void QuadTreeLod::create_from_sizes(int base_size, int full_size) {
	clear();
	_base_size = base_size;
	_max_depth = compute_lod_count(base_size, full_size);

	// Total qty of nodes is (N^L - 1) / (N - 1). -1 for root, where N=num children, L=levels including the root
	int node_count = ((static_cast<int>(pow(4, _max_depth+1)) - 1) / (4 - 1)) - 1;
	_node_pool.resize(node_count); // e.g. ((4^6 -1) / 3 ) - 1 = 1364 excluding root

	_free_indices.resize((node_count / 4)); // 1364 / 4 = 341
	for (int i = 0; i < _free_indices.size(); i++) // i = 0 to 340, *4 = 0 to 1360
		_free_indices[i] = 4 * i; // _node_pool[4*0 + i0] is first child, [4*340 + i3] is last
}

void QuadTreeLod::update(Vector3 view_pos) {
	_update(ROOT, _max_depth, view_pos);

	// This makes sure we keep seeing the lowest LOD,
	// if the tree is cleared while we are far away
	Quad *root = _get_root();
	if (!root->has_children() && root->is_null())
		root->set_data(_make_chunk(_max_depth, 0, 0));
}

void QuadTreeLod::debug_draw_tree(CanvasItem *ci) {
	if (ci != nullptr)
		_debug_draw_tree_recursive(ci, ROOT, _max_depth, 0);
}

// Intention is to only clear references to children
void QuadTreeLod::_clear_children(unsigned int index) {
	Quad *quad = _get_node(index);
	if (quad->has_children()) {
		_recycle_children(quad->first_child);
		quad->first_child = NO_CHILDREN;
	}
}

// Returns the index of the first_child. Allocates from _free_indices.
unsigned int QuadTreeLod::_allocate_children() {
	if (_free_indices.size() == 0) {
		return NO_CHILDREN;
	}

	unsigned int i0 = _free_indices[_free_indices.size() - 1];
	_free_indices.pop_back();
	return i0;
}

// Pass the first_child index, not the parent index. Stores back in _free_indices.
void QuadTreeLod::_recycle_children(unsigned int i0) {
	// Debug check, there is no use case in recycling a node which is not a first child
	CRASH_COND(i0 % 4 != 0);

	for (int i = 0; i < 4; ++i) {
		_node_pool[i0 + i].init();
	}

	_free_indices.push_back(i0);
}

Variant QuadTreeLod::_make_chunk(int lod, int origin_x, int origin_y) {
	if (_make_func.is_valid()) {
		return _make_func->call_func(origin_x, origin_y, lod);
	} else {
		return Variant();
	}
}

void QuadTreeLod::_recycle_chunk(unsigned int quad_index, int lod) {
	Quad *quad = _get_node(quad_index);
	if (_recycle_func.is_valid()) {
		_recycle_func->call_func(quad->get_data(), quad->origin_x, quad->origin_y, lod);
	}
}

void QuadTreeLod::_join_all_recursively(unsigned int quad_index, int lod) {
	Quad *quad = _get_node(quad_index);

	if (quad->has_children()) {
		for (int i = 0; i < 4; i++) {
			_join_all_recursively(quad->first_child + i, lod - 1);
		}
		_clear_children(quad_index);

	} else if (quad->is_valid()) {
		_recycle_chunk(quad_index, lod);
		quad->clear_data();
	}
}

void QuadTreeLod::_update(unsigned int quad_index, int lod, Vector3 view_pos) {
	// This function should be called regularly over frames.
	Quad *quad = _get_node(quad_index);
	int lod_factor = get_lod_factor(lod);
	int chunk_size = _base_size * lod_factor;
	Vector3 world_center = static_cast<real_t>(chunk_size) * (Vector3(static_cast<real_t>(quad->origin_x), 0.f, static_cast<real_t>(quad->origin_y)) + Vector3(0.5f, 0.f, 0.5f));

	if (_vertical_bounds_func.is_valid()) {
		Variant result = _vertical_bounds_func->call_func(quad->origin_x, quad->origin_y, lod);
		ERR_FAIL_COND(result.get_type() != Variant::VECTOR2);
		Vector2 vbounds = static_cast<Vector2>(result);
		world_center.y = (vbounds.x + vbounds.y) / 2.0f;
	}

	int split_distance = _base_size * lod_factor * static_cast<int>(_split_scale);

	if (!quad->has_children()) {
		if (lod > 0 && world_center.distance_to(view_pos) < split_distance) {
			// Split
			unsigned int new_idx = _allocate_children();
			ERR_FAIL_COND(new_idx == NO_CHILDREN);
			quad->first_child = new_idx;

			for (int i = 0; i < 4; i++) {
				Quad *child = _get_node(quad->first_child + i);
				child->origin_x = quad->origin_x * 2 + (i & 1);
				child->origin_y = quad->origin_y * 2 + ((i & 2) >> 1);
				child->set_data(_make_chunk(lod - 1, child->origin_x, child->origin_y));
				// If the quad needs to split more, we'll ask more recycling...
			}

			if (quad->is_valid()) {
				_recycle_chunk(quad_index, lod);
				quad->clear_data();
			}
		}
	} else {
		bool no_split_child = true;

		for (int i = 0; i < 4; i++) {
			_update(quad->first_child + i, lod - 1, view_pos);

			if (_get_node(quad->first_child + i)->has_children())
				no_split_child = false;
		}

		if (no_split_child && world_center.distance_to(view_pos) > split_distance) {
			// Join
			for (int i = 0; i < 4; i++) {
				_recycle_chunk(quad->first_child + i, lod - 1);
			}
			_clear_children(quad_index);
			quad->set_data(_make_chunk(lod, quad->origin_x, quad->origin_y));
		}
	}
} // _update

void QuadTreeLod::_debug_draw_tree_recursive(CanvasItem *ci, unsigned int quad_index, int lod_index, int child_index) {
	Quad *quad = _get_node(quad_index);

	if (quad->has_children()) {
		int ch_index = quad->first_child;
		for (int i = 0; i < 4; i++) {
			_debug_draw_tree_recursive(ci, ch_index + i, lod_index - 1, i);
		}

	} else {
		real_t size = static_cast<real_t>(get_lod_factor(lod_index));
		int checker = 0;
		if (child_index == 1 || child_index == 2)
			checker = 1;

		int chunk_indicator = 0;
		if (quad->is_valid())
			chunk_indicator = 1;

		Rect2 rect2(Vector2(static_cast<real_t>(quad->origin_x), static_cast<real_t>(quad->origin_y)) * size,
				Vector2(size, size));
		Color color(1.0f - static_cast<real_t>(lod_index) * 0.2f, 0.2f * static_cast<real_t>(checker), static_cast<real_t>(chunk_indicator), 1.0f);
		ci->draw_rect(rect2, color);
	}
}

void QuadTreeLod::_register_methods() {
	register_method("set_callbacks", &QuadTreeLod::set_callbacks);
	register_method("get_lod_count", &QuadTreeLod::get_lod_count);
	register_method("get_lod_factor", &QuadTreeLod::get_lod_factor);
	register_method("compute_lod_count", &QuadTreeLod::compute_lod_count);
	register_method("set_split_scale", &QuadTreeLod::set_split_scale);
	register_method("get_split_scale", &QuadTreeLod::get_split_scale);
	register_method("clear", &QuadTreeLod::clear);
	register_method("create_from_sizes", &QuadTreeLod::create_from_sizes);
	register_method("update", &QuadTreeLod::update);
	register_method("debug_draw_tree", &QuadTreeLod::debug_draw_tree);
}

} // namespace godot
