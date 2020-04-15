tool
# Independent quad tree designed to handle LOD

class Quad:
	var children = null
	var origin_x := 0
	var origin_y := 0
	var data = null

	func _init():
		pass
	
	func clear():
		clear_children()
		data = null
	
	func clear_children():
		children = null
	
	func has_children():
		return children != null


var _tree := Quad.new()
var _max_depth := 0
var _base_size := 16
var _split_scale := 2.0

var _make_func : FuncRef = null
var _recycle_func : FuncRef = null
var _vertical_bounds_func : FuncRef = null


func set_callbacks(make_cb: FuncRef, recycle_cb: FuncRef, vbounds_cb: FuncRef):
	_make_func = make_cb
	_recycle_func = recycle_cb
	_vertical_bounds_func = vbounds_cb


func clear():
	_join_all_recursively(_tree, _max_depth)
	_max_depth = 0
	_base_size = 0


static func compute_lod_count(base_size: int, full_size: int) -> int:
	var po = 0
	while full_size > base_size:
		full_size = full_size >> 1
		po += 1
	return po


func create_from_sizes(base_size: int, full_size: int):
	clear()
	_base_size = base_size
	_max_depth = compute_lod_count(base_size, full_size)


func get_lod_count() -> int:
	# TODO _max_depth is a maximum, not a count. Would be better for it to be a count (+1)
	return _max_depth + 1


# The higher, the longer LODs will spread and higher the quality.
# The lower, the shorter LODs will spread and lower the quality.
func set_split_scale(p_split_scale: float):
	var MIN := 2.0
	var MAX := 5.0

	# Split scale must be greater than a threshold,
	# otherwise lods will decimate too fast and it will look messy
	if p_split_scale < MIN:
		p_split_scale = MIN
	if p_split_scale > MAX:
		p_split_scale = MAX

	_split_scale = float(p_split_scale)


func get_split_scale() -> float:
	return _split_scale


func update(view_pos: Vector3):
	_update(_tree, _max_depth, view_pos)
	
	# This makes sure we keep seeing the lowest LOD,
	# if the tree is cleared while we are far away
	if not _tree.has_children() and _tree.data == null:
		_tree.data = _make_chunk(_max_depth, 0, 0)


# TODO Should be renamed get_lod_factor
func get_lod_size(lod: int) -> int:
	return 1 << lod


func _update(quad: Quad, lod: int, view_pos: Vector3):
	# This function should be called regularly over frames.
	
	var lod_factor := get_lod_size(lod)
	var chunk_size := _base_size * lod_factor
	var world_center := \
		chunk_size * (Vector3(quad.origin_x, 0, quad.origin_y) + Vector3(0.5, 0, 0.5))
	
	if _vertical_bounds_func != null:
		var vbounds = _vertical_bounds_func.call_func(quad.origin_x, quad.origin_y, lod)
		world_center.y = (vbounds.x + vbounds.y) / 2.0
	
	var split_distance := _base_size * lod_factor * _split_scale
	
	if not quad.has_children():
		if lod > 0 and world_center.distance_to(view_pos) < split_distance:
			# Split
			quad.children = [null, null, null, null]

			for i in 4:
				var child := Quad.new()
				child.origin_x = quad.origin_x * 2 + (i & 1)
				child.origin_y = quad.origin_y * 2 + ((i & 2) >> 1)
				quad.children[i] = child
				child.data = _make_chunk(lod - 1, child.origin_x, child.origin_y)
				# If the quad needs to split more, we'll ask more recycling...

			if quad.data != null:
				_recycle_chunk(quad.data, quad.origin_x, quad.origin_y, lod)
				quad.data = null
	
	else:
		var no_split_child := true
		
		for child in quad.children:
			_update(child, lod - 1, view_pos)
			if child.has_children():
				no_split_child = false
		
		if no_split_child and world_center.distance_to(view_pos) > split_distance:
			# Join
			if quad.has_children():
				for i in 4:
					var child = quad.children[i]
					_recycle_chunk(child.data, child.origin_x, child.origin_y, lod - 1)
					quad.data = null
				quad.clear_children()

				assert(quad.data == null)
				quad.data = _make_chunk(lod, quad.origin_x, quad.origin_y)


func _join_all_recursively(quad: Quad, lod: int):
	if quad.has_children():
		for i in range(4):
			var child = quad.children[i]
			_join_all_recursively(child, lod - 1)

		quad.clear_children()
		
	elif quad.data != null:
		_recycle_chunk(quad.data, quad.origin_x, quad.origin_y, lod)
		quad.data = null


func _make_chunk(lod: int, origin_x: int, origin_y: int):
	var chunk = null
	if _make_func != null:
		chunk = _make_func.call_func(origin_x, origin_y, lod)
	return chunk


func _recycle_chunk(chunk, origin_x: int, origin_y: int, lod: int):
	if _recycle_func != null:
		_recycle_func.call_func(chunk, origin_x, origin_y, lod)


func debug_draw_tree(ci: CanvasItem):
	var quad := _tree
	_debug_draw_tree_recursive(ci, quad, _max_depth, 0)


func _debug_draw_tree_recursive(ci: CanvasItem, quad: Quad, lod_index: int, child_index: int):
	if quad.has_children():
		for i in range(0, quad.children.size()):
			var child = quad.children[i]
			_debug_draw_tree_recursive(ci, child, lod_index - 1, i)	
	else:
		var size := get_lod_size(lod_index)
		var checker := 0
		if child_index == 1 or child_index == 2:
			checker = 1
		var chunk_indicator := 0
		if quad.data != null:
			chunk_indicator = 1
		var r := Rect2(Vector2(quad.origin_x, quad.origin_y) * size, Vector2(size, size))
		ci.draw_rect(r, Color(1.0 - lod_index * 0.2, 0.2 * checker, chunk_indicator, 1))

