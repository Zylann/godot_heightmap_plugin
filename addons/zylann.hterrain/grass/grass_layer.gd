tool
extends Spatial

const HTerrain = preload("res://addons/zylann.hterrain/hterrain.gd")
const HTerrainData = preload("res://addons/zylann.hterrain/hterrain_data.gd")

const CHUNK_SIZE = 32

class Chunk:
	var cx = 0
	var cz = 0
	var multimesh_instances = []

var _terrain = null
var _grass_texture = load("res://addons/zylann.hterrain/demo/textures/grass/grass_billboard.png")
var _grass_shader = load("res://addons/zylann.hterrain/grass/grass.shader")

var _multimesh = null
var _multimesh_instance_pool = []
var _material = null
var _chunks = {}
var _view_distance = 128.0

var _edit_manual_viewer_pos = Vector3()


func _ready():
	set_process(false)
	if get_parent() is HTerrain:
		set_terrain(get_parent())


func _edit_set_manual_viewer_pos(pos):
	_edit_manual_viewer_pos = pos


func _process(delta):

	if _terrain == null:
		print("GrassLayer still processing while terrain is null")
		return
	
	var viewer_pos = _edit_manual_viewer_pos
	var viewport = get_viewport()
	if viewport != null:
		var camera = viewport.get_camera()
		if camera != null:
			viewer_pos = camera.get_global_transform().origin
	
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
	
	for k in _chunks:
		var chunk = _chunks[k]
		var d = _get_distance_to_chunk(viewer_pos, chunk.cx, chunk.cz)
		if d > _view_distance:
			var cpos2d = Vector2(chunk.cx, chunk.cz)
			_recycle_chunk(cpos2d)


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


func _load_chunk(cx, cz):
	var cpos2d = Vector2(cx, cz)
	
	var mmi = null
	if len(_multimesh_instance_pool) != 0:
		mmi = _multimesh_instance_pool[-1]
		_multimesh_instance_pool.pop_back()
	else:
		if _multimesh == null:
			_multimesh = _generate_multimesh(CHUNK_SIZE)
		mmi = _create_multimesh_instance(_multimesh, self)
	mmi.translation = Vector3(cx * CHUNK_SIZE, 0, cz * CHUNK_SIZE)
	mmi.set_visible(true)
	# TODO Set custom AABB to prevent wrong culling
	
	var chunk = Chunk.new()
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


func set_terrain(terrain):
	if _terrain == terrain:
		return
	
	if _terrain != null:
		if _terrain.is_connected("progress_complete", self, "_on_terrain_loaded"):
			_terrain.disconnect("progress_complete", self, "_on_terrain_loaded")
			for k in _chunks:
				_recycle_chunk(k)
	
	_terrain = terrain
	
	if _terrain != null:
		var terrain_data = _terrain.get_data()
		if terrain_data != null:
			if terrain_data.is_locked():
				_terrain.connect("progress_complete", self, "_on_terrain_loaded", [], CONNECT_ONESHOT)
			else:
				set_process(true)
	else:
		set_process(false)


func _on_terrain_loaded():
	set_process(true)


static func _create_quad():
	var positions = PoolVector3Array([
		Vector3(-0.5, 0, 0),
		Vector3(0.5, 0, 0),
		Vector3(0.5, 1, 0),
		Vector3(-0.5, 1, 0),
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
	# Bottom is darkened to fake grass AO
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
	var mesh = _create_quad()
	
	var density = 4
	var position_randomness = 0.4
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


func _create_multimesh_instance(multimesh, parent):
	
	assert(_terrain != null)
	assert(_terrain.get_data() != null)
	var terrain_data = _terrain.get_data()
	assert(not terrain_data.is_locked())
	
	var heightmap_texture = _terrain.get_data().get_texture(HTerrainData.CHANNEL_HEIGHT)
	
#	var mat = SpatialMaterial.new()
#	mat.albedo_texture = _grass_texture
#	mat.vertex_color_use_as_albedo = true
#	mat.params_cull_mode = SpatialMaterial.CULL_DISABLED
#	mat.params_use_alpha_scissor = true
#	mat.params_alpha_scissor_threshold = 0.5
#	mat.roughness = 1.0
	#mat.params_depth_draw_mode = SpatialMaterial.DEPTH_DRAW_ALPHA_OPAQUE_PREPASS
	#mat.params_billboard_mode = SpatialMaterial.BILLBOARD_FIXED_Y
	
	if _material == null:
		var mat = ShaderMaterial.new()
		mat.shader = _grass_shader
		mat.set_shader_param("u_terrain_heightmap", heightmap_texture)
		mat.set_shader_param("u_albedo_alpha", _grass_texture)
		mat.set_shader_param("u_view_distance", _view_distance)
		_material = mat
	
	# Assign multimesh to be rendered by the MultiMeshInstance
	var mmi = MultiMeshInstance.new()
	mmi.multimesh = multimesh
	mmi.material_override = _material
	parent.add_child(mmi)
	
	return mmi
