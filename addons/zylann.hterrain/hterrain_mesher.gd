tool

const Logger = preload("./util/logger.gd")

const SEAM_LEFT = 1
const SEAM_RIGHT = 2
const SEAM_BOTTOM = 4
const SEAM_TOP = 8
const SEAM_CONFIG_COUNT = 16


# [seams_mask][lod]
var _mesh_cache := []
var _chunk_size_x := 16
var _chunk_size_y := 16


func configure(chunk_size_x: int, chunk_size_y: int, lod_count: int):
	assert(typeof(chunk_size_x) == TYPE_INT)
	assert(typeof(chunk_size_y) == TYPE_INT)
	assert(typeof(lod_count) == TYPE_INT)
	
	assert(chunk_size_x >= 2 or chunk_size_y >= 2)

	_mesh_cache.resize(SEAM_CONFIG_COUNT)
	
	if chunk_size_x == _chunk_size_x \
	and chunk_size_y == _chunk_size_y and lod_count == len(_mesh_cache):
		return
	
	_chunk_size_x = chunk_size_x
	_chunk_size_y = chunk_size_y

	# TODO Will reduce the size of this cache, but need index buffer swap feature
	for seams in range(SEAM_CONFIG_COUNT):
		
		var slot = []
		slot.resize(lod_count)
		_mesh_cache[seams] = slot
		
		for lod in range(lod_count):
			slot[lod] = make_flat_chunk(_chunk_size_x, _chunk_size_y, 1 << lod, seams)


func get_chunk(lod: int, seams: int) -> Mesh:
	return _mesh_cache[seams][lod] as Mesh


static func make_flat_chunk(quad_count_x: int, quad_count_y: int, stride: int, seams: int) -> Mesh:

	var positions = PoolVector3Array()
	positions.resize((quad_count_x + 1) * (quad_count_y + 1))

	var i = 0
	for y in range(quad_count_y + 1):
		for x in range(quad_count_x + 1):
			positions[i] = Vector3(x * stride, 0, y * stride)
			i += 1
		
	var indices = make_indices(quad_count_x, quad_count_y, seams)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX);
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh


# size: chunk size in quads (there are N+1 vertices)
# seams: Bitfield for which seams are present
static func make_indices(chunk_size_x: int, chunk_size_y: int, seams: int) -> PoolIntArray:

	var output_indices := PoolIntArray()

	if seams != 0:
		# LOD seams can't be made properly on uneven chunk sizes
		assert(chunk_size_x % 2 == 0 and chunk_size_y % 2 == 0)

	var reg_origin_x := 0
	var reg_origin_y := 0
	var reg_size_x := chunk_size_x
	var reg_size_y := chunk_size_y
	var reg_hstride := 1
	
	if seams & SEAM_LEFT:
		reg_origin_x += 1;
		reg_size_x -= 1;
		reg_hstride += 1

	if seams & SEAM_BOTTOM:
		reg_origin_y += 1
		reg_size_y -= 1

	if seams & SEAM_RIGHT:
		reg_size_x -= 1
		reg_hstride += 1

	if seams & SEAM_TOP:
		reg_size_y -= 1

	# Regular triangles
	var ii := reg_origin_x + reg_origin_y * (chunk_size_x + 1)

	for y in range(reg_size_y):
		for x in range(reg_size_x):
			
			var i00 := ii
			var i10 := ii + 1
			var i01 := ii + chunk_size_x + 1
			var i11 := i01 + 1

			# 01---11
			#  |  /|
			#  | / |
			#  |/  |
			# 00---10

			# This flips the pattern to make the geometry orientation-free.
			# Not sure if it helps in any way though
			var flip = ((x + reg_origin_x) + (y + reg_origin_y) % 2) % 2 != 0

			if flip:

				output_indices.push_back( i00 )
				output_indices.push_back( i10 )
				output_indices.push_back( i01 )

				output_indices.push_back( i10 )
				output_indices.push_back( i11 )
				output_indices.push_back( i01 )

			else:
				output_indices.push_back( i00 )
				output_indices.push_back( i11 )
				output_indices.push_back( i01 )

				output_indices.push_back( i00 )
				output_indices.push_back( i10 )
				output_indices.push_back( i11 )

			ii += 1
		ii += reg_hstride

	# Left seam
	if seams & SEAM_LEFT:

		#     4 . 5
		#     |\  .
		#     | \ .
		#     |  \.
		#  (2)|   3
		#     |  /.
		#     | / .
		#     |/  .
		#     0 . 1

		var i := 0
		var n := chunk_size_y / 2

		for j in range(n):

			var i0 := i
			var i1 := i + 1
			var i3 := i + chunk_size_x + 2
			var i4 := i + 2 * (chunk_size_x + 1)
			var i5 := i4 + 1

			output_indices.push_back( i0 )
			output_indices.push_back( i3 )
			output_indices.push_back( i4 )

			if j != 0 or (seams & SEAM_BOTTOM) == 0:
				output_indices.push_back( i0 )
				output_indices.push_back( i1 )
				output_indices.push_back( i3 )

			if j != n - 1 or (seams & SEAM_TOP) == 0:
				output_indices.push_back( i3 )
				output_indices.push_back( i5 )
				output_indices.push_back( i4 )

			i = i4

	if seams & SEAM_RIGHT:

		#     4 . 5
		#     .  /|
		#     . / |
		#     ./  |
		#     2   |(3)
		#     .\  |
		#     . \ |
		#     .  \|
		#     0 . 1

		var i := chunk_size_x - 1
		var n := chunk_size_y / 2

		for j in range(n):

			var i0 := i
			var i1 := i + 1
			var i2 := i + chunk_size_x + 1
			var i4 := i + 2 * (chunk_size_x + 1)
			var i5 := i4 + 1

			output_indices.push_back( i1 )
			output_indices.push_back( i5 )
			output_indices.push_back( i2 )

			if j != 0 or (seams & SEAM_BOTTOM) == 0:
				output_indices.push_back( i0 )
				output_indices.push_back( i1 )
				output_indices.push_back( i2 )

			if j != n - 1 or (seams & SEAM_TOP) == 0:
				output_indices.push_back( i2 )
				output_indices.push_back( i5 )
				output_indices.push_back( i4 )

			i = i4;

	if seams & SEAM_BOTTOM:

		#  3 . 4 . 5
		#  .  / \  .
		#  . /   \ .
		#  ./     \.
		#  0-------2
		#     (1)

		var i := 0;
		var n := chunk_size_x / 2;
		
		for j in range(n):

			var i0 := i
			var i2 := i + 2
			var i3 := i + chunk_size_x + 1
			var i4 := i3 + 1
			var i5 := i4 + 1

			output_indices.push_back( i0 )
			output_indices.push_back( i2 )
			output_indices.push_back( i4 )

			if j != 0 or (seams & SEAM_LEFT) == 0:
				output_indices.push_back( i0 )
				output_indices.push_back( i4 )
				output_indices.push_back( i3 )

			if j != n - 1 or (seams & SEAM_RIGHT) == 0:
				output_indices.push_back( i2 )
				output_indices.push_back( i5 )
				output_indices.push_back( i4 )

			i = i2

	if seams & SEAM_TOP:

		#     (4)
		#  3-------5
		#  .\     /.
		#  . \   / .
		#  .  \ /  .
		#  0 . 1 . 2

		var i := (chunk_size_y - 1) * (chunk_size_x + 1)
		var n := chunk_size_x / 2

		for j in range(n):

			var i0 := i
			var i1 := i + 1
			var i2 := i + 2
			var i3 := i + chunk_size_x + 1
			var i5 := i3 + 2

			output_indices.push_back( i3 )
			output_indices.push_back( i1 )
			output_indices.push_back( i5 )

			if j != 0 or (seams & SEAM_LEFT) == 0:
				output_indices.push_back( i0 )
				output_indices.push_back( i1 )
				output_indices.push_back( i3 )

			if j != n - 1 or (seams & SEAM_RIGHT) == 0:
				output_indices.push_back( i1 )
				output_indices.push_back( i2 )
				output_indices.push_back( i5 )

			i = i2

	return output_indices


static func get_mesh_size(width: int, height: int) -> Dictionary:
	return {
		"vertices": width * height,
		"triangles": (width - 1) * (height - 1) * 2
	}


# Makes a full mesh from a heightmap, without any LOD considerations.
# Using this mesh for rendering is very expensive on large terrains.
# Initially used as a workaround for Godot to use for navmesh generation.
static func make_heightmap_mesh(heightmap: Image, stride: int, scale: Vector3, 
	logger = null) -> Mesh:
	
	var size_x := heightmap.get_width() / stride
	var size_z := heightmap.get_height() / stride

	assert(size_x >= 2)
	assert(size_z >= 2)
	
	var positions := PoolVector3Array()
	positions.resize(size_x * size_z)
	
	heightmap.lock()

	var i := 0
	for mz in size_z:
		for mx in size_x:
			var x = mx * stride
			var z = mz * stride
			var y := heightmap.get_pixel(x, z).r
			positions[i] = Vector3(x, y, z) * scale
			i += 1
	
	heightmap.unlock()
	
	var indices := make_indices(size_x - 1, size_z - 1, 0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX);
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_INDEX] = indices
	
	if logger != null:
		logger.debug(str("Generated mesh has ", len(positions),
			" vertices and ", len(indices) / 3, " triangles"))

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	return mesh
