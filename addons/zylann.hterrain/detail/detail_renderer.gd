tool

# Internal module which handles detail layers on the terrain (grass, foliage, rocks)

var HTerrain = load("res://addons/zylann.hterrain/hterrain.gd")
var HTerrainData = load("res://addons/zylann.hterrain/hterrain_data.gd")

const CHUNK_SIZE = 32
const DETAIL_SHADER_PATH = "res://addons/zylann.hterrain/detail/detail.shader"

class Chunk:
	var cx = 0
	var cz = 0
	# One per layer
	var multimesh_instances = []

class Layer:
	var material = null
	var texture = null

var _view_distance = 100.0
var _layers = []

var _terrain = null
var _detail_shader = load(DETAIL_SHADER_PATH)
var _multimesh = null
var _multimesh_instance_pool = []
var _chunks = {}
# TODO Have an optimization baking process where we ignore chunks that have no grass
# TODO Ability to choose a custom mesh instead of the built-in quad

var _edit_manual_viewer_pos = Vector3()


func set_terrain(terrain):
	_terrain = terrain
	#_reset_layers()


func serialize():
	var data = []
	for layer in _layers:
		data.append({ "texture": layer.texture })
	return data


func deserialize(data):
	_layers.clear()
	for layer_data in data:
		var layer = Layer.new()
		layer.texture = layer_data.texture
		_layers.append(layer)


func reset():
	_reset_layers()


func remove_layer(index):
	print("Erase detail layer ", index)
	_layers.remove(index)
	_reset_layers()


func get_layer_count():
	return len(_layers)


func set_texture(i, tex):
	assert(i < len(_layers))
	var layer = _layers[i]
	assert(layer != null)
	layer.texture = tex
	if layer.material != null:
		layer.material.set_shader_param("u_albedo_alpha", tex)


func get_texture(i):
	assert(i < len(_layers))
	var layer = _layers[i]
	return layer.texture if layer != null else null


func _reset_layers():
	print("Resetting detail layers")

	for k in _chunks.keys():
		_recycle_chunk(k)
	
	if _terrain == null:
		_layers.clear()
		return
	
	var data = _terrain.get_data()
	if data == null or data.is_locked():
		return
	
	var layer_count = data.get_map_count(HTerrainData.CHANNEL_DETAIL)
	_layers.resize(layer_count)
	for i in range(layer_count):
		var layer = _layers[i]
		if layer == null:
			layer = Layer.new()
			_layers[i] = layer
		else:
			if layer.material != null:
				_update_layer_material(layer, i)


func process(viewer_pos):

	if _terrain == null:
		print("DetailLayer processing while terrain is null!")
		return
	
	if len(_layers) == 0:
		print("DetailLayer processing while there are no layers!")
		return

	var viewer_cx = viewer_pos.x / CHUNK_SIZE
	var viewer_cz = viewer_pos.z / CHUNK_SIZE
	
	var cr = int(_view_distance) / CHUNK_SIZE + 1

	var cmin_x = viewer_cx - cr
	var cmin_z = viewer_cz - cr
	var cmax_x = viewer_cx + cr
	var cmax_z = viewer_cz + cr
	
	var terrain_csize = _terrain.get_data().get_resolution() / CHUNK_SIZE
	
	if cmin_x < 0:
		cmin_x = 0
	if cmin_z < 0:
		cmin_z = 0
	if cmin_x >= terrain_csize:
		cmin_x = terrain_csize - 1
	if cmax_z >= terrain_csize:
		cmax_z = terrain_csize - 1
	
	for cz in range(cmin_z, cmax_z):
		for cx in range(cmin_x, cmax_x):
			
			var d = _get_distance_to_chunk(viewer_pos, cx, cz)
			var cpos2d = Vector2(cx, cz)
			
			if d < _view_distance:
				if not _chunks.has(cpos2d):
					_load_chunk(cx, cz)
	
	var to_recycle = []

	for k in _chunks:
		var chunk = _chunks[k]
		var d = _get_distance_to_chunk(viewer_pos, chunk.cx, chunk.cz)
		if d > _view_distance:
			var cpos2d = Vector2(chunk.cx, chunk.cz)
			to_recycle.append(cpos2d)

	for k in to_recycle:
		_recycle_chunk(k)


func _get_distance_to_chunk(viewer_pos, cx, cz):
	return Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE).distance_to(viewer_pos)
	
	# TODO Should use AABB, but there is a bug here that offsets the chunks somehow
#	var chunk_aabb = _terrain.get_data().get_region_aabb( \
#		cx * CHUNK_SIZE, \
#		cz * CHUNK_SIZE, \
#		(cx + 1) * CHUNK_SIZE, \
#		(cz + 1) * CHUNK_SIZE)
#
#	# TODO use distance to box, not center?
#	var d = (chunk_aabb.position + chunk_aabb.size / 2.0).distance_to(viewer_pos)
#	return d


func _get_chunk_aabb(cx, cz):
	return _terrain.get_data().get_region_aabb( \
		cx * CHUNK_SIZE, \
		cz * CHUNK_SIZE, \
		(cx + 1) * CHUNK_SIZE, \
		(cz + 1) * CHUNK_SIZE)


func _load_chunk(cx, cz):
	var cpos2d = Vector2(cx, cz)

	var chunk = Chunk.new()
	
	for i in range(len(_layers)):
		var layer = _layers[i]
		
		var mmi = null
		if len(_multimesh_instance_pool) != 0:
			mmi = _multimesh_instance_pool[-1]
			_multimesh_instance_pool.pop_back()
			
		else:
			if _multimesh == null:
				_multimesh = _generate_multimesh(CHUNK_SIZE)
				# TODO Have a different multimesh per layer to avoid triangle fights
			
			# TODO Use VisualServer directly?
			mmi = MultiMeshInstance.new()
			mmi.multimesh = _multimesh
			_terrain.add_child(mmi)
		
		mmi.material_override = _get_layer_material(layer, i)
		mmi.translation = Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
		mmi.set_visible(true)
		# TODO Set custom AABB to prevent bad culling
	
		chunk.multimesh_instances.append(mmi)
	
	chunk.cx = cx
	chunk.cz = cz
	_chunks[cpos2d] = chunk


func _recycle_chunk(cpos2d):
	var chunk = _chunks[cpos2d]
	
	for mmi in chunk.multimesh_instances:
		mmi.set_visible(false)
		_multimesh_instance_pool.append(mmi)
	
	_chunks.erase(cpos2d)


static func create_quad():
	var positions = PoolVector3Array([
		Vector3(-0.5, 0, 0),
		Vector3(0.5, 0, 0),
		Vector3(0.5, 1, 0),
		Vector3(-0.5, 1, 0)
	])
	var normals = PoolVector3Array([
		Vector3(0, 0, -1),
		Vector3(0, 0, -1),
		Vector3(0, 0, -1),
		Vector3(0, 0, -1)
	])
	var uvs = PoolVector2Array([
		Vector2(0, 1),
		Vector2(1, 1),
		Vector2(1, 0),
		Vector2(0, 0)
	])
	# Bottom is darkened to fake AO
	var dc = 0.8
	var colors = PoolColorArray([
		Color(1, 1, 1).darkened(dc),
		Color(1, 1, 1).darkened(dc),
		Color(1, 1, 1),
		Color(1, 1, 1)
	])
	var indices = PoolIntArray([
		0, 1, 2,
		0, 2, 3
	])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _generate_multimesh(resolution):
	var mesh = create_quad()
	
	var density = 4
	var position_randomness = 0.5
	var scale_randomness = 0.0
	#var color_randomness = 0.5

	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_8BIT
	mm.instance_count = resolution * resolution * density
	mm.mesh = mesh
	
	var i = 0
	for z in range(resolution):
		for x in range(resolution):
			for j in range(density):
				#var pos = Vector3(rand_range(0, res), 0, rand_range(0, res))
				
				var pos = Vector3(x, 0, z)
				pos.x += rand_range(-position_randomness, position_randomness)
				pos.z += rand_range(-position_randomness, position_randomness)
				
				var sr = rand_range(0, scale_randomness)
				var s = 1.0 + (sr * sr * sr * sr * sr) * 50.0
				
				var basis = Basis()
				basis = basis.scaled(Vector3(1, s, 1))
				basis = basis.rotated(Vector3(0, 1, 0), rand_range(0, PI))
				
				var t = Transform(basis, pos)
				
				var c = Color(1, 1, 1)#.darkened(rand_range(0, color_randomness))
				
				mm.set_instance_color(i, c)
				mm.set_instance_transform(i, t)
				i += 1
	
	return mm


func _get_layer_material(layer, index):
	if layer.material != null:
		return layer.material

	print("Creating material for detail layer ", index, " with texture ", layer.texture)

	var mat = ShaderMaterial.new()
	mat.shader = _detail_shader
	layer.material = mat

	_update_layer_material(layer, index)
	
	return mat


func _update_layer_material(layer, index):

	assert(_terrain != null)
	assert(_terrain.get_data() != null)
	var terrain_data = _terrain.get_data()
	assert(not terrain_data.is_locked())

	var heightmap_texture = _terrain.get_data().get_texture(HTerrainData.CHANNEL_HEIGHT)
	var detailmap_texture = _terrain.get_data().get_texture(HTerrainData.CHANNEL_DETAIL, index)
	var normalmap_texture = _terrain.get_data().get_texture(HTerrainData.CHANNEL_NORMAL)

	var mat = layer.material
	mat.set_shader_param("u_terrain_heightmap", heightmap_texture)
	mat.set_shader_param("u_terrain_detailmap", detailmap_texture)
	mat.set_shader_param("u_terrain_normalmap", normalmap_texture)
	mat.set_shader_param("u_albedo_alpha", layer.texture)
	mat.set_shader_param("u_view_distance", _view_distance)
