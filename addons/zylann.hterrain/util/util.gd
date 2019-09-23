tool

static func next_power_of_two(x):
	x -= 1
	x |= x >> 1
	x |= x >> 2
	x |= x >> 4
	x |= x >> 8
	x |= x >> 16
	x += 1
	return x


static func encode_v2i(x, y):
	return (x & 0xffff) | ((y << 16) & 0xffff0000)  


static func decode_v2i(k):
	return [
		k & 0xffff,
		(k >> 16) & 0xffff
	]


static func min_int(a, b):
	return a if a < b else b


static func max_int(a, b):
	return a if a > b else b


static func clamp_int(x, a, b):
	if x < a:
		return a
	if x > b:
		return b
	return x


static func array_sum(a):
	var s = 0
	for x in a:
		s += x
	return s


static func create_wirecube_mesh(color = Color(1,1,1)):
	var positions = PoolVector3Array([
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(1, 0, 1),
		Vector3(0, 0, 1),
		Vector3(0, 1, 0),
		Vector3(1, 1, 0),
		Vector3(1, 1, 1),
		Vector3(0, 1, 1),
	])
	var colors = PoolColorArray([
		color, color, color, color,
		color, color, color, color,
	])
	var indices = PoolIntArray([
		0, 1,
		1, 2,
		2, 3,
		3, 0,

		4, 5,
		5, 6,
		6, 7,
		7, 4,

		0, 4,
		1, 5,
		2, 6,
		3, 7
	])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


static func integer_square_root(x):
	assert(typeof(x) == TYPE_INT)
	var r = int(round(sqrt(x)))
	if r * r == x:
		return r
	# Does not exist
	printerr("isqrt(", x, ") doesn't exist")
	return -1


static func format_integer(n, sep = ","):
	assert(typeof(n) == TYPE_INT)
	
	var negative = false
	if n < 0:
		negative = true
		n = -n
	
	var s = ""
	while n >= 1000:
		s = str(sep, str(n % 1000).pad_zeros(3), s)
		n /= 1000
	
	if negative:
		return str("-", str(n), s)
	else:
		return str(str(n), s)


static func get_node_in_parents(node, klass):
	while node != null:
		node = node.get_parent()
		if node != null and node is klass:
			return node
	return null


static func is_in_edited_scene(node):
	if not node.is_inside_tree():
		return false
	var edited_scene = node.get_tree().edited_scene_root
	if node == edited_scene:
		return true
	return edited_scene != null and edited_scene.is_a_parent_of(node)


# Get an extended or cropped version of an image,
# with optional anchoring to decide in which direction to extend or crop.
# New pixels are filled with the provided fill color.
static func get_cropped_image(src, width, height, fill_color=null, anchor=Vector2(-1, -1)):
	width = int(width)
	height = int(height)
	if width == src.get_width() and height == src.get_height():
		return src
	var im = Image.new()
	im.create(width, height, false, src.get_format())
	if fill_color != null:
		im.fill(fill_color)
	var p = get_cropped_image_params(src.get_width(), src.get_height(), width, height, anchor)
	im.blit_rect(src, p.src_rect, p.dst_pos)
	return im


static func get_cropped_image_params(src_w, src_h, dst_w, dst_h, anchor):
	var rel_anchor = (anchor + Vector2(1, 1)) / 2.0

	var dst_x = (dst_w - src_w) * rel_anchor.x
	var dst_y = (dst_h - src_h) * rel_anchor.y
	
	var src_x = 0
	var src_y = 0
	
	if dst_x < 0:
		src_x -= dst_x
		src_w -= dst_x
		dst_x = 0
	
	if dst_y < 0:
		src_y -= dst_y
		src_h -= dst_y
		dst_y = 0
	
	if dst_x + src_w >= dst_w:
		src_w = dst_w - dst_x

	if dst_y + src_h >= dst_h:
		src_h = dst_h - dst_y

	return {
		"src_rect": Rect2(src_x, src_y, src_w, src_h),
		"dst_pos": Vector2(dst_x, dst_y)
	}

# TODO Workaround for https://github.com/godotengine/godot/issues/24488
# TODO Simplify in Godot 3.1 if that's still not fixed, using https://github.com/godotengine/godot/pull/21806
static func get_shader_param_or_default(mat, name):
	var v = mat.get_shader_param(name)
	if v != null:
		return v
	var params = VisualServer.shader_get_param_list(mat.shader)
	for p in params:
		print(p)
		if p.name == name:
			match p.type:
				TYPE_OBJECT:
					return null
				# I should normally check default values,
				# however they are not accessible
				TYPE_BOOL:
					return false
				TYPE_REAL:
					return 0.0
				TYPE_VECTOR2:
					return Vector2()
				TYPE_VECTOR3:
					return Vector3()
				TYPE_COLOR:
					return Color()
	return null


