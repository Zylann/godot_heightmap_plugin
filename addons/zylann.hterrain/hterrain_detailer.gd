tool

	
const Logger = preload("./util/logger.gd")
var HTerrain = load("res://addons/zylann.hterrain/hterrain.gd")

const CHUNK_SIZE = 32

var _terrain = null
var _detail_layers := []

# Vector2 => AABB
var _aabbs := {}

var _logger := Logger.get_for(self)


func set_terrain(terrain):
	assert(terrain is HTerrain)
	_terrain = terrain
	_terrain.connect("transform_changed", self, "_on_terrain_transform_changed")
	

func update_materials():
	for layer in _detail_layers:
		layer.update_material()


func add_map(index: int):
	for layer in _detail_layers:
		# Shift indexes up since one was inserted
		if layer.layer_index >= index:
			layer.layer_index += 1
		layer.update_material()


func remove_map(index: int):
	for layer in _detail_layers:
		# Shift indexes down since one was removed
		if layer.layer_index > index:
			layer.layer_index -= 1
		layer.update_material()


func _on_terrain_transform_changed(gt: Transform):
	# Recalculate aabbs because the transform changed
	_calculate_aabbs()
	
	for layer in _detail_layers:
		layer.update_material()
		layer.set_terrain_transform(_terrain, _aabbs)
		
		
func process(delta: float, viewer_pos: Vector3):
	if _terrain == null:
		_logger.debug("HTerrainDetailer: terrain not set yet")
		return
		
	if _aabbs.empty():
		_calculate_aabbs()

	var local_viewer_pos = _terrain.global_transform.affine_inverse() * viewer_pos
	
	var viewer_cx = local_viewer_pos.x / CHUNK_SIZE
	var viewer_cz = local_viewer_pos.z / CHUNK_SIZE

	var map_res = _terrain.get_data().get_resolution()
	var map_scale = _terrain.map_scale

	var terrain_size_x = map_res * map_scale.x
	var terrain_size_z = map_res * map_scale.z

	var terrain_chunks_x = terrain_size_x / CHUNK_SIZE
	var terrain_chunks_z = terrain_size_z / CHUNK_SIZE
		
	var max_view_distance = 0
	for layer in _detail_layers:
		max_view_distance = max(max_view_distance, layer.view_distance)
			
	var cr = int(max_view_distance) / CHUNK_SIZE + 1
	
	var cmin_x = viewer_cx - cr
	var cmin_z = viewer_cz - cr
	var cmax_x = viewer_cx + cr
	var cmax_z = viewer_cz + cr
	
	if cmin_x < 0:
		cmin_x = 0
	if cmin_z < 0:
		cmin_z = 0
	if cmax_x > terrain_chunks_x:
		cmax_x = terrain_chunks_x
	if cmax_z > terrain_chunks_z:
		cmax_z = terrain_chunks_z
			
	for layer in _detail_layers:
		if !layer.visible:
			continue
		layer.update(_terrain, local_viewer_pos, Vector2(cmin_x, cmin_z), Vector2(cmax_x, cmax_z), _aabbs)
		layer.update_wind_time(_terrain, delta)


func add_layer(layer):
	assert(_detail_layers.find(layer) == -1)
	_detail_layers.append(layer)


func remove_layer(layer):
	assert(_detail_layers.find(layer) != -1)
	_detail_layers.erase(layer)


func get_layers() -> Array:
	return _detail_layers.duplicate()
	

func recalculate_aabbs():
	_calculate_aabbs()
	
	
func recalculate_region_aabbs(min_x, min_y, size_x, size_y):
	var terrain_data = _terrain.get_data()
	var map_scale = _terrain.map_scale
	
	var size_cells_x := int(CHUNK_SIZE / map_scale.x)
	var size_cells_z := int(CHUNK_SIZE / map_scale.z)
	
	var cmin_x = min_x * map_scale.x / CHUNK_SIZE
	var cmax_x = (min_x + size_x) * map_scale.x / CHUNK_SIZE
	var cmin_z = min_y * map_scale.z / CHUNK_SIZE
	var cmax_z = (min_y + size_y) * map_scale.z / CHUNK_SIZE

	for cz in range(cmin_z, cmax_z):
		for cx in range(cmin_x, cmax_x):
			var aabb = terrain_data.get_region_aabb(
				cx * size_cells_x, cz * size_cells_z, size_cells_x, size_cells_z)
				
			aabb.position = Vector3(cx * CHUNK_SIZE, aabb.position.y * map_scale.y, cz * CHUNK_SIZE)
			aabb.size = Vector3(CHUNK_SIZE, aabb.size.y * map_scale.y, CHUNK_SIZE)
			_aabbs[Vector2(cx, cz)] = aabb
	
	
# Calculates local-space AABBs for all detail chunks.
# This only apply map_scale in Y, because details are not affected by X and Z map scale.
func _calculate_aabbs():
	if !_aabbs.empty():
		_aabbs.clear()
	
	var terrain_data = _terrain.get_data()
	var map_res = terrain_data.get_resolution()
	var map_scale = _terrain.map_scale

	var terrain_size_x = map_res * map_scale.x
	var terrain_size_z = map_res * map_scale.z

	var terrain_chunks_x = terrain_size_x / CHUNK_SIZE
	var terrain_chunks_z = terrain_size_z / CHUNK_SIZE
	
	var size_cells_x := int(CHUNK_SIZE / map_scale.x)
	var size_cells_z := int(CHUNK_SIZE / map_scale.z)
	
	for cz in range(0, terrain_chunks_z):
		for cx in range(0, terrain_chunks_x):			
			var aabb = terrain_data.get_region_aabb(
				cx * size_cells_x, cz * size_cells_z, size_cells_x, size_cells_z)
		
			aabb.position = Vector3(cx * CHUNK_SIZE, aabb.position.y * map_scale.y, cz * CHUNK_SIZE)
			aabb.size = Vector3(CHUNK_SIZE, aabb.size.y * map_scale.y, CHUNK_SIZE)
			_aabbs[Vector2(cx, cz)] = aabb
