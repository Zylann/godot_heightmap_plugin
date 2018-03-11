tool
# Independent quad tree designed to handle LOD

class TreeNode:
	var children = null
	var origin_x = 0
	var origin_y = 0

	var chunk = null

	func _init():
		pass
	
	func clear():
		clear_children()
		chunk = null
	
	func clear_children():
		if has_children():
			for i in range(4):
				children[i] = null
		children = null
	
	func has_children():
		return children != null


var _tree = TreeNode.new()
var _max_depth = 0
var _base_size = 0
var _split_scale = 2.0

var _make_func = null
var _recycle_func = null


func _init():
	pass


func set_callbacks(make_cb, recycle_cb):
	_make_func = make_cb
	_recycle_func = recycle_cb


func clear():
	_join_recursively(_tree, _max_depth)
	
	_tree.clear_children()
	
	_max_depth = 0
	_base_size = 0


func compute_lod_count(base_size, full_size):
	var po = 0
	while full_size > base_size:
		full_size = full_size >> 1
		po += 1
	return po


func create_from_sizes(base_size, full_size):
	clear()
	_base_size = base_size
	_max_depth = compute_lod_count(base_size, full_size)


func get_lod_count():
	# TODO _max_depth is a maximum, not a count. Would be better for it to be a count (+1)
	return _max_depth + 1


# The higher, the longer LODs will spread and higher the quality.
# The lower, the shorter LODs will spread and lower the quality.
func set_split_scale(p_split_scale):
	var MIN = 2.0
	var MAX = 5.0

	# Split scale must be greater than a threshold,
	# otherwise lods will decimate too fast and it will look messy
	if p_split_scale < MIN:
		p_split_scale = MIN
	if p_split_scale > MAX:
		p_split_scale = MAX

	_split_scale = p_split_scale


func get_split_scale():
	return _split_scale


func update(viewer_pos):
	_update_nodes_recursive(_tree, _max_depth, viewer_pos)
	_make_chunks_recursively(_tree, _max_depth)


# TODO Should be renamed get_lod_factor
func get_lod_size(lod):
	return 1 << lod


func get_split_distance(lod):
	return _base_size * get_lod_size(lod) * _split_scale


func _make_chunk(lod, origin_x, origin_y):
	var chunk = null
	if _make_func != null:
		chunk = _make_func.call_func(origin_x, origin_y, lod)
	return chunk


func _recycle_chunk(chunk, origin_x, origin_y, lod):
	if _recycle_func != null:
		_recycle_func.call_func(chunk, origin_x, origin_y, lod)


func _join_recursively(node, lod):
	if node.has_children():
		for i in range(4):
			var child = node.children[i]
			_join_recursively(child, lod - 1)

		node.clear_children()
		
	elif node.chunk != null:
		_recycle_chunk(node.chunk, node.origin_x, node.origin_y, lod)
		node.chunk = null;


func _update_nodes_recursive(node, lod, viewer_pos):
	#print_line(String("update_nodes_recursive lod={0}, o={1}, {2} ").format(varray(lod, node.origin.x, node.origin.y)));

	var lod_size = get_lod_size(lod)
	var world_center = (_base_size * lod_size) * (Vector3(node.origin_x, 0, node.origin_y) + Vector3(0.5, 0, 0.5))
	var split_distance = get_split_distance(lod)

	if node.has_children():
		# Test if it should be joined
		# TODO Distance should take the chunk's Y dimension into account
		if world_center.distance_to(viewer_pos) > split_distance:
			_join_recursively(node, lod)

	elif lod > 0:
		# Test if it should split
		if world_center.distance_to(viewer_pos) < split_distance:
			# Split
			
			node.children = [null, null, null, null]

			for i in range(4):
				var child = TreeNode.new()
				child.origin_x = node.origin_x * 2 + (i & 1)
				child.origin_y = node.origin_y * 2 + ((i & 2) >> 1)
				node.children[i] = child

			if node.chunk != null:
				_recycle_chunk(node.chunk, node.origin_x, node.origin_y, lod)

			node.chunk = null

	# TODO This will check all chunks every frame,
	# we could find a way to recursively update chunks as they get joined/split,
	# but in C++ that would be not even needed.
	if node.has_children():
		for i in range(4):
			_update_nodes_recursive(node.children[i], lod - 1, viewer_pos)


func _make_chunks_recursively(node, lod):
	assert(lod >= 0)
	if node.has_children():
		for i in range(4):
			var child = node.children[i]
			_make_chunks_recursively(child, lod - 1)
	else:
		if node.chunk == null:
			node.chunk = _make_chunk(lod, node.origin_x, node.origin_y)
			# Note: if you don't return anything here,
			# _make_chunk will continue being called


func debug_draw_tree(ci):
	var node = _tree
	_debug_draw_tree_recursive(ci, node, _max_depth, 0)


func _debug_draw_tree_recursive(ci, node, lod_index, child_index):
	if node.has_children():
		for i in range(0, node.children.size()):
			var child = node.children[i]
			_debug_draw_tree_recursive(ci, child, lod_index - 1, i)	
	else:
		var size = get_lod_size(lod_index)
		var checker = 0
		if child_index == 1 or child_index == 2:
			checker = 1
		var chunk_indicator = 0
		if node.chunk != null:
			chunk_indicator = 1
		var r = Rect2(Vector2(node.origin_x, node.origin_y) * size, Vector2(size, size))
		ci.draw_rect(r, Color(1.0 - lod_index * 0.2, 0.2 * checker, chunk_indicator, 1))


