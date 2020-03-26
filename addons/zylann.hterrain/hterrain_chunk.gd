tool

var cell_origin_x := 0
var cell_origin_y := 0

var _visible : bool
# This is true when the chunk is meant to be displayed.
# A chunk can be active and hidden (due to the terrain being hidden).
var _active : bool

var _pending_update : bool

var _mesh_instance : RID
# Need to keep a reference so that the mesh RID doesn't get freed
# TODO Use RID directly, no need to keep all those meshes in memory
var _mesh : Mesh = null


# TODO p_parent is HTerrain, can't add type hint due to cyclic reference
func _init(p_parent, p_cell_x: int, p_cell_y: int, p_material: Material):
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


func _notification(p_what: int):
	if p_what == NOTIFICATION_PREDELETE:
		if _mesh_instance != RID():
			VisualServer.free_rid(_mesh_instance)
			_mesh_instance = RID()


func is_active() -> bool:
	return _active


func set_active(a):
	_active = a


func is_pending_update() -> bool:
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


func set_mesh(mesh: Mesh):
	assert(_mesh_instance != RID())
	if mesh == _mesh:
		return
	VisualServer.instance_set_base(_mesh_instance, mesh.get_rid() if mesh != null else RID())
	_mesh = mesh


func set_material(material: Material):
	assert(_mesh_instance != RID())
	VisualServer.instance_geometry_set_material_override( \
		_mesh_instance, material.get_rid() if material != null else RID())


func set_visible(visible: bool):
	assert(_mesh_instance != RID())
	VisualServer.instance_set_visible(_mesh_instance, visible)
	_visible = visible


func is_visible() -> bool:
	return _visible


func set_aabb(aabb: AABB):
	assert(_mesh_instance != RID())
	VisualServer.instance_set_custom_aabb(_mesh_instance, aabb)

