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


static func create_wirecube_mesh():
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
	var c = Color(1, 1, 1)
	var colors = PoolColorArray([
		c, c, c, c,
		c, c, c, c
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
	print("isqrt(", x, ") doesn't exist")
	return -1
