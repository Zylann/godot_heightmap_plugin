@tool

const HT_Logger = preload("./util/logger.gd")
const HTerrainData = preload("./hterrain_data.gd")

var _shape_rid := RID()
var _body_rid := RID()
var _terrain_transform := Transform3D()
var _terrain_data : HTerrainData = null
var _logger = HT_Logger.get_for(self)


func _init(attached_node: Node, initial_layer: int, initial_mask: int):
	_logger.debug("HTerrainCollider: creating body")
	assert(attached_node != null)
	_shape_rid = PhysicsServer3D.heightmap_shape_create()
	_body_rid = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body_rid, PhysicsServer3D.BODY_MODE_STATIC)

	PhysicsServer3D.body_set_collision_layer(_body_rid, initial_layer)
	PhysicsServer3D.body_set_collision_mask(_body_rid, initial_mask)

	# TODO This is an attempt to workaround https://github.com/godotengine/godot/issues/24390
	PhysicsServer3D.body_set_ray_pickable(_body_rid, false)

	# Assigng dummy data
	# TODO This is a workaround to https://github.com/godotengine/godot/issues/25304
	PhysicsServer3D.shape_set_data(_shape_rid, {
		"width": 2,
		"depth": 2,
		"heights": PackedFloat32Array([0, 0, 0, 0]),
		"min_height": -1,
		"max_height": 1
	})

	PhysicsServer3D.body_add_shape(_body_rid, _shape_rid)
	
	# This makes collision hits report the provided object as `collider`
	PhysicsServer3D.body_attach_object_instance_id(_body_rid, attached_node.get_instance_id())


func set_collision_layer(layer: int):
	PhysicsServer3D.body_set_collision_layer(_body_rid, layer)


func set_collision_mask(mask: int):
	PhysicsServer3D.body_set_collision_mask(_body_rid, mask)


func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		_logger.debug("Destroy HTerrainCollider")
		PhysicsServer3D.free_rid(_body_rid)
		# The shape needs to be freed after the body, otherwise the engine crashes
		PhysicsServer3D.free_rid(_shape_rid)


func set_transform(transform: Transform3D):
	assert(_body_rid != RID())
	_terrain_transform = transform
	_update_transform()


func set_world(world: World3D):
	assert(_body_rid != RID())
	PhysicsServer3D.body_set_space(_body_rid, world.get_space() if world != null else RID())


func create_from_terrain_data(terrain_data: HTerrainData):
	assert(terrain_data != null)
	assert(not terrain_data.is_locked())
	_logger.debug("HTerrainCollider: setting up heightmap")

	_terrain_data = terrain_data

	var aabb := terrain_data.get_aabb()

	var width := terrain_data.get_resolution()
	var depth := terrain_data.get_resolution()
	var height := aabb.size.y

	var shape_data = {
		"width": terrain_data.get_resolution(),
		"depth": terrain_data.get_resolution(),
		"heights": terrain_data.get_all_heights(),
		"min_height": aabb.position.y,
		"max_height": aabb.end.y
	}

	PhysicsServer3D.shape_set_data(_shape_rid, shape_data)

	_update_transform(aabb)


func _update_transform(aabb=null):
	if _terrain_data == null:
		_logger.debug("HTerrainCollider: terrain data not set yet")
		return

#	if aabb == null:
#		aabb = _terrain_data.get_aabb()

	var width := _terrain_data.get_resolution()
	var depth := _terrain_data.get_resolution()
	#var height = aabb.size.y

	#_terrain_transform

	var trans := Transform3D(Basis(), 0.5 * Vector3(width - 1, 0, depth - 1))
	
	# And then apply the terrain transform
	trans = _terrain_transform * trans

	PhysicsServer3D.body_set_state(_body_rid, PhysicsServer3D.BODY_STATE_TRANSFORM, trans)
	# Cannot use shape transform when scaling is involved,
	# because Godot is undoing that scale for some reason.
	# See https://github.com/Zylann/godot_heightmap_plugin/issues/70
	#PhysicsServer.body_set_shape_transform(_body_rid, 0, trans)
