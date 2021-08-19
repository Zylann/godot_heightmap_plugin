
# Implementation of MultiMeshInstance which doesn't use the scene tree

var _multimesh_instance := RID()


func _init():
	_multimesh_instance = VisualServer.instance_create()


func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		VisualServer.free_rid(_multimesh_instance)


func set_world(world: World):
	VisualServer.instance_set_scenario(
		_multimesh_instance, world.get_scenario() if world != null else RID())


func set_visible(visible: bool):
	VisualServer.instance_set_visible(_multimesh_instance, visible)


func set_transform(trans: Transform):
	VisualServer.instance_set_transform(_multimesh_instance, trans)


func set_multimesh(mm: MultiMesh):
	VisualServer.instance_set_base(_multimesh_instance, mm.get_rid() if mm != null else RID())


func set_material_override(material: Material):
	VisualServer.instance_geometry_set_material_override( \
		_multimesh_instance, material.get_rid() if material != null else RID())


func set_aabb(aabb: AABB):
	VisualServer.instance_set_custom_aabb(_multimesh_instance, aabb)


func set_layer_mask(mask: int):
	VisualServer.instance_set_layer_mask(_multimesh_instance, mask)
