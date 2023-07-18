@tool

# Implementation of MultiMeshInstance which doesn't use the scene tree

var _multimesh_instance := RID()


func _init():
	_multimesh_instance = RenderingServer.instance_create()


func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		RenderingServer.free_rid(_multimesh_instance)


func set_world(world: World3D):
	RenderingServer.instance_set_scenario(
		_multimesh_instance, world.get_scenario() if world != null else RID())


func set_visible(visible: bool):
	RenderingServer.instance_set_visible(_multimesh_instance, visible)


func set_transform(trans: Transform3D):
	RenderingServer.instance_set_transform(_multimesh_instance, trans)


func set_multimesh(mm: MultiMesh):
	RenderingServer.instance_set_base(_multimesh_instance, mm.get_rid() if mm != null else RID())


func set_material_override(material: Material):
	RenderingServer.instance_geometry_set_material_override( \
		_multimesh_instance, material.get_rid() if material != null else RID())


func set_aabb(aabb: AABB):
	RenderingServer.instance_set_custom_aabb(_multimesh_instance, aabb)


func set_layer_mask(mask: int):
	RenderingServer.instance_set_layer_mask(_multimesh_instance, mask)


func set_cast_shadow(cast_shadow: int):
	RenderingServer.instance_geometry_set_cast_shadows_setting(_multimesh_instance, cast_shadow)
