tool

const Logger = preload("./util/logger.gd")

var _shape_rid = RID()
var _body_rid = RID()
var _terrain_transform = Transform()
var _terrain_data = null
var _logger = Logger.get_for(self)


func _init(attached_node):
	_logger.debug("HTerrainCollider: creating body")
	assert(attached_node != null)
	_shape_rid = PhysicsServer.shape_create(PhysicsServer.SHAPE_HEIGHTMAP)
	_body_rid = PhysicsServer.body_create(PhysicsServer.BODY_MODE_STATIC)

	# TODO Let user configure layer and mask
	PhysicsServer.body_set_collision_layer(_body_rid, 1)
	PhysicsServer.body_set_collision_mask(_body_rid, 1)

	# TODO This is an attempt to workaround https://github.com/godotengine/godot/issues/24390
	PhysicsServer.body_set_ray_pickable(_body_rid, false)

	# TODO This is a workaround to https://github.com/godotengine/godot/issues/25304
	PhysicsServer.shape_set_data(_shape_rid, {
		"width": 1,
		"depth": 1,
		"heights": PoolRealArray([0]),
		"min_height": -1,
		"max_height": 1
	})

	PhysicsServer.body_add_shape(_body_rid, _shape_rid)
	
	# This makes collision hits report the provided object as `collider`
	PhysicsServer.body_attach_object_instance_id(_body_rid, attached_node.get_instance_id())


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		_logger.debug("Destroy HTerrainCollider")
		PhysicsServer.free_rid(_body_rid)
		# The shape needs to be freed after the body, otherwise the engine crashes
		PhysicsServer.free_rid(_shape_rid)


func set_transform(transform):
	assert(_body_rid != RID())
	_terrain_transform = transform
	_update_transform()


func set_world(world):
	assert(_body_rid != RID())
	PhysicsServer.body_set_space(_body_rid, world.get_space() if world != null else RID())


func create_from_terrain_data(terrain_data):
	assert(terrain_data != null)
	assert(not terrain_data.is_locked())
	_logger.debug("HTerrainCollider: setting up heightmap")

	_terrain_data = terrain_data

	var aabb = terrain_data.get_aabb()

	var width = terrain_data.get_resolution()
	var depth = terrain_data.get_resolution()
	var height = aabb.size.y

	var shape_data = {
		"width": terrain_data.get_resolution(),
		"depth": terrain_data.get_resolution(),
		"heights": terrain_data.get_all_heights(),
		"min_height": aabb.position.y,
		"max_height": aabb.end.y
	}

	PhysicsServer.shape_set_data(_shape_rid, shape_data)

	_update_transform(aabb)


func _update_transform(aabb=null):
	if _terrain_data == null:
		_logger.debug("HTerrainCollider: terrain data not set yet")
		return

	if aabb == null:
		aabb = _terrain_data.get_aabb()

	var width = _terrain_data.get_resolution()
	var depth = _terrain_data.get_resolution()
	var height = aabb.size.y

	#_terrain_transform

	var trans
	var v = Engine.get_version_info()
	if v.major == 3 and v.minor <= 1:
		# Bullet centers the shape to its overall AABB so we need to move it to match the visuals
		trans = Transform(Basis(), 0.5 * Vector3(width, height, depth) + Vector3(0, aabb.position.y, 0))
	else:
		# In 3.2, vertical centering changed.
		# https://github.com/godotengine/godot/pull/28326
		trans = Transform(Basis(), 0.5 * Vector3(width, 0, depth))
	
	# And then apply the terrain transform
	trans = _terrain_transform * trans

	PhysicsServer.body_set_state(_body_rid, PhysicsServer.BODY_STATE_TRANSFORM, trans)
	# Cannot use shape transform when scaling is involved,
	# because Godot is undoing that scale for some reason.
	# See https://github.com/Zylann/godot_heightmap_plugin/issues/70
	#PhysicsServer.body_set_shape_transform(_body_rid, 0, trans)
