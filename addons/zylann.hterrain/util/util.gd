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


# TODO Get rid of this, it was needed for C++ porting but it's ugly in GDScript
static func clamp_min_max_excluded(out_min, out_max, p_min, p_max):
	if out_min[0] < p_min[0]:
		out_min[0] = p_min[0]
	if out_min[1] < p_min[1]:
		out_min[1] = p_min[1]

	if out_min[0] > p_max[0]:
		# Means the rectangle has zero length.
		# Position is invalid but shouldn't be iterated anyways
		out_min[0] = p_max[0]
	if out_min[1] > p_max[1]:
		out_min[1] = p_max[1]

	if out_max[0] < p_min[0]:
		# Means the rectangle has zero length.
		# Position is invalid but shouldn't be iterated anyways
		out_max[0] = p_min[0]
	if out_max[1] < p_min[1]:
		out_max[1] = p_min[1];

	if out_max[0] > p_max[0]:
		out_max[0] = p_max[0]
	if out_max[1] > p_max[1]:
		out_max[1] = p_max[1]


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
	if x >= b:
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
	#                               .___.
	#           /)               ,-^     ^-. 
	#          //               /           \
	# .-------| |--------------/  __     __  \-------------------.__
	# |WMWMWMW| |>>>>>>>>>>>>> | />>\   />>\ |>>>>>>>>>>>>>>>>>>>>>>:>
	# `-------| |--------------| \__/   \__/ |-------------------'^^
	#          \\               \    /|\    /
	#           \)               \   \_/   /
	#                             |       |
	#                             |+H+H+H+|
	#                             \       /
	#                              ^-----^
	# TODO https://github.com/godotengine/godot/issues/17592
	# This may break some day, don't fly planes with this bullshit.
	# Obviously it won't work for nested viewports since that's basically what this function checks.
	if not node.is_inside_tree():
		return false
	var vp = get_node_in_parents(node, Viewport)
	if vp == null:
		return false
	return vp.get_parent() != null


