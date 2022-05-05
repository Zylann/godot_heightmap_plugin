extends Node

const HT_Painter = preload("./painter.gd")
const HTerrain = preload("../../hterrain.gd")
const HTerrainData = preload("../../hterrain_data.gd")
const HT_Logger = preload("../../util/logger.gd")
const HT_Brush = preload("./brush.gd")

const HT_RaiseShader = preload("./shaders/raise.shader")
const HT_SmoothShader = preload("./shaders/smooth.shader")
const HT_LevelShader = preload("./shaders/level.shader")
const HT_FlattenShader = preload("./shaders/flatten.shader")
const HT_ErodeShader = preload("./shaders/erode.shader")
const HT_Splat4Shader = preload("./shaders/splat4.shader")
const HT_Splat16Shader = preload("./shaders/splat16.shader")
const HT_SplatIndexedShader = preload("./shaders/splat_indexed.shader")
const HT_ColorShader = preload("./shaders/color.shader")
const HT_AlphaShader = preload("./shaders/alpha.shader")

const MODE_RAISE = 0
const MODE_LOWER = 1
const MODE_SMOOTH = 2
const MODE_FLATTEN = 3
const MODE_SPLAT = 4
const MODE_COLOR = 5
const MODE_MASK = 6
const MODE_DETAIL = 7
const MODE_LEVEL = 8
const MODE_ERODE = 9
const MODE_COUNT = 10

class HT_ModifiedMap:
	var map_type := 0
	var map_index := 0
	var painter_index := 0

signal flatten_height_changed

var _painters := []

var _brush := HT_Brush.new()

var _color := Color(1, 0, 0, 1)
var _mask_flag := false
var _mode := MODE_RAISE
var _flatten_height := 0.0
var _detail_index := 0
var _detail_density := 1.0
var _texture_index := 0
var _slope_limit_low_angle := 0.0
var _slope_limit_high_angle := PI / 2.0

var _modified_maps := []
var _terrain : HTerrain
var _logger = HT_Logger.get_for(self)


func _init():
	for i in 4:
		var p = HT_Painter.new()
		# The name is just for debugging
		p.set_name(str("Painter", i))
		#p.set_brush_size(_brush_size)
		p.connect("texture_region_changed", self, "_on_painter_texture_region_changed", [i])
		add_child(p)
		_painters.append(p)


func get_brush() -> HT_Brush:
	return _brush


func get_brush_size() -> int:
	return _brush.get_size()


func set_brush_size(s: int):
	_brush.set_size(s)
#	for p in _painters:
#		p.set_brush_size(_brush_size)


func set_brush_texture(texture: Texture):
	_brush.set_shapes([texture])
#	for p in _painters:
#		p.set_brush_texture(texture)


func get_opacity() -> float:
	return _brush.get_opacity()


func set_opacity(opacity: float):
	_brush.set_opacity(opacity)


func set_flatten_height(h: float):
	if h == _flatten_height:
		return
	_flatten_height = h
	emit_signal("flatten_height_changed")


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


func set_detail_index(di: int):
	_detail_index = di


func set_texture_index(i: int):
	_texture_index = i


func get_texture_index() -> int:
	return _texture_index


func get_slope_limit_low_angle() -> float:
	return _slope_limit_low_angle


func get_slope_limit_high_angle() -> float:
	return _slope_limit_high_angle


func set_slope_limit_angles(low: float, high: float):
	_slope_limit_low_angle = low
	_slope_limit_high_angle = high


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
	return HT_Painter.UNDO_CHUNK_SIZE


func commit() -> Dictionary:
	assert(_terrain.get_data() != null)
	var terrain_data = _terrain.get_data()
	assert(not terrain_data.is_locked())
	
	var changes := []
	var chunk_positions : Array
	
	assert(len(_modified_maps) > 0)
	
	for mm in _modified_maps:
		#print("Flushing painter ", mm.painter_index)
		var painter : HT_Painter = _painters[mm.painter_index]
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
	
#	for i in len(_painters):
#		var p = _painters[i]
#		if p.has_modified_chunks():
#			print("Painter ", i, " has modified chunks")
	
	# `commit()` is supposed to consume these chunks, there should be none left
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
		p.clear_brush_shader_params()


# This may be called from an `_input` callback.
# Returns `true` if any change was performed.
func paint_input(position: Vector2, pressure: float) -> bool:
	assert(_terrain.get_data() != null)
	var data = _terrain.get_data()
	assert(not data.is_locked())
	
	if not _brush.configure_paint_input(_painters, position, pressure):
		# Sometimes painting may not happen due to frequency options
		return false

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
			
		MODE_ERODE:
			_paint_erode(data, position)

		MODE_SPLAT:
			# TODO Properly support what happens when painting outside of supported index
			# var supported_slots_count := terrain.get_cached_ground_texture_slot_count()
			# if _texture_index >= supported_slots_count:
			# 	_logger.debug("Painting out of range of supported texture slots: {0}/{1}" \
			# 		.format([_texture_index, supported_slots_count]))
			# 	return
			if _terrain.is_using_indexed_splatmap():
				_paint_splat_indexed(data, position)
			else:
				var splatmap_count := _terrain.get_used_splatmaps_count()
				match splatmap_count:
					1:
						_paint_splat4(data, position)
					4:
						_paint_splat16(data, position)

		MODE_COLOR:
			_paint_color(data, position)

		MODE_MASK:
			_paint_mask(data, position)

		MODE_DETAIL:
			_paint_detail(data, position)
			
		_:
			_logger.error("Unknown mode {0}".format([_mode]))

	assert(len(_modified_maps) > 0)
	return true


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
	
	var mm = HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_HEIGHT
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	# When using sculpting tools, make it dependent on brush size
	var raise_strength := 10.0 + float(_brush.get_size())
	var delta := factor * (2.0 / 60.0) * raise_strength
	
	var p : HT_Painter = _painters[0]
	
	p.set_brush_shader(HT_RaiseShader)
	p.set_brush_shader_param("u_factor", delta)
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_smooth(data: HTerrainData, position: Vector2):
	var image = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT, 0, true)
	
	var mm = HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_HEIGHT
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	var p : HT_Painter = _painters[0]
	
	p.set_brush_shader(HT_SmoothShader)
	p.set_brush_shader_param("u_factor", (10.0 / 60.0))
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_flatten(data: HTerrainData, position: Vector2):
	var image = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT, 0, true)
	
	var mm = HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_HEIGHT
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	var p : HT_Painter = _painters[0]
	
	p.set_brush_shader(HT_FlattenShader)
	p.set_brush_shader_param("u_flatten_value", _flatten_height)
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_level(data: HTerrainData, position: Vector2):
	var image = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT, 0, true)
	
	var mm = HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_HEIGHT
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	var p : HT_Painter = _painters[0]
	
	p.set_brush_shader(HT_LevelShader)
	p.set_brush_shader_param("u_factor", (10.0 / 60.0))
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_erode(data: HTerrainData, position: Vector2):
	var image = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT, 0, true)
	
	var mm = HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_HEIGHT
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	var p : HT_Painter = _painters[0]
	
	p.set_brush_shader(HT_ErodeShader)
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_splat4(data: HTerrainData, position: Vector2):
	var image = data.get_image(HTerrainData.CHANNEL_SPLAT)
	var texture = data.get_texture(HTerrainData.CHANNEL_SPLAT, 0, true)
	var heightmap_texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT, 0)
	
	var mm = HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_SPLAT
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	var p : HT_Painter = _painters[0]
	var splat = Color(0.0, 0.0, 0.0, 0.0)
	splat[_texture_index] = 1.0;
	p.set_brush_shader(HT_Splat4Shader)
	p.set_brush_shader_param("u_splat", splat)
	p.set_brush_shader_param("u_normal_min_y", cos(_slope_limit_high_angle))
	p.set_brush_shader_param("u_normal_max_y", cos(_slope_limit_low_angle) + 0.001)
	p.set_brush_shader_param("u_heightmap", heightmap_texture)
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_splat_indexed(data: HTerrainData, position: Vector2):
	var map_types = [
		HTerrainData.CHANNEL_SPLAT_INDEX, 
		HTerrainData.CHANNEL_SPLAT_WEIGHT
	]
	_modified_maps = []

	var textures = []
	for mode in 2:
		textures.append(data.get_texture(map_types[mode], 0, true))

	for mode in 2:
		var image = data.get_image(map_types[mode])
		
		var mm = HT_ModifiedMap.new()
		mm.map_type = map_types[mode]
		mm.map_index = 0
		mm.painter_index = mode
		_modified_maps.append(mm)

		var p : HT_Painter = _painters[mode]

		p.set_brush_shader(HT_SplatIndexedShader)
		p.set_brush_shader_param("u_mode", mode)
		p.set_brush_shader_param("u_index_map", textures[0])
		p.set_brush_shader_param("u_weight_map", textures[1])
		p.set_brush_shader_param("u_texture_index", _texture_index)
		p.set_image(image, textures[mode])
		p.paint_input(position)


func _paint_splat16(data: HTerrainData, position: Vector2):
	# Make sure required maps are present
	while data.get_map_count(HTerrainData.CHANNEL_SPLAT) < 4:
		data._edit_add_map(HTerrainData.CHANNEL_SPLAT)

	var splats := []
	for i in 4:
		splats.append(Color(0.0, 0.0, 0.0, 0.0))
	splats[_texture_index / 4][_texture_index % 4] = 1.0

	var textures := []
	for i in 4:
		textures.append(data.get_texture(HTerrainData.CHANNEL_SPLAT, i, true))

	var heightmap_texture = data.get_texture(HTerrainData.CHANNEL_HEIGHT, 0)

	for i in 4:
		var image : Image = data.get_image(HTerrainData.CHANNEL_SPLAT, i)
		var texture : Texture = textures[i]
		
		var mm := HT_ModifiedMap.new()
		mm.map_type = HTerrainData.CHANNEL_SPLAT
		mm.map_index = i
		mm.painter_index = i
		_modified_maps.append(mm)

		var p : HT_Painter = _painters[i]

		var other_splatmaps = []
		for tex in textures:
			if tex != texture:
				other_splatmaps.append(tex)
		
		p.set_brush_shader(HT_Splat16Shader)
		p.set_brush_shader_param("u_splat", splats[i])
		p.set_brush_shader_param("u_other_splatmap_1", other_splatmaps[0])
		p.set_brush_shader_param("u_other_splatmap_2", other_splatmaps[1])
		p.set_brush_shader_param("u_other_splatmap_3", other_splatmaps[2])
		p.set_brush_shader_param("u_normal_min_y", cos(_slope_limit_high_angle))
		p.set_brush_shader_param("u_normal_max_y", cos(_slope_limit_low_angle) + 0.001)
		p.set_brush_shader_param("u_heightmap", heightmap_texture)
		p.set_image(image, texture)
		p.paint_input(position)


func _paint_color(data: HTerrainData, position: Vector2):
	var image := data.get_image(HTerrainData.CHANNEL_COLOR)
	var texture := data.get_texture(HTerrainData.CHANNEL_COLOR, 0, true)
	
	var mm := HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_COLOR
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	var p : HT_Painter = _painters[0]
	
	# There was a problem with painting colors because of sRGB
	# https://github.com/Zylann/godot_heightmap_plugin/issues/17#issuecomment-734001879

	p.set_brush_shader(HT_ColorShader)
	p.set_brush_shader_param("u_color", _color)
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_mask(data: HTerrainData, position: Vector2):
	var image := data.get_image(HTerrainData.CHANNEL_COLOR)
	var texture := data.get_texture(HTerrainData.CHANNEL_COLOR, 0, true)
	
	var mm := HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_COLOR
	mm.map_index = 0
	mm.painter_index = 0
	_modified_maps = [mm]

	var p : HT_Painter = _painters[0]
	
	p.set_brush_shader(HT_AlphaShader)
	p.set_brush_shader_param("u_value", 1.0 if _mask_flag else 0.0)
	p.set_image(image, texture)
	p.paint_input(position)


func _paint_detail(data: HTerrainData, position: Vector2):
	var image := data.get_image(HTerrainData.CHANNEL_DETAIL, _detail_index)
	var texture := data.get_texture(HTerrainData.CHANNEL_DETAIL, _detail_index, true)
	
	var mm := HT_ModifiedMap.new()
	mm.map_type = HTerrainData.CHANNEL_DETAIL
	mm.map_index = _detail_index
	mm.painter_index = 0
	_modified_maps = [mm]

	var p : HT_Painter = _painters[0]
	var c := Color(_detail_density, _detail_density, _detail_density, 1.0)
	
	# TODO Don't use this shader
	p.set_brush_shader(HT_ColorShader)
	p.set_brush_shader_param("u_color", c)
	p.set_image(image, texture)
	p.paint_input(position)
