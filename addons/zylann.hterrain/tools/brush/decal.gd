tool
# Shows a cursor on top of the terrain to preview where the brush will paint

const DirectMeshInstance = preload("direct_mesh_instance.gd")
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


func set_terrain(terrain):
	_terrain = terrain
	var heightmap = _get_heightmap(terrain)
	
	if heightmap == null:
		_mesh_instance.exit_world()
		# I do this for refcounting because heightmaps are large resources
		_material.set_shader_param("heightmap", null)
		
	else:
		_mesh_instance.enter_world(terrain.get_world())
		
		_material.set_shader_param("heightmap", heightmap)
				
		var gt = terrain.get_global_transform()
		var t = gt.affine_inverse()
		_material.set_shader_param("heightmap_inverse_transform", t)


func set_position(p_local_pos):
	assert(_terrain != null)
	assert(typeof(p_local_pos) == TYPE_VECTOR3)
	var parent_transform = _terrain.global_transform
	var pos = parent_transform * p_local_pos
	_mesh_instance.set_transform(Transform(Basis(), pos))


func _get_heightmap(terrain):
	if terrain == null:
		return null
	var data = terrain.get_data()
	if data == null:
		return null
	return data.get_texture(HTerrainData.CHANNEL_HEIGHT)

