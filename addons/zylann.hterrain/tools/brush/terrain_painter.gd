extends Node

const Painter = preload("./painter.gd")
const HTerrain = preload("../../hterrain.gd")
const HTerrainData = preload("../../hterrain_data.gd")
const Logger = preload("../../util/logger.gd")

const RaiseShader = preload("./shaders/raise.shader")

const MODE_RAISE = 0
const MODE_LOWER = 1
const MODE_SMOOTH = 2
const MODE_FLATTEN = 3
const MODE_SPLAT = 4
const MODE_COLOR = 5
const MODE_MASK = 6
const MODE_DETAIL = 7
const MODE_LEVEL = 8
const MODE_COUNT = 9

class ModifiedMap:
	var map_type := 0
	var map_index := 0
	var painter_index := 0

signal changed

var _painters := []
var _brush_size := 32
var _opacity := 1.0
var _color := Color(1, 0, 0, 1)
# When true, we draw holes. When unchecked, we clear holes
var _mask_flag := false
var _mode := MODE_RAISE
var _flatten_height := 0.0
var _detail_index := 0
var _detail_density := 1.0
var _texture_index := 0
var _modified_maps := []
var _terrain : HTerrain
var _logger = Logger.get_for(self)


func _init():
	for i in 4:
		var p = Painter.new()
		p.set_brush_size(_brush_size)
		p.connect("texture_region_changed", self, "_on_painter_texture_region_changed", [i])
		add_child(p)
		_painters.append(p)


func get_brush_size() -> int:
	return _brush_size


func set_brush_size(s: int):
	if _brush_size == s:
		return
	_brush_size = s
	for p in _painters:
		p.set_brush_size(_brush_size)
	emit_signal("changed")


func get_opacity() -> float:
	return _opacity


func set_opacity(opacity: float):
	_opacity = opacity


func set_flatten_height(h: float):
	if h == _flatten_height:
		return
	_flatten_height = h
	emit_signal("changed")


func get_flatten_height() -> float:
	return _flatten_height


func set_color(c: Color):
	_color = c


func get_color() -> Color:
	return _color


func set_mask_flag(m: bool):
	_mask_flag = m


func get_mask_flag() -> bool:
	return _mask_flag


func set_detail_density(d: float):
	_detail_density = clamp(d, 0.0, 1.0)


func get_detail_density() -> float:
	return _detail_density


func is_operation_pending() -> bool:
	for p in _painters:
		if p.is_operation_pending():
			return true
	return false


func has_modified_chunks() -> bool:
	for p in _painters:
		if p.has_modified_chunks():
			return true
	return false


func get_undo_chunk_size() -> int:
	return Painter.UNDO_CHUNK_SIZE


func commit() -> Dictionary:
	assert(_terrain.get_data() != null)
	var terrain_data = _terrain.get_data()
	assert(not terrain_data.is_locked())
	
	var changes := []
	var chunk_positions : Array
	
	for mm in _modified_maps:
		var painter : Painter = _painters[mm.painter_index]
		var info := painter.commit()
		
		# Note, positions are always the same for each map
		chunk_positions = info.chunk_positions
	
		changes.append({
			"map_type": mm.map_type,
			"map_index": mm.map_index,
			"chunk_initial_datas": info.chunk_initial_datas,
			"chunk_final_datas": info.chunk_final_datas
		})
		
		var cs := get_undo_chunk_size()
		for pos in info.chunk_positions:
			var rect = Rect2(pos * cs, Vector2(cs, cs))
			# This will update vertical bounds and notify normal map baker,
			# since the latter updates out of order for preview
			terrain_data.notify_region_change(rect, mm.map_type, mm.map_index, false, true)
	
	assert(not has_modified_chunks())
	
	return {
		"chunk_positions": chunk_positions,
		"maps": changes
	}


func set_mode(mode: int):
	assert(mode >= 0 and mode < MODE_COUNT)
	_mode = mode


func get_mode() -> int:
	return _mode


func set_terrain(terrain: HTerrain):
	if terrain == _terrain:
		return
	_terrain = terrain
	# It's important  to release resources here,
	# otherwise Godot keeps modified terrain maps in memory and "reloads" them like that
	# next time we reopen the scene, even if we didn't save it
	for p in _painters:
		p.set_image(null, null)


# This may be called from an `_input` callback
func paint_input(position: Vector2):
	assert(_terrain.get_data() != null)
	var data = _terrain.get_data()
	assert(not data.is_locked())
	
	_modified_maps.clear()

	match _mode:
		MODE_RAISE:
			_paint_height(data, position, 1.0)

		MODE_LOWER:
			_paint_height(data, position, -1.0)

		MODE_SMOOTH:
			_paint_smooth(data, position)

		MODE_FLATTEN:
			_paint_flatten(data, position)

		MODE_LEVEL:
			_paint_level(data, position)

		MODE_SPLAT:
			var use_indexed_splat := _terrain.is_using_texture_array()
			if use_indexed_splat:
				_paint_splat_indexed(data, position)
			else:
				_paint_splat_classic4(data, position)

		MODE_COLOR:
			_paint_color(data, position)

		MODE_MASK:
			_paint_mask(data, position)

		MODE_DETAIL:
			_paint_mask(data, position)
			
		_:
			_logger.error("Unknown mode {0}".format([_mode]))

	assert(len(_modified_maps) > 0)


func _on_painter_texture_region_changed(rect: Rect2, painter_index: int):
	var data = _terrain.get_data()
	if data == null:
		return
	for mm in _modified_maps:
		if mm.painter_index == painter_index:
			# This will tell auto-baked maps to update (like normals).
			data.notify_region_change(rect, mm.map_type, mm.map_index, false, false)
			break


func _paint_height(data: HTerrainData, position: Vector2, factor: float):
	var image = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT, 0, true)
	
	var mm = ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_HEIGHT
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	# When using sculpting tools, make it dependent on brush size
	var raise_strength := 10.0 + float(_brush_size)
	var delta := factor * _opacity * (2.0 / 60.0) * raise_strength
	
	var p : Painter = _painters[0]
	
	p.set_brush_shader(RaiseShader)
	p.set_brush_shader_param("u_factor", delta)
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_smooth(data: HTerrainData, position: Vector2):
	var delta := _opacity * 1.0 / 60.0
	_modified_maps = [[HTerrainData.CHANNEL_HEIGHT, 0]]
	# TODO
	pass


func _paint_flatten(data: HTerrainData, position: Vector2):
	_modified_maps = [[HTerrainData.CHANNEL_HEIGHT, 0]]
	
	# TODO
	pass


func _paint_level(data: HTerrainData, position: Vector2):
	_modified_maps = [[HTerrainData.CHANNEL_HEIGHT, 0]]
	# TODO
	pass


func _paint_splat_classic4(data: HTerrainData, position: Vector2):
	# TODO
	pass


func _paint_splat_indexed(data: HTerrainData, position: Vector2):
	# TODO
	pass


func _paint_color(data: HTerrainData, position: Vector2):
	# TODO
	pass


func _paint_mask(data: HTerrainData, position: Vector2):
	# TODO
	pass


func _paint_detail(data: HTerrainData, position: Vector2):
	# TODO
	pass
