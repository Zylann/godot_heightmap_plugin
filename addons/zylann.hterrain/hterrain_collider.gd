tool

var _shape_rid = RID()
var _body_rid = RID()
var _terrain_transform = Transform()
var _terrain_data = null


func _init():
	print("Create HTerrainCollider")
	_shape_rid = PhysicsServer.shape_create(PhysicsServer.SHAPE_HEIGHTMAP)
	_body_rid = PhysicsServer.body_create(PhysicsServer.BODY_MODE_STATIC)
	
	# TODO Let user configure layer and mask
	PhysicsServer.body_set_collision_layer(_body_rid, 1)
	PhysicsServer.body_set_collision_mask(_body_rid, 1)

	PhysicsServer.body_add_shape(_body_rid, _shape_rid)


func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		print("Destroy HTerrainCollider")
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
	print("Creating terrain collider shape")
	
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
	if aabb == null:
		aabb = _terrain_data.get_aabb()

	var width = _terrain_data.get_resolution()
	var depth = _terrain_data.get_resolution()
	var height = aabb.size.y

	#_terrain_transform

	# Bullet centers the shape to its overall AABB so we need to move it to match the visuals
	var trans = Transform(Basis(), 0.5 * Vector3(width, height, depth) + Vector3(0, aabb.position.y, 0))

	# And then apply the terrain transform
	trans = _terrain_transform * trans

	PhysicsServer.body_set_shape_transform(_body_rid, 0, trans)
