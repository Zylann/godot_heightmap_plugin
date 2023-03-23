@tool
# Shows a cursor on top of the terrain to preview where the brush will paint

# TODO Use an actual decal node, it wasn't available in Godot 3

const HT_DirectMeshInstance = preload("../../util/direct_mesh_instance.gd")
const HTerrain = preload("../../hterrain.gd")
const HTerrainData = preload("../../hterrain_data.gd")
const HT_Util = preload("../../util/util.gd")

var _mesh_instance : HT_DirectMeshInstance
var _mesh : PlaneMesh
var _material = ShaderMaterial.new()
#var _debug_mesh = CubeMesh.new()
#var _debug_mesh_instance = null

var _terrain : HTerrain = null


func _init():
	_material.shader = load("res://addons/zylann.hterrain/tools/brush/decal.gdshader")
	_mesh_instance = HT_DirectMeshInstance.new()
	_mesh_instance.set_material(_material)
	
	_mesh = PlaneMesh.new()
	_mesh_instance.set_mesh(_mesh)
	
	#_debug_mesh_instance = DirectMeshInstance.new()
	#_debug_mesh_instance.set_mesh(_debug_mesh)


func set_size(size: float):
	_mesh.size = Vector2(size, size)
	# Must line up to terrain vertex policy, so must apply an off-by-one.
	# If I don't do that, the brush will appear to wobble above the ground
	var ss := size - 1
	# Don't subdivide too much
	while ss > 50:
		ss /= 2
	_mesh.subdivide_width = ss
	_mesh.subdivide_depth = ss


#func set_shape(shape_image):
#	set_size(shape_image.get_width())


func _on_terrain_transform_changed(terrain_global_trans: Transform3D):
	var inv = terrain_global_trans.affine_inverse()
	_material.set_shader_parameter("u_terrain_inverse_transform", inv)

	var normal_basis = terrain_global_trans.basis.inverse().transposed()
	_material.set_shader_parameter("u_terrain_normal_basis", normal_basis)


func set_terrain(terrain: HTerrain):
	if _terrain == terrain:
		return

	if _terrain != null:
		_terrain.transform_changed.disconnect(_on_terrain_transform_changed)
		_mesh_instance.exit_world()
		#_debug_mesh_instance.exit_world()

	_terrain = terrain

	if _terrain != null:
		_terrain.transform_changed.connect(_on_terrain_transform_changed)
		_on_terrain_transform_changed(_terrain.get_internal_transform())
		_mesh_instance.enter_world(terrain.get_world_3d())
		#_debug_mesh_instance.enter_world(terrain.get_world())

	update_visibility()


func set_position(p_local_pos: Vector3):
	assert(_terrain != null)
	assert(typeof(p_local_pos) == TYPE_VECTOR3)
	
	# Set custom AABB (in local cells) because the decal is displaced by shader
	var data = _terrain.get_data()
	if data != null:
		var r = _mesh.size / 2
		var aabb = data.get_region_aabb( \
			int(p_local_pos.x - r.x), \
			int(p_local_pos.z - r.y), \
			int(2 * r.x), \
			int(2 * r.y))
		aabb.position = Vector3(-r.x, aabb.position.y, -r.y)
		_mesh.custom_aabb = aabb
		#_debug_mesh.size = aabb.size
	
	var trans = Transform3D(Basis(), p_local_pos)
	var terrain_gt = _terrain.get_internal_transform()
	trans = terrain_gt * trans
	_mesh_instance.set_transform(trans)
	#_debug_mesh_instance.set_transform(trans)


# This is called very often so it should be cheap
func update_visibility():
	var heightmap = _get_heightmap(_terrain)
	if heightmap == null:
		# I do this for refcounting because heightmaps are large resources
		_material.set_shader_parameter("u_terrain_heightmap", null)
		_mesh_instance.set_visible(false)
		#_debug_mesh_instance.set_visible(false)
	else:
		_material.set_shader_parameter("u_terrain_heightmap", heightmap)
		_mesh_instance.set_visible(true)
		#_debug_mesh_instance.set_visible(true)


func _get_heightmap(terrain):
	if terrain == null:
		return null
	var data = terrain.get_data()
	if data == null:
		return null
	return data.get_texture(HTerrainData.CHANNEL_HEIGHT)

