tool
# Shows a cursor on top of the terrain to preview where the brush will paint

const DirectMeshInstance = preload("../../util/direct_mesh_instance.gd")
const HTerrainData = preload("../../hterrain_data.gd")

var _mesh_instance = null
var _mesh = null
var _material = ShaderMaterial.new()

var _terrain = null


func _init():
	_material.shader = load("res://addons/zylann.hterrain/tools/brush/decal.shader")
	_mesh_instance = DirectMeshInstance.new()
	_mesh_instance.set_material(_material)
	
	_mesh = PlaneMesh.new()
	_mesh_instance.set_mesh(_mesh)


func set_size(size):
	_mesh.size = Vector2(size, size)
	# Must line up to terrain vertex policy, so must apply an off-by-one.
	# If I don't do that, the brush will appear to wobble above the ground
	_mesh.subdivide_width = size - 1
	_mesh.subdivide_depth = size - 1


func set_shape(shape_grid):
	# TODO In the future, this might be a texture
	set_size(len(shape_grid))


func set_visible(visible):
	_mesh_instance.set_visible(visible)


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

	_terrain = terrain

	if _terrain != null:
		_terrain.connect("transform_changed", self, "_on_terrain_transform_changed")
		_on_terrain_transform_changed(_terrain.get_internal_transform())

	var heightmap = _get_heightmap(terrain)
	
	if heightmap == null:
		_mesh_instance.exit_world()
		# I do this for refcounting because heightmaps are large resources
		_material.set_shader_param("u_terrain_heightmap", null)
		
	else:
		_mesh_instance.enter_world(terrain.get_world())
		
		_material.set_shader_param("u_terrain_heightmap", heightmap)


func set_position(p_local_pos):
	assert(_terrain != null)
	assert(typeof(p_local_pos) == TYPE_VECTOR3)
	var trans = Transform(Basis(), p_local_pos)
	var terrain_gt = _terrain.get_internal_transform()
	trans = terrain_gt * trans
	_mesh_instance.set_transform(trans)


func _get_heightmap(terrain):
	if terrain == null:
		return null
	var data = terrain.get_data()
	if data == null:
		return null
	return data.get_texture(HTerrainData.CHANNEL_HEIGHT)

