#ifndef QUAD_TREE_LOD_H
#define QUAD_TREE_LOD_H

#include <CanvasItem.hpp>
#include <FuncRef.hpp>
#include <Godot.hpp>

#include <vector>

namespace godot {

class QuadTreeLod : public Reference {
	GODOT_CLASS(QuadTreeLod, Reference)
public:
	static void _register_methods();

	QuadTreeLod() {}
	~QuadTreeLod() {}
	
	void _init() {}

	void set_callbacks(Ref<FuncRef> make_cb, Ref<FuncRef> recycle_cb, Ref<FuncRef> vbounds_cb);
	int get_lod_count();
	int get_lod_factor(int lod);
	int compute_lod_count(int base_size, int full_size);
	void set_split_scale(real_t p_split_scale);
	real_t get_split_scale();
	void clear();
	void create_from_sizes(int base_size, int full_size);
	void update(Vector3 view_pos);
	void debug_draw_tree(CanvasItem *ci);

private:
	static const unsigned int NO_CHILDREN = -1;
	static const unsigned int ROOT = -1;

	class Quad {
	public:
		unsigned int first_child = NO_CHILDREN;
		int origin_x = 0;
		int origin_y = 0;

		Quad() {
			init();
		}

		~Quad() {
		}

		inline void init() {
			first_child = NO_CHILDREN;
			origin_x = 0;
			origin_y = 0;
			clear_data();
		}

		inline void clear_data() {
			_data = Variant();
		}

		inline bool has_children() {
			return first_child != NO_CHILDREN;
		}

		inline bool is_null() {
			return _data.get_type() == Variant::NIL;
		}

		inline bool is_valid() {
			return _data.get_type() != Variant::NIL;
		}

		inline Variant get_data() {
			return _data;
		}

		inline void set_data(Variant p_data) {
			_data = p_data;
		}

	private:
		Variant _data; // Type is HTerrainChunk.gd : Object
	};

	Quad _root;
	std::vector<Quad> _node_pool;
	std::vector<unsigned int> _free_indices;

	int _max_depth = 0;
	int _base_size = 16;
	real_t _split_scale = 2.0f;

	Ref<FuncRef> _make_func;
	Ref<FuncRef> _recycle_func;
	Ref<FuncRef> _vertical_bounds_func;

	inline Quad *_get_root() {
		return &_root;
	}

	inline Quad *_get_node(unsigned int index) {
		if (index == ROOT) {
			return &_root;
		} else {
			return &_node_pool[index];
		}
	}

	void _clear_children(unsigned int index);
	unsigned int _allocate_children();
	void _recycle_children(unsigned int i0);
	Variant _make_chunk(int lod, int origin_x, int origin_y);
	void _recycle_chunk(unsigned int quad_index, int lod);
	void _join_all_recursively(unsigned int quad_index, int lod);
	void _update(unsigned int quad_index, int lod, Vector3 view_pos);
	void _debug_draw_tree_recursive(CanvasItem *ci, unsigned int quad_index, int lod_index, int child_index);
}; // class QuadTreeLod

} // namespace godot

#endif // QUAD_TREE_LOD_H
