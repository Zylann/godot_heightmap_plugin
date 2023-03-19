@tool

# Implementation of MeshInstance which doesn't use the scene tree

var _mesh_instance := RID()
# Need to keep a reference so that the mesh RID doesn't get freed
var _mesh : Mesh


func _init():
	var rs = RenderingServer
	_mesh_instance = rs.instance_create()
	rs.instance_set_visible(_mesh_instance, true)


func _notification(p_what: int):
	if p_what == NOTIFICATION_PREDELETE:
		if _mesh_instance != RID():
			RenderingServer.free_rid(_mesh_instance)
			_mesh_instance = RID()


func enter_world(world: World3D):
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_scenario(_mesh_instance, world.get_scenario())


func exit_world():
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_scenario(_mesh_instance, RID())


func set_world(world: World3D):
	if world != null:
		enter_world(world)
	else:
		exit_world()


func set_transform(world_transform: Transform3D):
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_transform(_mesh_instance, world_transform)


func set_mesh(mesh: Mesh):
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_base(_mesh_instance, mesh.get_rid() if mesh != null else RID())
	_mesh = mesh


func set_material(material: Material):
	assert(_mesh_instance != RID())
	RenderingServer.instance_geometry_set_material_override( \
		_mesh_instance, material.get_rid() if material != null else RID())


func set_visible(visible: bool):
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_visible(_mesh_instance, visible)


func set_aabb(aabb: AABB):
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_custom_aabb(_mesh_instance, aabb)

