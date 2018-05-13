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


static func clampi(x, a, b):
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
