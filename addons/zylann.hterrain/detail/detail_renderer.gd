tool

# Internal module which handles detail layers on the terrain (grass, foliage, rocks).
# Details use their own chunk grid, scattered around the player.
# Importantly, they also do NOT scale with map scale.
# Indeed, scaling the heightmap doesn't mean we want to scale grass blades (which is not a use case I know of).

var HTerrainData = load("res://addons/zylann.hterrain/hterrain_data.gd")
const DirectMultiMeshInstance = preload("../util/direct_multimesh_instance.gd")
const DirectMeshInstance = preload("../util/direct_mesh_instance.gd")
const Util = preload("../util/util.gd")

# TODO Rename DETAIL_CHUNK_SIZE to avoid confusion?
const CHUNK_SIZE = 32
const DETAIL_SHADER_PATH = "res://addons/zylann.hterrain/detail/detail.shader"
const DEBUG = false

# These parameters are considered built-in,
# they are managed internally so they are not treated the same
const _API_SHADER_PARAMS = {
	"u_terrain_heightmap": true,
	"u_terrain_detailmap": true,
	"u_terrain_normalmap": true,
	"u_terrain_globalmap": true,
	"u_terrain_inverse_transform": true,
	"u_albedo_alpha": true,
	"u_view_distance": true,
	"u_ambient_wind": true
}

class Chunk:
	var cx = 0
	var cz = 0
	# One per layer
	var multimesh_instances = []

	func set_aabb(p_aabb):
		for mmi in multimesh_instances:
			mmi.set_aabb(p_aabb)

	func set_world(w):
		for mmi in multimesh_instances:
			mmi.set_world(w)

	func set_visible(v):
		for mmi in multimesh_instances:
			mmi.set_visible(v)


class Layer:
	# This material can be null until it is really needed for rendering
	var material = null
	var texture = null


var _view_distance = 100.0
var _layers = []
var _ambient_wind_time = 0.0

var _terrain = null
var _detail_shader = load(DETAIL_SHADER_PATH)
var _multimesh = null
var _multimesh_instance_pool = []

# Chunks indexed by position in chunks
var _chunks = {}

var _debug_wirecube_mesh = null
var _debug_cubes = []

# TODO Have an optimization baking process where we ignore chunks that have no grass
# TODO Ability to choose a custom mesh instead of the built-in quad


func set_terrain(terrain):
	_terrain = terrain
	#_reset_layers()


func on_terrain_transform_changed(gt):
	# Update materials
	for i in range(len(_layers)):
		var layer = _layers[i]
		if layer != null:
			if layer.material != null:
				_update_layer_material(layer, i)

	# Update AABBs
	for k in _chunks:
		var chunk = _chunks[k]
		var aabb = _get_chunk_aabb(Vector3(chunk.cx * CHUNK_SIZE, 0, chunk.cz * CHUNK_SIZE))
		# Nullify XZ translation because that's done by transform already
		aabb.position.x = 0
		aabb.position.z = 0
		chunk.set_aabb(aabb)


func on_terrain_world_changed(w):
	for k in _chunks:
		var chunk = _chunks[k]
		chunk.set_world(w)


func on_terrain_visibility_changed(visible):
	for k in _chunks:
		var chunk = _chunks[k]
		chunk.set_visible(visible)


func serialize():
	var data = []
	for layer in _layers:
		
		var props = {
			"texture": layer.texture,
			"shader_params": {}
		}
		
		var shader_params = VisualServer.shader_get_param_list(layer.material.shader.get_rid())
		for p in shader_params:
			if _API_SHADER_PARAMS.has(p.name):
				continue
			props.shader_params[p.name] = layer.material.get_shader_param(p.name)
		
		data.append(props)

	return data


func deserialize(data):
	_layers.clear()
	for layer_data in data:

		var layer = Layer.new()
		layer.texture = layer_data.texture

		if layer_data.has("shader_params"):
			if layer.material == null:
				layer.material = ShaderMaterial.new()
				layer.material.shader = _detail_shader
			for param_name in layer_data.shader_params:
				var v = layer_data.shader_params[param_name]
				layer.material.set_shader_param(param_name, v)

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


func set_shader_param(i, param_name, value):
	assert(i < len(_layers))
	var layer = _layers[i]
	layer.material.set_shader_param(param_name, value)


func get_shader_param(i, param_name):
	assert(i < len(_layers))
	var layer = _layers[i]
	return Util.get_shader_param_or_default(layer.material, param_name)


func update_ambient_wind():
	var awp = _get_ambient_wind_params()
	for layer in _layers:
		# TODO Have stiffness per layer?
		layer.material.set_shader_param("u_ambient_wind", awp)


func _reset_layers():
	print("Resetting detail layers")

	for k in _chunks.keys():
		_recycle_chunk(k)
	
	if _terrain == null:
		print("Clearing layers because _terrain is null")
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


func process(delta, viewer_pos):

	if _terrain == null:
		print("DetailLayer processing while terrain is null!")
		return
	
	if len(_layers) == 0:
		print("DetailLayer processing while there are no layers!")
		return

	var local_viewer_pos = viewer_pos - _terrain.translation

	var viewer_cx = local_viewer_pos.x / CHUNK_SIZE
	var viewer_cz = local_viewer_pos.z / CHUNK_SIZE
	
	var cr = int(_view_distance) / CHUNK_SIZE + 1

	var cmin_x = viewer_cx - cr
	var cmin_z = viewer_cz - cr
	var cmax_x = viewer_cx + cr
	var cmax_z = viewer_cz + cr
	
	var map_res = _terrain.get_data().get_resolution()
	var map_scale = _terrain.map_scale

	var terrain_size_x = map_res * map_scale.x
	var terrain_size_z = map_res * map_scale.z

	var terrain_chunks_x = terrain_size_x / CHUNK_SIZE
	var terrain_chunks_z = terrain_size_z / CHUNK_SIZE
	
	if cmin_x < 0:
		cmin_x = 0
	if cmin_z < 0:
		cmin_z = 0
	if cmax_x > terrain_chunks_x:
		cmax_x = terrain_chunks_x
	if cmax_z > terrain_chunks_z:
		cmax_z = terrain_chunks_z

	if DEBUG:
		_debug_cubes.clear()
		for cz in range(cmin_z, cmax_z):
			for cx in range(cmin_x, cmax_x):
				_add_debug_cube(_get_chunk_aabb(Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)))
	
	for cz in range(cmin_z, cmax_z):
		for cx in range(cmin_x, cmax_x):
			
			var d = _get_distance_to_chunk(local_viewer_pos, cx, cz)
			var cpos2d = Vector2(cx, cz)
			
			if d < _view_distance:
				if not _chunks.has(cpos2d):
					_load_chunk(cx, cz)
	
	var to_recycle = []

	for k in _chunks:
		var chunk = _chunks[k]
		var d = _get_distance_to_chunk(local_viewer_pos, chunk.cx, chunk.cz)
		if d > _view_distance:
			var cpos2d = Vector2(chunk.cx, chunk.cz)
			to_recycle.append(cpos2d)

	for k in to_recycle:
		_recycle_chunk(k)

	# Update time manually, so we can accelerate the animation when strength is increased,
	# without causing phase jumps (which would be the case if we just scaled TIME)
	var ambient_wind_frequency = 1.0 + 3.0 * _terrain.ambient_wind
	_ambient_wind_time += delta * ambient_wind_frequency
	var awp = _get_ambient_wind_params()
	for layer in _layers:
		# Layer materials are created only when a chunk is first needed in that layer,
		# so it's possible they are still null at this point
		if layer.material != null:
			layer.material.set_shader_param("u_ambient_wind", awp)


func _get_ambient_wind_params():
	# amplitude, time
	return Vector2(_terrain.ambient_wind, _ambient_wind_time)


func _get_distance_to_chunk(local_viewer_pos, cx, cz):
	assert(typeof(cx) == TYPE_INT)
	assert(typeof(cz) == TYPE_INT)
	#return Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE).distance_to(local_viewer_pos)
	# TODO use distance to box, not center?
	var aabb = _get_chunk_aabb(Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE))
	return (aabb.position + 0.5 * aabb.size).distance_to(local_viewer_pos)


# Gets local-space AABB of a detail chunk.
# This only apply map_scale in Y, because details are not affected by X and Z map scale.
func _get_chunk_aabb(lpos):
	var terrain_scale = _terrain.map_scale
	var terrain_data = _terrain.get_data()
	var origin_cells_x = int(lpos.x / terrain_scale.x)
	var origin_cells_z = int(lpos.z / terrain_scale.z)
	var size_cells_x = int(CHUNK_SIZE / terrain_scale.x)
	var size_cells_z = int(CHUNK_SIZE / terrain_scale.z)
	var aabb = terrain_data.get_region_aabb(origin_cells_x, origin_cells_z, size_cells_x, size_cells_z)
	aabb.position = Vector3(lpos.x, lpos.y + aabb.position.y * terrain_scale.y, lpos.z)
	aabb.size = Vector3(CHUNK_SIZE, aabb.size.y * terrain_scale.y, CHUNK_SIZE)
	return aabb


func _load_chunk(cx, cz):
	var cpos2d = Vector2(cx, cz)

	var chunk = Chunk.new()
	chunk.cx = cx
	chunk.cz = cz
	
	var lpos = Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
	# Terrain scale is not used on purpose. Rotation is not supported.
	var trans = Transform(Basis(), _terrain.get_internal_transform().origin + lpos)

	var aabb = _get_chunk_aabb(lpos)
	# Nullify XZ translation because that's done by transform already
	aabb.position.x = 0
	aabb.position.z = 0

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
			
			mmi = DirectMultiMeshInstance.new()
			mmi.set_world(_terrain.get_world())
			mmi.set_multimesh(_multimesh)
		
		mmi.set_material_override(_get_layer_material(layer, i))
		mmi.set_transform(trans)
		mmi.set_aabb(aabb)
		mmi.set_visible(true)

		chunk.multimesh_instances.append(mmi)

	_chunks[cpos2d] = chunk


func _recycle_chunk(cpos2d):
	var chunk = _chunks[cpos2d]

	chunk.set_visible(false)

	for mmi in chunk.multimesh_instances:
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
	# Sets API shader properties. Custom properties are assumed to be set already

	assert(_terrain != null)
	assert(_terrain.get_data() != null)

	var gt = _terrain.get_internal_transform()
	var it = gt.affine_inverse()
	var mat = layer.material

	mat.set_shader_param("u_terrain_inverse_transform", it)
	mat.set_shader_param("u_albedo_alpha", layer.texture)
	mat.set_shader_param("u_view_distance", _view_distance)
	mat.set_shader_param("u_ambient_wind", _get_ambient_wind_params())

	var terrain_data = _terrain.get_data()
	if terrain_data.is_locked():
		print("Terrain data locked, can't update detail layer now")
		return

	var heightmap_texture = terrain_data.get_texture(HTerrainData.CHANNEL_HEIGHT)
	var normalmap_texture = terrain_data.get_texture(HTerrainData.CHANNEL_NORMAL)

	# This texture must exist. If not, there is a bug in how the layer was added in the first place
	var detailmap_texture = terrain_data.get_texture(HTerrainData.CHANNEL_DETAIL, index)
	
	var globalmap_texture = null
	if terrain_data.get_map_count(HTerrainData.CHANNEL_GLOBAL_ALBEDO) > 0:
		globalmap_texture = terrain_data.get_texture(HTerrainData.CHANNEL_GLOBAL_ALBEDO)

	mat.set_shader_param("u_terrain_heightmap", heightmap_texture)
	mat.set_shader_param("u_terrain_detailmap", detailmap_texture)
	mat.set_shader_param("u_terrain_normalmap", normalmap_texture)
	mat.set_shader_param("u_terrain_globalmap", globalmap_texture)


func _add_debug_cube(aabb):
	var world = _terrain.get_world()

	if _debug_wirecube_mesh == null:
		_debug_wirecube_mesh = Util.create_wirecube_mesh()
		var mat = SpatialMaterial.new()
		mat.flags_unshaded = true
		_debug_wirecube_mesh.surface_set_material(0, mat)

	var debug_cube = DirectMeshInstance.new()
	debug_cube.set_mesh(_debug_wirecube_mesh)
	debug_cube.set_world(world)
	#aabb.position.y += 0.2*randf()
	debug_cube.set_transform(Transform(Basis().scaled(aabb.size), aabb.position))

	_debug_cubes.append(debug_cube)
