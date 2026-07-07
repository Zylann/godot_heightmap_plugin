@tool

var cell_origin := Vector2i()

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
func _init(p_parent: Node3D, p_cell_origin: Vector2i, p_material: Material) -> void:
	cell_origin = p_cell_origin

	var rs := RenderingServer

	_mesh_instance = rs.instance_create()
	
	# Godot 4.4 introduced physics interpolation again, and it's always on.
	# Unfortunately that breaks terrain chunks, which start to flicker when created,
	# even though they don't move. Terrains are inherently static so that feature must not be used.
	# This feature is new in Godot 4.4 so to maintain compatibility with previous versions
	# we have to test if the method is available.
	# See https://github.com/Zylann/godot_heightmap_plugin/issues/475
	if rs.has_method(&"instance_set_interpolated"):
		rs.call(&"instance_set_interpolated", _mesh_instance, false)

	if p_material != null:
		rs.instance_geometry_set_material_override(_mesh_instance, p_material.get_rid())

	var world := p_parent.get_world_3d()
	if world != null:
		rs.instance_set_scenario(_mesh_instance, world.get_scenario())

	_visible = true
	# TODO Is this needed?
	rs.instance_set_visible(_mesh_instance, _visible)

	_active = true
	_pending_update = false


func _notification(p_what: int) -> void:
	if p_what == NOTIFICATION_PREDELETE:
		if _mesh_instance != RID():
			RenderingServer.free_rid(_mesh_instance)
			_mesh_instance = RID()


func is_active() -> bool:
	return _active


func set_active(a: bool) -> void:
	_active = a


func is_pending_update() -> bool:
	return _pending_update


func set_pending_update(p: bool) -> void:
	_pending_update = p


func enter_world(world: World3D) -> void:
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_scenario(_mesh_instance, world.get_scenario())


func exit_world() -> void:
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_scenario(_mesh_instance, RID())


func parent_transform_changed(parent_transform: Transform3D) -> void:
	assert(_mesh_instance != RID())
	var local_transform := Transform3D(Basis(), Vector3(cell_origin.x, 0, cell_origin.y))
	var world_transform := parent_transform * local_transform
	RenderingServer.instance_set_transform(_mesh_instance, world_transform)


func set_mesh(mesh: Mesh) -> void:
	assert(_mesh_instance != RID())
	if mesh == _mesh:
		return
	RenderingServer.instance_set_base(_mesh_instance, mesh.get_rid() if mesh != null else RID())
	_mesh = mesh


func set_material(material: Material) -> void:
	assert(_mesh_instance != RID())
	RenderingServer.instance_geometry_set_material_override( \
		_mesh_instance, material.get_rid() if material != null else RID())


func set_visible(visible: bool) -> void:
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_visible(_mesh_instance, visible)
	_visible = visible


func is_visible() -> bool:
	return _visible


func set_aabb(aabb: AABB) -> void:
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_custom_aabb(_mesh_instance, aabb)


func set_render_layer_mask(mask: int) -> void:
	assert(_mesh_instance != RID())
	RenderingServer.instance_set_layer_mask(_mesh_instance, mask)


func set_cast_shadow_setting(setting: int) -> void:
	assert(_mesh_instance != RID())
	RenderingServer.instance_geometry_set_cast_shadows_setting(_mesh_instance, setting)
