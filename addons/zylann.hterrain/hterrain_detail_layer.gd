tool
extends Spatial

# Child node of the terrain, used to render numerous small objects on the ground
# such as grass or rocks. They do so by using a texture covering the terrain
# (a "detail map"), which is found in the terrain data itself.
# A terrain can have multiple detail maps, and you can choose which one will be
# used with `layer_index`.
# Details use instanced rendering within their own chunk grid, scattered around
# the player. Importantly, the position and rotation of this node don't matter,
# and they also do NOT scale with map scale. Indeed, scaling the heightmap
# doesn't mean we want to scale grass blades (which is not a use case I know of).

const HTerrainData = preload("./hterrain_data.gd")
const DirectMultiMeshInstance = preload("./util/direct_multimesh_instance.gd")
const DirectMeshInstance = preload("./util/direct_mesh_instance.gd")
const Util = preload("./util/util.gd")
const Logger = preload("./util/logger.gd")
const DefaultMesh = preload("./models/grass_quad.obj")

const CHUNK_SIZE = 32
const DEFAULT_SHADER_PATH = "res://addons/zylann.hterrain/shaders/detail.shader"
const DEBUG = false

# These parameters are considered built-in,
# they are managed internally so they are not directly exposed
const _API_SHADER_PARAMS = {
	"u_terrain_heightmap": true,
	"u_terrain_detailmap": true,
	"u_terrain_normalmap": true,
	"u_terrain_globalmap": true,
	"u_terrain_inverse_transform": true,
	"u_terrain_normal_basis": true,
	"u_albedo_alpha": true,
	"u_view_distance": true,
	"u_ambient_wind": true
}

export(int) var layer_index := 0 setget set_layer_index, get_layer_index
export(Texture) var texture : Texture setget set_texture, get_texture
# TODO Improve speed of _get_chunk_aabb() so we can increase the limit
# See https://github.com/Zylann/godot_heightmap_plugin/issues/155
export(float, 1.0, 500.0) var view_distance := 100.0 setget set_view_distance, get_view_distance
export(Shader) var custom_shader : Shader setget set_custom_shader, get_custom_shader
export(float, 0, 10) var density := 4.0 setget set_density, get_density
# Mesh used for every detail instance (for example, every grass patch).
# If not assigned, an internal quad mesh will be used.
# I would have called it `mesh` but that's too broad and conflicts with local vars ._.
export(Mesh) var instance_mesh : Mesh setget set_instance_mesh, get_instance_mesh

var _material: ShaderMaterial = null
var _default_shader: Shader = null

# Vector2 => DirectMultiMeshInstance
var _chunks := {}

var _multimesh: MultiMesh = null
var _multimesh_instance_pool := []
var _ambient_wind_time := 0.0
var _first_enter_tree := true
var _debug_wirecube_mesh: Mesh = null
var _debug_cubes := []
var _logger := Logger.get_for(self)


func _init():
	_default_shader = load(DEFAULT_SHADER_PATH)
	_material = ShaderMaterial.new()
	_material.shader = _default_shader


func _enter_tree():
	var terrain = _get_terrain()
	if terrain != null:
		terrain.connect("transform_changed", self, "_on_terrain_transform_changed")

		if Engine.editor_hint and _first_enter_tree:
			_first_enter_tree = false
			_edit_auto_pick_index()

		terrain._internal_add_detail_layer(self)

	_update_material()


func _exit_tree():
	var terrain = _get_terrain()
	if terrain != null:
		terrain.disconnect("transform_changed", self, "_on_terrain_transform_changed")
		terrain._internal_remove_detail_layer(self)
	_update_material()
	for k in _chunks.keys():
		_recycle_chunk(k)
	_chunks.clear()


func _edit_auto_pick_index():
	# Automatically pick an unused layer, or create a new one

	var terrain = _get_terrain()
	if terrain == null:
		return

	var terrain_data = terrain.get_data()
	if terrain_data == null or terrain_data.is_locked():
		return

	var auto_index := layer_index
	var others = terrain.get_detail_layers()

	if len(others) > 0:
		var used_layers := []
		for other in others:
			used_layers.append(other.layer_index)
		used_layers.sort()

		auto_index = used_layers[-1] + 1
		for i in range(1, len(used_layers)):
			if used_layers[i - 1] - used_layers[i] > 1:
				# Found a hole, take it instead
				auto_index = used_layers[i] - 1
				break

	layer_index = auto_index

	var map_count = terrain_data.get_map_count(HTerrainData.CHANNEL_DETAIL)
	if layer_index >= map_count:
		layer_index = terrain_data._edit_add_map(HTerrainData.CHANNEL_DETAIL)


func _get_property_list():
	# Dynamic properties coming from the shader
	var props := []
	if _material != null:
		var shader_params = VisualServer.shader_get_param_list(_material.shader.get_rid())
		for p in shader_params:
			if _API_SHADER_PARAMS.has(p.name):
				continue
			var cp = {}
			for k in p:
				cp[k] = p[k]
			cp.name = str("shader_params/", p.name)
			props.append(cp)
	return props


func _get(key: String):
	if key.begins_with("shader_params/"):
		var param_name = key.right(len("shader_params/"))
		return get_shader_param(param_name)


func _set(key: String, v):
	if key.begins_with("shader_params/"):
		var param_name = key.right(len("shader_params/"))
		set_shader_param(param_name, v)


func get_shader_param(param_name: String):
	return _material.get_shader_param(param_name)


func set_shader_param(param_name: String, v):
	_material.set_shader_param(param_name, v)


func _get_terrain():
	if is_inside_tree():
		return get_parent()
	return null


func set_texture(tex: Texture):
	texture = tex
	_material.set_shader_param("u_albedo_alpha", tex)


func get_texture() -> Texture:
	return texture


func set_layer_index(v: int):
	if layer_index == v:
		return
	layer_index = v
	if is_inside_tree():
		_update_material()


func get_layer_index() -> int:
	return layer_index


func set_view_distance(v: float):
	if view_distance == v:
		return
	view_distance = max(v, 1.0)
	if is_inside_tree():
		_update_material()


func get_view_distance() -> float:
	return view_distance


func set_custom_shader(shader: Shader):
	if custom_shader == shader:
		return
	custom_shader = shader
	if custom_shader == null:
		_material.shader = load(DEFAULT_SHADER_PATH)
	else:
		_material.shader = custom_shader

		if Engine.editor_hint:
			# Ability to fork default shader
			if shader.code == "":
				shader.code = _default_shader.code


func get_custom_shader() -> Shader:
	return custom_shader


func set_instance_mesh(p_mesh: Mesh):
	if p_mesh == instance_mesh:
		return
	instance_mesh = p_mesh
	if _multimesh == null:
		_multimesh = MultiMesh.new()
	_multimesh.mesh = _get_used_mesh()


func get_instance_mesh() -> Mesh:
	return instance_mesh


func _get_used_mesh() -> Mesh:
	if instance_mesh == null:
		return DefaultMesh
	return instance_mesh


func set_density(v: float):
	v = clamp(v, 0, 10)
	if v == density:
		return
	density = v
	# If available, we modify the existing multimesh instead of replacing it.
	# DirectMultiMeshInstance does not keep a strong reference to them,
	# so replacing would break pooled instances.
	_regen_multimesh()
	# Crash workaround for Godot 3.1
	# See https://github.com/godotengine/godot/issues/32500
	for k in _chunks:
		var mmi = _chunks[k]
		mmi.set_multimesh(_multimesh)


func get_density() -> float:
	return density


# Updates texture references and values that come from the terrain itself.
# This is typically used when maps are being swapped around in terrain data,
# so we can restore texture references that may break.
func update_material():
	_update_material()
	# Formerly update_ambient_wind, reset


func _notification(what: int):
	match what:
		NOTIFICATION_ENTER_WORLD:
			_set_world(get_world())

		NOTIFICATION_EXIT_WORLD:
			_set_world(null)

		NOTIFICATION_VISIBILITY_CHANGED:
			_set_visible(visible)


func _set_visible(v: bool):
	for k in _chunks:
		var chunk = _chunks[k]
		chunk.set_visible(v)


func _set_world(w: World):
	for k in _chunks:
		var chunk = _chunks[k]
		chunk.set_world(w)


func _on_terrain_transform_changed(gt: Transform):
	_update_material()

	var terrain = _get_terrain()
	if terrain == null:
		_logger.error("Detail layer is not child of a terrain!")
		return

	# Update AABBs, because scale might have changed
	for k in _chunks:
		var mmi = _chunks[k]
		var aabb = _get_chunk_aabb(terrain, Vector3(k.x * CHUNK_SIZE, 0, k.y * CHUNK_SIZE))
		# Nullify XZ translation because that's done by transform already
		aabb.position.x = 0
		aabb.position.z = 0
		mmi.set_aabb(aabb)


func process(delta: float, viewer_pos: Vector3):
	var terrain = _get_terrain()
	if terrain == null:
		_logger.error("DetailLayer processing while terrain is null!")
		return

	var local_viewer_pos = viewer_pos - terrain.translation

	var viewer_cx = local_viewer_pos.x / CHUNK_SIZE
	var viewer_cz = local_viewer_pos.z / CHUNK_SIZE

	var cr = int(view_distance) / CHUNK_SIZE + 1

	var cmin_x = viewer_cx - cr
	var cmin_z = viewer_cz - cr
	var cmax_x = viewer_cx + cr
	var cmax_z = viewer_cz + cr

	var map_res = terrain.get_data().get_resolution()
	var map_scale = terrain.map_scale

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

	if DEBUG and visible:
		_debug_cubes.clear()
		for cz in range(cmin_z, cmax_z):
			for cx in range(cmin_x, cmax_x):
				_add_debug_cube(terrain, _get_chunk_aabb(terrain, Vector3(cx, 0, cz) * CHUNK_SIZE))

	for cz in range(cmin_z, cmax_z):
		for cx in range(cmin_x, cmax_x):

			var cpos2d = Vector2(cx, cz)
			if _chunks.has(cpos2d):
				continue

			var aabb = _get_chunk_aabb(terrain, Vector3(cx, 0, cz) * CHUNK_SIZE)
			var d = (aabb.position + 0.5 * aabb.size).distance_to(local_viewer_pos)

			if d < view_distance:
				_load_chunk(terrain, cx, cz, aabb)

	var to_recycle = []

	for k in _chunks:
		var chunk = _chunks[k]
		var aabb = _get_chunk_aabb(terrain, Vector3(k.x, 0, k.y) * CHUNK_SIZE)
		var d = (aabb.position + 0.5 * aabb.size).distance_to(local_viewer_pos)
		if d > view_distance:
			to_recycle.append(k)

	for k in to_recycle:
		_recycle_chunk(k)

	# Update time manually, so we can accelerate the animation when strength is increased,
	# without causing phase jumps (which would be the case if we just scaled TIME)
	var ambient_wind_frequency = 1.0 + 3.0 * terrain.ambient_wind
	_ambient_wind_time += delta * ambient_wind_frequency
	var awp = _get_ambient_wind_params()
	_material.set_shader_param("u_ambient_wind", awp)


# Gets local-space AABB of a detail chunk.
# This only apply map_scale in Y, because details are not affected by X and Z map scale.
func _get_chunk_aabb(terrain, lpos: Vector3):
	var terrain_scale = terrain.map_scale
	var terrain_data = terrain.get_data()
	var origin_cells_x := int(lpos.x / terrain_scale.x)
	var origin_cells_z := int(lpos.z / terrain_scale.z)
	var size_cells_x := int(CHUNK_SIZE / terrain_scale.x)
	var size_cells_z := int(CHUNK_SIZE / terrain_scale.z)
	
	var aabb = terrain_data.get_region_aabb(
		origin_cells_x, origin_cells_z, size_cells_x, size_cells_z)
		
	aabb.position = Vector3(lpos.x, lpos.y + aabb.position.y * terrain_scale.y, lpos.z)
	aabb.size = Vector3(CHUNK_SIZE, aabb.size.y * terrain_scale.y, CHUNK_SIZE)
	return aabb


func _load_chunk(terrain, cx: int, cz: int, aabb: AABB):
	var lpos = Vector3(cx, 0, cz) * CHUNK_SIZE
	# Terrain scale is not used on purpose. Rotation is not supported.
	var trans = Transform(Basis(), terrain.get_internal_transform().origin + lpos)

	# Nullify XZ translation because that's done by transform already
	aabb.position.x = 0
	aabb.position.z = 0

	var mmi = null
	if len(_multimesh_instance_pool) != 0:
		mmi = _multimesh_instance_pool[-1]
		_multimesh_instance_pool.pop_back()
	else:
		if _multimesh == null:
			_regen_multimesh()
		mmi = DirectMultiMeshInstance.new()
		mmi.set_world(terrain.get_world())
		mmi.set_multimesh(_multimesh)

	mmi.set_material_override(_material)
	mmi.set_transform(trans)
	mmi.set_aabb(aabb)
	mmi.set_visible(visible)

	_chunks[Vector2(cx, cz)] = mmi


func _recycle_chunk(cpos2d: Vector2):
	var mmi = _chunks[cpos2d]
	_chunks.erase(cpos2d)
	mmi.set_visible(false)
	_multimesh_instance_pool.append(mmi)


func _get_ambient_wind_params() -> Vector2:
	var aw = 0.0
	var terrain = _get_terrain()
	if terrain != null:
		aw = terrain.ambient_wind
	# amplitude, time
	return Vector2(aw, _ambient_wind_time)


func _update_material():
	# Sets API shader properties. Custom properties are assumed to be set already
	_logger.debug("Updating detail layer material")

	var terrain_data = null
	var terrain = _get_terrain()
	var it = Transform()
	var normal_basis = Basis()

	if terrain != null:
		var gt = terrain.get_internal_transform()
		it = gt.affine_inverse()
		terrain_data = terrain.get_data()
		# This is needed to properly transform normals if the terrain is scaled
		normal_basis = gt.basis.inverse().transposed()

	var mat = _material

	mat.set_shader_param("u_terrain_inverse_transform", it)
	mat.set_shader_param("u_terrain_normal_basis", normal_basis)
	mat.set_shader_param("u_albedo_alpha", texture)
	mat.set_shader_param("u_view_distance", view_distance)
	mat.set_shader_param("u_ambient_wind", _get_ambient_wind_params())

	var heightmap_texture = null
	var normalmap_texture = null
	var detailmap_texture = null
	var globalmap_texture = null

	if terrain_data != null:
		if terrain_data.is_locked():
			_logger.error("Terrain data locked, can't update detail layer now")
			return

		heightmap_texture = terrain_data.get_texture(HTerrainData.CHANNEL_HEIGHT)
		normalmap_texture = terrain_data.get_texture(HTerrainData.CHANNEL_NORMAL)

		if layer_index < terrain_data.get_map_count(HTerrainData.CHANNEL_DETAIL):
			detailmap_texture = terrain_data.get_texture(HTerrainData.CHANNEL_DETAIL, layer_index)

		if terrain_data.get_map_count(HTerrainData.CHANNEL_GLOBAL_ALBEDO) > 0:
			globalmap_texture = terrain_data.get_texture(HTerrainData.CHANNEL_GLOBAL_ALBEDO)
	else:
		_logger.error("Terrain data is null, can't update detail layer completely")

	mat.set_shader_param("u_terrain_heightmap", heightmap_texture)
	mat.set_shader_param("u_terrain_detailmap", detailmap_texture)
	mat.set_shader_param("u_terrain_normalmap", normalmap_texture)
	mat.set_shader_param("u_terrain_globalmap", globalmap_texture)


# TODO Uncomment in Godot 3.1
#func get_configuration_warning():
#	var terrain = _get_terrain()
#	if terrain == null:
#		return "This node must be under a HTerrain parent"
#	var terrain_data = terrain.get_data()
#	if terrain_data == null:
#		return "The terrain needs data to be assigned"
#	if layer_index <= terrain_data.get_map_count(HTerrainData.CHANNEL_DETAIL):
#		return "This layer's index is out of the range of maps the terrain has"
#	return ""


func _add_debug_cube(terrain, aabb: AABB):
	var world = terrain.get_world()

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


func _regen_multimesh():
	_multimesh = _generate_multimesh(CHUNK_SIZE, density, _get_used_mesh(), _multimesh)


static func _generate_multimesh(resolution: int, density: float, 
	mesh: Mesh, existing_multimesh: MultiMesh) -> MultiMesh:
		
	var position_randomness = 0.5
	var scale_randomness = 0.0
	#var color_randomness = 0.5

	var cell_count = resolution * resolution
	var idensity = int(density)
	var random_instance_count = int(cell_count * (density - floor(density)))
	var total_instance_count = cell_count * idensity + random_instance_count
	
	var mm
	if existing_multimesh != null:
		mm = existing_multimesh
	else:
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.color_format = MultiMesh.COLOR_8BIT

	mm.instance_count = total_instance_count
	mm.mesh = mesh

	# First pass ensures uniform spread
	var i = 0
	for z in resolution:
		for x in resolution:
			for j in idensity:
				
				var pos = Vector3(x, 0, z)
				pos.x += rand_range(-position_randomness, position_randomness)
				pos.z += rand_range(-position_randomness, position_randomness)

				mm.set_instance_color(i, Color(1, 1, 1))
				mm.set_instance_transform(i, \
					Transform(_get_random_instance_basis(scale_randomness), pos))
				i += 1
	
	# Second pass adds the rest
	for j in random_instance_count:
		var pos = Vector3(rand_range(0, resolution), 0, rand_range(0, resolution))
		mm.set_instance_color(i, Color(1, 1, 1))
		mm.set_instance_transform(i, \
			Transform(_get_random_instance_basis(scale_randomness), pos))
		i += 1

	return mm


static func _get_random_instance_basis(scale_randomness: float) -> Basis:
	var sr = rand_range(0, scale_randomness)
	var s = 1.0 + (sr * sr * sr * sr * sr) * 50.0

	var basis = Basis()
	basis = basis.scaled(Vector3(1, s, 1))
	basis = basis.rotated(Vector3(0, 1, 0), rand_range(0, PI))
	
	return basis
