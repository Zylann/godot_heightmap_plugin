tool
# Shows a cursor on top of the terrain to preview where the brush will paint

const DirectMeshInstance = preload("../../util/direct_mesh_instance.gd")
const HTerrainData = preload("../../hterrain_data.gd")
const Util = preload("../../util/util.gd")

var _mesh_instance = null
var _mesh = null
var _material = ShaderMaterial.new()
#var _debug_mesh = CubeMesh.new()
#var _debug_mesh_instance = null

var _terrain = null


func _init():
	_material.shader = load("res://addons/zylann.hterrain/tools/brush/decal.shader")
	_mesh_instance = DirectMeshInstance.new()
	_mesh_instance.set_material(_material)
		
	_mesh = PlaneMesh.new()
	_mesh_instance.set_mesh(_mesh)
	
	#_debug_mesh_instance = DirectMeshInstance.new()
	#_debug_mesh_instance.set_mesh(_debug_mesh)


func set_size(size):
	_mesh.size = Vector2(size, size)
	# Must line up to terrain vertex policy, so must apply an off-by-one.
	# If I don't do that, the brush will appear to wobble above the ground
	var ss = size - 1
	# Don't subdivide too much
	if ss > 50:
		ss /= 2
	if ss > 50:
		ss /= 2
	_mesh.subdivide_width = ss
	_mesh.subdivide_depth = ss


#func set_shape(shape_image):
#	set_size(shape_image.get_width())


func _on_terrain_transform_changed(terrain_global_trans):
	var inv = terrain_global_trans.affine_inverse()
	_material.set_shader_param("u_terrain_inverse_transform", inv)

	var normal_basis = terrain_global_trans.basis.inverse().transposed()
	_material.set_shader_param("u_terrain_normal_basis", normal_basis)


func set_terrain(terrain):
	if _terrain == terrain:
		return

	if _terrain != null:
		_terrain.disconnect("transform_changed", self, "_on_terrain_transform_changed")
		_mesh_instance.exit_world()
		#_debug_mesh_instance.exit_world()

	_terrain = terrain

	if _terrain != null:
		_terrain.connect("transform_changed", self, "_on_terrain_transform_changed")
		_on_terrain_transform_changed(_terrain.get_internal_transform())
		_mesh_instance.enter_world(terrain.get_world())
		#_debug_mesh_instance.enter_world(terrain.get_world())

	update_visibility()


func set_position(p_local_pos):
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
	
	var trans = Transform(Basis(), p_local_pos)
	var terrain_gt = _terrain.get_internal_transform()
	trans = terrain_gt * trans
	_mesh_instance.set_transform(trans)
	#_debug_mesh_instance.set_transform(trans)


# This is called very often so it should be cheap
func update_visibility():
	var heightmap = _get_heightmap(_terrain)
	if heightmap == null:
		# I do this for refcounting because heightmaps are large resources
		_material.set_shader_param("u_terrain_heightmap", null)
		_mesh_instance.set_visible(false)
		#_debug_mesh_instance.set_visible(false)
	else:
		_material.set_shader_param("u_terrain_heightmap", heightmap)
		_mesh_instance.set_visible(true)
		#_debug_mesh_instance.set_visible(true)


func _get_heightmap(terrain):
	if terrain == null:
		return null
	var data = terrain.get_data()
	if data == null:
		return null
	return data.get_texture(HTerrainData.CHANNEL_HEIGHT)

