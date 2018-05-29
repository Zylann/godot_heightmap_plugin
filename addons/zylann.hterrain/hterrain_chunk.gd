tool

var cell_origin_x = 0
var cell_origin_y = 0

var _visible
var _active
var _pending_update

var _mesh_instance = null
# Need to keep a reference so that the mesh RID doesn't get freed
# TODO Use RID directly, no need to keep all those meshes in memory
var _mesh = null


func _init(p_parent, p_cell_x, p_cell_y, p_material):
	assert(p_parent is Spatial)
	assert(typeof(p_cell_x) == TYPE_INT)
	assert(typeof(p_cell_y) == TYPE_INT)
	assert(p_material is Material)
	
	cell_origin_x = p_cell_x
	cell_origin_y = p_cell_y

	var vs = VisualServer

	_mesh_instance = vs.instance_create()

	if p_material != null:
		vs.instance_geometry_set_material_override(_mesh_instance, p_material.get_rid())

	var world = p_parent.get_world()
	if world != null:
		vs.instance_set_scenario(_mesh_instance, world.get_scenario())

	_visible = true
	# TODO Is this needed?
	vs.instance_set_visible(_mesh_instance, _visible)

	_active = true
	_pending_update = false


func _notification(p_what):
	if p_what == NOTIFICATION_PREDELETE:
		if _mesh_instance != RID():
			VisualServer.free_rid(_mesh_instance)
			_mesh_instance = RID()


func is_active():
	return _active


func set_active(a):
	_active = a


func is_pending_update():
	return _pending_update


func set_pending_update(p):
	_pending_update = p


func enter_world(world):
	assert(_mesh_instance != RID())
	VisualServer.instance_set_scenario(_mesh_instance, world.get_scenario())


func exit_world():
	assert(_mesh_instance != RID())
	VisualServer.instance_set_scenario(_mesh_instance, RID())


func parent_transform_changed(parent_transform):
	assert(_mesh_instance != RID())
	var local_transform = Transform(Basis(), Vector3(cell_origin_x, 0, cell_origin_y))
	var world_transform = parent_transform * local_transform
	VisualServer.instance_set_transform(_mesh_instance, world_transform)


func set_mesh(mesh):
	assert(_mesh_instance != RID())
	if mesh == _mesh:
		return
	VisualServer.instance_set_base(_mesh_instance, mesh.get_rid() if mesh != null else RID())
	_mesh = mesh


func set_material(material):
	assert(_mesh_instance != RID())
	VisualServer.instance_geometry_set_material_override( \
		_mesh_instance, material.get_rid() if material != null else RID())


func set_visible(visible):
	assert(_mesh_instance != RID())
	VisualServer.instance_set_visible(_mesh_instance, visible)
	_visible = visible


func is_visible():
	return _visible


func set_aabb(aabb):
	assert(_mesh_instance != RID())
	VisualServer.instance_set_custom_aabb(_mesh_instance, aabb)

