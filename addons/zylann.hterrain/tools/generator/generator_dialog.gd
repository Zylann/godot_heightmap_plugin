@tool
extends AcceptDialog

const HTerrain = preload("../../hterrain.gd")
const HTerrainData = preload("../../hterrain_data.gd")
const HTerrainMesher = preload("../../hterrain_mesher.gd")
const HT_Util = preload("../../util/util.gd")
const HT_TextureGenerator = preload("./texture_generator.gd")
const HT_TextureGeneratorPass = preload("./texture_generator_pass.gd")
const HT_Logger = preload("../../util/logger.gd")
const HT_ImageFileCache = preload("../../util/image_file_cache.gd")
const HT_Inspector = preload("../inspector/inspector.gd")
const HT_TerrainPreview = preload("../terrain_preview.gd")
const HT_ProgressWindow = preload("../progress_window.gd")

const HT_ProgressWindowScene = preload("../progress_window.tscn")

# TODO Power of two is assumed here.
# I wonder why it doesn't have the off by one terrain textures usually have
const MAX_VIEWPORT_RESOLUTION = 512

#signal progress_notified(info) # { "progress": real, "message": string, "finished": bool }

@onready var _inspector_container : Control = $VBoxContainer/Editor/Settings
@onready var _inspector : HT_Inspector = $VBoxContainer/Editor/Settings/Inspector
@onready var _preview : HT_TerrainPreview = $VBoxContainer/Editor/Preview/TerrainPreview
@onready var _progress_bar : ProgressBar = $VBoxContainer/Editor/Preview/ProgressBar

var _dummy_texture = load("res://addons/zylann.hterrain/tools/icons/empty.png")
var _terrain : HTerrain = null
var _applying := false
var _generator : HT_TextureGenerator
var _generated_textures := [null, null]
var _dialog_visible := false
var _undo_map_ids := {}
var _image_cache : HT_ImageFileCache = null
var _undo_redo_manager : EditorUndoRedoManager
var _logger := HT_Logger.get_for(self)
var _viewport_resolution := MAX_VIEWPORT_RESOLUTION
var _progress_window : HT_ProgressWindow


static func get_shader(shader_name: String) -> Shader:
	var path := "res://addons/zylann.hterrain/tools/generator/shaders"\
		.path_join(str(shader_name, ".gdshader"))
	return load(path) as Shader


func _init():
	# Godot 4 does not have a plain WindowDialog class... there is Window but it's too unfriendly...
	get_ok_button().hide()
	
	_progress_window = HT_ProgressWindowScene.instantiate()
	add_child(_progress_window)


func _ready():
	_inspector.set_prototype({
		"seed": {
			"type": TYPE_INT, 
			"randomizable": true, 
			"range": { "min": -100, "max": 100 }, 
			"slidable": false
		},
		"offset": {
			"type": TYPE_VECTOR2
		},
		"base_height": { 
			"type": TYPE_FLOAT,
			"range": {"min": -500.0, "max": 500.0, "step": 0.1 },
			"default_value": -50.0
		},
		"height_range": {
			"type": TYPE_FLOAT,
			"range": {"min": 0.0, "max": 2000.0, "step": 0.1 },
			"default_value": 150.0
		},
		"scale": {
			"type": TYPE_FLOAT,
			"range": {"min": 1.0, "max": 1000.0, "step": 1.0},
			"default_value": 100.0
		},
		"roughness": {
			"type": TYPE_FLOAT,
			"range": {"min": 0.0, "max": 1.0, "step": 0.01},
			"default_value": 0.4
		},
		"curve": {
			"type": TYPE_FLOAT,
			"range": {"min": 1.0, "max": 10.0, "step": 0.1},
			"default_value": 1.0
		},
		"octaves": {
			"type": TYPE_INT,
			"range": {"min": 1, "max": 10, "step": 1},
			"default_value": 6
		},
		"erosion_steps": {
			"type": TYPE_INT,
			"range": {"min": 0, "max": 100, "step": 1},
			"default_value": 0
		},
		"erosion_weight": {
			"type": TYPE_FLOAT,
			"range": { "min": 0.0, "max": 1.0 },
			"default_value": 0.5
		},
		"erosion_slope_factor": {
			"type": TYPE_FLOAT,
			"range": { "min": 0.0, "max": 1.0 },
			"default_value": 0.0
		},
		"erosion_slope_direction": {
			"type": TYPE_VECTOR2,
			"default_value": Vector2(0, 0)
		},
		"erosion_slope_invert": {
			"type": TYPE_BOOL,
			"default_value": false
		},
		"dilation": {
			"type": TYPE_FLOAT,
			"range": { "min": 0.0, "max": 1.0 },
			"default_value": 0.0
		},
		"island_weight": {
			"type": TYPE_FLOAT,
			"range": { "min": 0.0, "max": 1.0, "step": 0.01 },
			"default_value": 0.0
		},
		"island_sharpness": {
			"type": TYPE_FLOAT,
			"range": { "min": 0.0, "max": 1.0, "step": 0.01 },
			"default_value": 0.0
		},
		"island_height_ratio": {
			"type": TYPE_FLOAT,
			"range": { "min": -1.0, "max": 1.0, "step": 0.01 },
			"default_value": -1.0
		},
		"island_shape": {
			"type": TYPE_FLOAT,
			"range": { "min": 0.0, "max": 1.0, "step": 0.01 },
			"default_value": 0.0
		},
		"additive_heightmap": {
			"type": TYPE_BOOL,
			"default_value": false
		},
		"show_sea": {
			"type": TYPE_BOOL,
			"default_value": true
		},
		"shadows": {
			"type": TYPE_BOOL,
			"default_value": true
		}
	})

	_generator = HT_TextureGenerator.new()
	_generator.set_resolution(Vector2i(_viewport_resolution, _viewport_resolution))
	# Setup the extra pixels we want on max edges for terrain
	# TODO I wonder if it's not better to let the generator shaders work in pixels
	# instead of NDC, rather than putting a padding system there
	_generator.set_output_padding([0, 1, 0, 1])
	_generator.output_generated.connect(_on_TextureGenerator_output_generated)
	_generator.completed.connect(_on_TextureGenerator_completed)
	_generator.progress_reported.connect(_on_TextureGenerator_progress_reported)
	add_child(_generator)

	# TEST
	if not Engine.is_editor_hint():
		call_deferred("popup_centered")


func apply_dpi_scale(dpi_scale: float):
	min_size *= dpi_scale
	_inspector_container.custom_minimum_size *= dpi_scale


func set_terrain(terrain: HTerrain):
	_terrain = terrain
	_adjust_viewport_resolution()


func _adjust_viewport_resolution():
	if _terrain == null:
		return
	var data = _terrain.get_data()
	if data == null:
		return
	var terrain_resolution := data.get_resolution()
	
	# By default we want to work with a large enough viewport to generate tiles,
	# but we should pick a smaller size if the terrain is smaller than that...
	var vp_res := MAX_VIEWPORT_RESOLUTION
	while vp_res > terrain_resolution:
		vp_res /= 2
	
	_generator.set_resolution(Vector2(vp_res, vp_res))
	_viewport_resolution = vp_res


func set_image_cache(image_cache: HT_ImageFileCache):
	_image_cache = image_cache


func set_undo_redo(ur: EditorUndoRedoManager):
	_undo_redo_manager = ur


func _notification(what: int):
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			# We don't want any of this to run in an edited scene
			if HT_Util.is_in_edited_scene(self):
				return
			# Since Godot 4 visibility can be changed even between _enter_tree and _ready
			if _preview == null:
				return

			if visible:
				# TODO https://github.com/godotengine/godot/issues/18160
				if _dialog_visible:
					return
				_dialog_visible = true
				
				_adjust_viewport_resolution()

				_preview.set_sea_visible(_inspector.get_value("show_sea"))
				_preview.set_shadows_enabled(_inspector.get_value("shadows"))
				
				_update_generator(true)

			else:
#				if not _applying:
#					_destroy_viewport()
				_preview.cleanup()
				for i in len(_generated_textures):
					_generated_textures[i] = null
				_dialog_visible = false


func _update_generator(preview: bool):
	var scale : float = _inspector.get_value("scale")
	# Scale is inverted in the shader
	if absf(scale) < 0.01:
		scale = 0.0
	else:
		scale = 1.0 / scale
	scale *= _viewport_resolution

	var preview_scale := 4.0 # As if 2049x2049
	var sectors := []
	var terrain_size := 513
	
	var additive_heightmap : Texture2D = null

	# For testing
	if not Engine.is_editor_hint() and _terrain == null:
		sectors.append(Vector2(0, 0))

	# Get preview scale and sectors to generate.
	# Allowing null terrain to make it testable.
	if _terrain != null and _terrain.get_data() != null:
		var terrain_data := _terrain.get_data()
		terrain_size = terrain_data.get_resolution()
		
		if _inspector.get_value("additive_heightmap"):
			additive_heightmap = terrain_data.get_texture(HTerrainData.CHANNEL_HEIGHT)

		if preview:
			# When previewing the resolution does not span the entire terrain,
			# so we apply a scale to some of the passes to make it cover it all.
			preview_scale = float(terrain_size) / float(_viewport_resolution)
			sectors.append(Vector2(0, 0))

		else:
			if additive_heightmap != null:
				# We have to duplicate the heightmap because we are going to write
				# into it during the generation process.
				# It would be fine when we don't read outside of a generated tile,
				# but we actually do that for erosion: neighboring pixels are read
				# again, and if they were modified by a previous tile it will 
				# disrupt generation, so we need to use a copy of the original.
				additive_heightmap = additive_heightmap.duplicate()
			
			# When we get to generate it fully, sectors are used,
			# so the size or shape of the terrain doesn't matter
			preview_scale = 1.0

			var cw := terrain_size / _viewport_resolution
			var ch := terrain_size / _viewport_resolution

			for y in ch:
				for x in cw:
					sectors.append(Vector2(x, y))

	var erosion_iterations := int(_inspector.get_value("erosion_steps"))
	erosion_iterations /= int(preview_scale)

	_generator.clear_passes()

	# Terrain textures need to have an off-by-one on their max edge,
	# which is shared with the other sectors.
	var base_offset_ndc = _inspector.get_value("offset")
	#var sector_size_offby1_ndc = float(VIEWPORT_RESOLUTION - 1) / padded_viewport_resolution

	for i in len(sectors):
		var sector = sectors[i]
		#var offset = sector * sector_size_offby1_ndc - Vector2(pad_offset_ndc, pad_offset_ndc)

#		var offset_px = sector * (VIEWPORT_RESOLUTION - 1) - Vector2(pad_offset_px, pad_offset_px)
#		var offset_ndc = offset_px / padded_viewport_resolution
		var progress := float(i) / len(sectors)
		var p := HT_TextureGeneratorPass.new()
		p.clear = true
		p.shader = get_shader("perlin_noise")
		# This pass generates the shapes of the terrain so will have to account for offset
		p.tile_pos = sector
		p.params = {
			"u_octaves": _inspector.get_value("octaves"),
			"u_seed": _inspector.get_value("seed"),
			"u_scale": scale,
			"u_offset": base_offset_ndc,
			"u_base_height": _inspector.get_value("base_height") / preview_scale,
			"u_height_range": _inspector.get_value("height_range") / preview_scale,
			"u_roughness": _inspector.get_value("roughness"),
			"u_curve": _inspector.get_value("curve"),
			"u_island_weight": _inspector.get_value("island_weight"),
			"u_island_sharpness": _inspector.get_value("island_sharpness"),
			"u_island_height_ratio": _inspector.get_value("island_height_ratio"),
			"u_island_shape": _inspector.get_value("island_shape"),
			"u_additive_heightmap": additive_heightmap,
			"u_additive_heightmap_factor": \
				(1.0 if additive_heightmap != null else 0.0) / preview_scale,
			"u_terrain_size": terrain_size / preview_scale,
			"u_tile_size": _viewport_resolution
		}
		_generator.add_pass(p)

		if erosion_iterations > 0:
			p = HT_TextureGeneratorPass.new()
			p.shader = get_shader("erode")
			# TODO More erosion config
			p.params = {
				"u_slope_factor": _inspector.get_value("erosion_slope_factor"),
				"u_slope_invert": _inspector.get_value("erosion_slope_invert"),
				"u_slope_up": _inspector.get_value("erosion_slope_direction"),
				"u_weight": _inspector.get_value("erosion_weight"),
				"u_dilation": _inspector.get_value("dilation")
			}
			p.iterations = erosion_iterations
			p.padding = p.iterations
			_generator.add_pass(p)

		_generator.add_output({
			"maptype": HTerrainData.CHANNEL_HEIGHT,
			"sector": sector,
			"progress": progress
		})

		p = HT_TextureGeneratorPass.new()
		p.shader = get_shader("bump2normal")
		p.padding = 1
		_generator.add_pass(p)

		_generator.add_output({
			"maptype": HTerrainData.CHANNEL_NORMAL,
			"sector": sector,
			"progress": progress
		})

	# TODO AO generation
	# TODO Splat generation
	_generator.run()


func _on_CancelButton_pressed():
	hide()


func _on_ApplyButton_pressed():
	# We used to hide the dialog when the Apply button is clicked, and then texture generation took
	# place in an offscreen viewport in multiple tiled stages, with a progress window being shown.
	# But in Godot 4, it turns out SubViewports never update if they are child of a hidden Window,
	# even if they are set to UPDATE_ALWAYS...
	#hide()
	
	_apply()


func _on_Inspector_property_changed(key, value):
	match key:
		"show_sea":
			_preview.set_sea_visible(value)
		"shadows":
			_preview.set_shadows_enabled(value)
		_:
			_update_generator(true)


func _on_TerrainPreview_dragged(relative: Vector2, button_mask: int):
	if button_mask & MOUSE_BUTTON_MASK_LEFT:
		var offset : Vector2 = _inspector.get_value("offset")
		offset += relative
		_inspector.set_value("offset", offset)


func _apply():
	if _terrain == null:
		_logger.error("cannot apply, terrain is null")
		return

	var data := _terrain.get_data()
	if data == null:
		_logger.error("cannot apply, terrain data is null")
		return

	var dst_heights := data.get_image(HTerrainData.CHANNEL_HEIGHT)
	if dst_heights == null:
		_logger.error("terrain heightmap image isn't loaded")
		return

	var dst_normals := data.get_image(HTerrainData.CHANNEL_NORMAL)
	if dst_normals == null:
		_logger.error("terrain normal image isn't loaded")
		return

	_applying = true
	
	_undo_map_ids[HTerrainData.CHANNEL_HEIGHT] = _image_cache.save_image(dst_heights)
	_undo_map_ids[HTerrainData.CHANNEL_NORMAL] = _image_cache.save_image(dst_normals)

	_update_generator(false)


func _on_TextureGenerator_progress_reported(info: Dictionary):
	if _applying:
		return
	var p := 0.0
	if info.pass_index == 1:
		p = float(info.iteration) / float(info.iteration_count)
	_progress_bar.show()
	_progress_bar.ratio = p


func _on_TextureGenerator_output_generated(image: Image, info: Dictionary):
	# TODO We should check the terrain's image format,
	# but that would prevent from testing in isolation...
	if info.maptype == HTerrainData.CHANNEL_HEIGHT:
		# Hack to workaround Godot 4.0 not supporting RF viewports. Heights are packed as floats
		# into RGBA8 components.
		assert(image.get_format() == Image.FORMAT_RGBA8)
		image = Image.create_from_data(image.get_width(), image.get_height(), false, 
			Image.FORMAT_RF, image.get_data())
	
	if not _applying:
		# Update preview
		# TODO Improve TextureGenerator so we can get a ViewportTexture per output?
		var tex = _generated_textures[info.maptype]
		if tex == null:
			tex = ImageTexture.create_from_image(image)
			_generated_textures[info.maptype] = tex
		else:
			tex.update(image)

		var num_set := 0
		for v in _generated_textures:
			if v != null:
				num_set += 1
		if num_set == len(_generated_textures):
			_preview.setup( \
				_generated_textures[HTerrainData.CHANNEL_HEIGHT],
				_generated_textures[HTerrainData.CHANNEL_NORMAL])
	else:
		assert(_terrain != null)
		var data := _terrain.get_data()
		assert(data != null)
		var dst := data.get_image(info.maptype)
		assert(dst != null)
#		print("Tile ", info.sector)
#		image.save_png(str("debug_generator_tile_", 
#			info.sector.x, "_", info.sector.y, "_map", info.maptype, ".png"))
		
		# Converting in case Viewport texture isn't the format we expect for this map.
		# Note, in Godot 4 it seems the chosen renderer also influences what you get.
		# Forward+ non-transparent viewport gives RGB8, but Compatibility gives RGBA8.
		# I don't know if it's expected or is a bug...
		# Also, since RF heightmaps we use RGBA8 so we can pack floats in pixels, because
		# Godot 4.0 does not support RF viewports. But that also means the same viewport may be
		# re-used for other maps that don't need to be RGBA8.
		if image.get_format() != dst.get_format():
			image.convert(dst.get_format())

		dst.blit_rect(image, \
			Rect2i(0, 0, image.get_width(), image.get_height()), \
			info.sector * _viewport_resolution)

		_notify_progress({
			"progress": info.progress,
			"message": "Calculating sector (" 
				+ str(info.sector.x) + ", " + str(info.sector.y) + ")"
		})

#		if info.maptype == HTerrainData.CHANNEL_NORMAL:
#			image.save_png(str("normal_sector_", info.sector.x, "_", info.sector.y, ".png"))


func _on_TextureGenerator_completed():
	_progress_bar.hide()

	if not _applying:
		return
	_applying = false
	
	assert(_terrain != null)
	var data : HTerrainData = _terrain.get_data()
	var resolution := data.get_resolution()
	data.notify_region_change(Rect2(0, 0, resolution, resolution), HTerrainData.CHANNEL_HEIGHT)

	var redo_map_ids := {}
	for map_type in _undo_map_ids:
		redo_map_ids[map_type] = _image_cache.save_image(data.get_image(map_type))

	var undo_redo := _undo_redo_manager.get_history_undo_redo(
		_undo_redo_manager.get_object_history_id(data))

	data._edit_set_disable_apply_undo(true)
	undo_redo.create_action("Generate terrain")
	undo_redo.add_do_method(data._edit_apply_maps_from_file_cache.bind(_image_cache, redo_map_ids))
	undo_redo.add_undo_method(
		data._edit_apply_maps_from_file_cache.bind(_image_cache, _undo_map_ids))
	undo_redo.commit_action()
	data._edit_set_disable_apply_undo(false)

	_notify_progress({ "finished": true })
	_logger.debug("Done")
	
	hide()


func _notify_progress(info: Dictionary):
	_progress_window.handle_progress(info)


func _process(delta):
	if _applying:
		# HACK to workaround a peculiar behavior of Viewports in Godot 4.
		# Apparently Godot 4 will not update Viewports set to UPDATE_ALWAYS when the editor decides
		# it doesn't need to redraw ("low processor mode", what makes the editor redraw only with
		# changes). That wasn't the case in Godot 3, but I guess it is now.
		# That means when we click Apply, the viewport will not update in particular when doing
		# erosion passes, because the action of clicking Apply doesn't lead to as many redraws as
		# changing preview parameters in the UI (those cause redraws for different reasons).
		# So let's poke the renderer by redrawing something...
		#
		# This also piles on top of the workaround in which we keep the window visible when
		# applying! So the window has one more reason to stay visible...
		#
		_preview.queue_redraw()

