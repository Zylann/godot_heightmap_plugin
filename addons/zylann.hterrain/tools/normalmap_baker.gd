
# Bakes normals asynchronously in the editor as the heightmap gets modified.
# It uses the heightmap texture to change the normalmap image, which is then uploaded like an edit.
# This is probably not a nice method GPU-wise, but it's way faster than GDScript.

@tool
extends Node

const _bump2normal_shader_path = "res://addons/zylann.hterrain/tools/bump2normal_tex.gdshader"

const VIEWPORT_SIZE = 64

const STATE_PENDING = 0
const STATE_PROCESSING = 1

var _viewport : SubViewport = null
var _ci : Sprite2D = null
var _pending_tiles_grid := {} # Dictionary[Vector2i, int] (typed dicts only from 4.4)
var _pending_tiles_queue : Array[Vector2i] = []
var _processing_tile : Vector2i
var _is_processing_tile := false
var _terrain_data : HTerrainData = null


func _init() -> void:
	assert(VIEWPORT_SIZE <= HTerrainData.MIN_RESOLUTION)
	_viewport = SubViewport.new()
	_viewport.size = Vector2(VIEWPORT_SIZE + 2, VIEWPORT_SIZE + 2)
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	# We only render 2D, but we don't want the parent world to interfere
	_viewport.world_3d = World3D.new()
	_viewport.own_world_3d = true
	add_child(_viewport)
	
	var mat := ShaderMaterial.new()
	mat.shader = load(_bump2normal_shader_path)
	
	_ci = Sprite2D.new()
	_ci.centered = false
	_ci.material = mat
	_viewport.add_child(_ci)
	
	set_process(false)


func set_terrain_data(data: HTerrainData) -> void:
	if data == _terrain_data:
		return

	_pending_tiles_grid.clear()
	_pending_tiles_queue.clear()
	_ci.texture = null
	set_process(false)
	
	if data == null:
		_terrain_data.map_changed.disconnect(_on_terrain_data_map_changed)
		_terrain_data.resolution_changed.disconnect(_on_terrain_data_resolution_changed)

	_terrain_data = data
	
	if _terrain_data != null:
		_terrain_data.map_changed.connect(_on_terrain_data_map_changed)
		_terrain_data.resolution_changed.connect(_on_terrain_data_resolution_changed)
		_ci.texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT)


func _on_terrain_data_map_changed(maptype: int, index: int) -> void:
	if maptype == HTerrainData.CHANNEL_HEIGHT:
		_ci.texture = _terrain_data.get_texture(HTerrainData.CHANNEL_HEIGHT)


func _on_terrain_data_resolution_changed() -> void:
	# TODO Workaround issue https://github.com/godotengine/godot/issues/24463
	_ci.queue_redraw()


func request_tiles_in_region(rect: Rect2i) -> void:
	assert(is_inside_tree())
	assert(_terrain_data != null)
	var res : int = _terrain_data.get_resolution()
	
	var min_pos := rect.position - Vector2i(1, 1)
	var max_pos := rect.position + rect.size + Vector2i(1, 1)
	var tmin : Vector2i = min_pos / VIEWPORT_SIZE
	var tmax : Vector2i = max_pos / VIEWPORT_SIZE
	var ntx := res / VIEWPORT_SIZE
	var nty := res / VIEWPORT_SIZE
	tmin.x = clampi(tmin.x, 0, ntx)
	tmin.y = clampi(tmin.y, 0, nty)
	tmax.x = clampi(tmax.x, 0, ntx)
	tmax.y = clampi(tmax.y, 0, nty)
	
	for y in range(tmin.y, tmax.y):
		for x in range(tmin.x, tmax.x):
			_request_tile(Vector2i(x, y))


func _request_tile(tpos: Vector2i) -> void:
	if _pending_tiles_grid.has(tpos):
		var state : int = _pending_tiles_grid[tpos]
		if state == STATE_PENDING:
			return
	_pending_tiles_grid[tpos] = STATE_PENDING
	_pending_tiles_queue.push_front(tpos)
	set_process(true)


func _process(_unused_delta: float) -> void:
	if not is_processing():
		return
	
	if _is_processing_tile and _terrain_data != null:
		var src : Image = _viewport.get_texture().get_image()
		var dst : Image = _terrain_data.get_image(HTerrainData.CHANNEL_NORMAL)
		
		src.convert(dst.get_format())
		#src.save_png(str("test_", _processing_tile.x, "_", _processing_tile.y, ".png"))
		var pos := _processing_tile * VIEWPORT_SIZE
		var w := src.get_width() - 1
		var h := src.get_height() - 1
		dst.blit_rect(src, Rect2i(1, 1, w, h), pos)
		_terrain_data.notify_region_change(Rect2i(pos.x, pos.y, w, h), HTerrainData.CHANNEL_NORMAL)
		
		if _pending_tiles_grid[_processing_tile] == STATE_PROCESSING:
			_pending_tiles_grid.erase(_processing_tile)
		_is_processing_tile = false

	if _has_pending_tiles():
		var tpos : Vector2i = _pending_tiles_queue[-1]
		_pending_tiles_queue.pop_back()
		# The sprite will be much larger than the viewport due to the size of the heightmap.
		# We move it around so the part inside the viewport will correspond to the tile.
		_ci.position = -VIEWPORT_SIZE * tpos + Vector2i(1, 1)
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		_processing_tile = tpos
		_is_processing_tile = true
		_pending_tiles_grid[tpos] = STATE_PROCESSING
	else:
		set_process(false)


func _has_pending_tiles() -> bool:
	return len(_pending_tiles_queue) > 0
