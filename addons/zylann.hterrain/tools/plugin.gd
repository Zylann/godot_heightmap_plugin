@tool # https://www.youtube.com/watch?v=Y7JG63IuaWs

extends EditorPlugin

const HTerrain = preload("../hterrain.gd")
const HTerrainDetailLayer = preload("../hterrain_detail_layer.gd")
const HTerrainData = preload("../hterrain_data.gd")
const HTerrainMesher = preload("../hterrain_mesher.gd")
const HTerrainTextureSet = preload("../hterrain_texture_set.gd")
const HT_PreviewGenerator = preload("./preview_generator.gd")
const HT_TerrainPainter = preload("./brush/terrain_painter.gd")
const HT_BrushDecal = preload("./brush/decal.gd")
const HT_Util = preload("../util/util.gd")
const HT_EditorUtil = preload("./util/editor_util.gd")
const HT_LoadTextureDialog = preload("./load_texture_dialog.gd")
const HT_GlobalMapBaker = preload("./globalmap_baker.gd")
const HT_ImageFileCache = preload("../util/image_file_cache.gd")
const HT_Logger = preload("../util/logger.gd")
const HT_EditPanel = preload("./panel.gd")
const HT_GeneratorDialog = preload("./generator/generator_dialog.gd")
const HT_TextureSetEditor = preload("./texture_editor/set_editor/texture_set_editor.gd")
const HT_TextureSetImportEditor = \
	preload("./texture_editor/set_editor/texture_set_import_editor.gd")
const HT_ProgressWindow = preload("./progress_window.gd")

const HT_EditPanelScene = preload("./panel.tscn")
const HT_ProgressWindowScene = preload("./progress_window.tscn")
const HT_GeneratorDialogScene = preload("./generator/generator_dialog.tscn")
const HT_ImportDialogScene = preload("./importer/importer_dialog.tscn")
const HT_GenerateMeshDialogScene = preload("./generate_mesh_dialog.tscn")
const HT_ResizeDialogScene = preload("./resize_dialog/resize_dialog.tscn")
const HT_ExportImageDialogScene = preload("./exporter/export_image_dialog.tscn")
const HT_TextureSetEditorScene = preload("./texture_editor/set_editor/texture_set_editor.tscn")
const HT_TextureSetImportEditorScene = \
	preload("./texture_editor/set_editor/texture_set_import_editor.tscn")
const HT_AboutDialogScene = preload("./about/about_dialog.tscn")

const DOCUMENTATION_URL = "https://hterrain-plugin.readthedocs.io/en/latest"

const MENU_IMPORT_MAPS = 0
const MENU_GENERATE = 1
const MENU_BAKE_GLOBALMAP = 2
const MENU_RESIZE = 3
const MENU_UPDATE_EDITOR_COLLIDER = 4
const MENU_GENERATE_MESH = 5
const MENU_EXPORT_HEIGHTMAP = 6
const MENU_LOOKDEV = 7
const MENU_DOCUMENTATION = 8
const MENU_ABOUT = 9


# TODO Rename _terrain
var _node : HTerrain = null

# GUI
var _panel : HT_EditPanel = null
var _toolbar : Container = null
var _toolbar_brush_buttons := {}
var _generator_dialog : HT_GeneratorDialog = null
# TODO Rename _import_terrain_dialog
var _import_dialog = null
var _export_image_dialog = null

# This window is only used for operations not triggered by an existing dialog.
# In Godot it has been solved by automatically reparenting the dialog:
# https://github.com/godotengine/godot/pull/71209
# But `get_exclusive_child()` is not exposed. So dialogs triggering a progress
# dialog may need their own child instance...
var _progress_window : HT_ProgressWindow = null

var _generate_mesh_dialog = null
var _preview_generator : HT_PreviewGenerator = null
var _resize_dialog = null
var _about_dialog = null
var _menu_button : MenuButton
var _lookdev_menu : PopupMenu
var _texture_set_editor : HT_TextureSetEditor = null
var _texture_set_import_editor : HT_TextureSetImportEditor = null

var _globalmap_baker : HT_GlobalMapBaker = null
var _terrain_had_data_previous_frame := false
var _image_cache : HT_ImageFileCache
var _terrain_painter : HT_TerrainPainter = null
var _brush_decal : HT_BrushDecal = null
var _mouse_pressed := false
#var _pending_paint_action = null
var _pending_paint_commit := false

var _logger := HT_Logger.get_for(self)


func get_icon(icon_name: String) -> Texture2D:
	return HT_EditorUtil.load_texture(
		"res://addons/zylann.hterrain/tools/icons/icon_" + icon_name + ".svg", _logger)


func _enter_tree():
	_logger.debug("HTerrain plugin Enter tree")
	
	var dpi_scale = get_editor_interface().get_editor_scale()
	_logger.debug(str("DPI scale: ", dpi_scale))
	
	add_custom_type("HTerrain", "Node3D", HTerrain, get_icon("heightmap_node"))
	add_custom_type("HTerrainDetailLayer", "Node3D", HTerrainDetailLayer, 
		get_icon("detail_layer_node"))
	add_custom_type("HTerrainData", "Resource", HTerrainData, get_icon("heightmap_data"))
	# TODO Proper texture
	add_custom_type("HTerrainTextureSet", "Resource", HTerrainTextureSet, null)
	
	_preview_generator = HT_PreviewGenerator.new()
	get_editor_interface().get_resource_previewer().add_preview_generator(_preview_generator)
	
	_terrain_painter = HT_TerrainPainter.new()
	_terrain_painter.set_brush_size(5)
	_terrain_painter.get_brush().size_changed.connect(_on_brush_size_changed)
	add_child(_terrain_painter)

	_brush_decal = HT_BrushDecal.new()
	_brush_decal.set_size(_terrain_painter.get_brush_size())
	
	_image_cache = HT_ImageFileCache.new("user://temp_hterrain_image_cache")
	
	var editor_interface := get_editor_interface()
	var base_control := editor_interface.get_base_control()
	
	_panel = HT_EditPanelScene.instantiate()
	HT_Util.apply_dpi_scale(_panel, dpi_scale)
	_panel.hide()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, _panel)
	# Apparently _ready() still isn't called at this point...
	_panel.call_deferred("set_terrain_painter", _terrain_painter)
	_panel.call_deferred("setup_dialogs", base_control)
	_panel.set_undo_redo(get_undo_redo())
	_panel.set_image_cache(_image_cache)
	_panel.detail_selected.connect(_on_detail_selected)
	_panel.texture_selected.connect(_on_texture_selected)
	_panel.detail_list_changed.connect(_update_brush_buttons_availability)
	_panel.edit_texture_pressed.connect(_on_Panel_edit_texture_pressed)
	_panel.import_textures_pressed.connect(_on_Panel_import_textures_pressed)
	
	_toolbar = HBoxContainer.new()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.hide()
	
	var menu := MenuButton.new()
	menu.set_text("Terrain")
	menu.get_popup().add_item("Import maps...", MENU_IMPORT_MAPS)
	menu.get_popup().add_item("Generate...", MENU_GENERATE)
	menu.get_popup().add_item("Resize...", MENU_RESIZE)
	menu.get_popup().add_item("Bake global map", MENU_BAKE_GLOBALMAP)
	menu.get_popup().add_separator()
	menu.get_popup().add_item("Update Editor Collider", MENU_UPDATE_EDITOR_COLLIDER)
	menu.get_popup().add_separator()
	menu.get_popup().add_item("Generate mesh (heavy)", MENU_GENERATE_MESH)
	menu.get_popup().add_separator()
	menu.get_popup().add_item("Export heightmap", MENU_EXPORT_HEIGHTMAP)
	menu.get_popup().add_separator()
	_lookdev_menu = PopupMenu.new()
	_lookdev_menu.name = "LookdevMenu"
	_lookdev_menu.about_to_popup.connect(_on_lookdev_menu_about_to_show)
	_lookdev_menu.id_pressed.connect(_on_lookdev_menu_id_pressed)
	menu.get_popup().add_child(_lookdev_menu)
	menu.get_popup().add_submenu_item("Lookdev", _lookdev_menu.name, MENU_LOOKDEV)
	menu.get_popup().id_pressed.connect(_menu_item_selected)
	menu.get_popup().add_separator()
	menu.get_popup().add_item("Documentation", MENU_DOCUMENTATION)
	menu.get_popup().add_item("About HTerrain...", MENU_ABOUT)
	_toolbar.add_child(menu)
	_menu_button = menu
	
	var mode_icons := {}
	mode_icons[HT_TerrainPainter.MODE_RAISE] = get_icon("heightmap_raise")
	mode_icons[HT_TerrainPainter.MODE_LOWER] = get_icon("heightmap_lower")
	mode_icons[HT_TerrainPainter.MODE_SMOOTH] = get_icon("heightmap_smooth")
	mode_icons[HT_TerrainPainter.MODE_FLATTEN] = get_icon("heightmap_flatten")
	mode_icons[HT_TerrainPainter.MODE_SPLAT] = get_icon("heightmap_paint")
	mode_icons[HT_TerrainPainter.MODE_COLOR] = get_icon("heightmap_color")
	mode_icons[HT_TerrainPainter.MODE_DETAIL] = get_icon("grass")
	mode_icons[HT_TerrainPainter.MODE_MASK] = get_icon("heightmap_mask")
	mode_icons[HT_TerrainPainter.MODE_LEVEL] = get_icon("heightmap_level")
	mode_icons[HT_TerrainPainter.MODE_ERODE] = get_icon("heightmap_erode")
	
	var mode_tooltips := {}
	mode_tooltips[HT_TerrainPainter.MODE_RAISE] = "Raise height"
	mode_tooltips[HT_TerrainPainter.MODE_LOWER] = "Lower height"
	mode_tooltips[HT_TerrainPainter.MODE_SMOOTH] = "Smooth height"
	mode_tooltips[HT_TerrainPainter.MODE_FLATTEN] = "Flatten (flatten to a specific height)"
	mode_tooltips[HT_TerrainPainter.MODE_SPLAT] = "Texture paint"
	mode_tooltips[HT_TerrainPainter.MODE_COLOR] = "Color paint"
	mode_tooltips[HT_TerrainPainter.MODE_DETAIL] = "Grass paint"
	mode_tooltips[HT_TerrainPainter.MODE_MASK] = "Cut holes"
	mode_tooltips[HT_TerrainPainter.MODE_LEVEL] = "Level (smoothly flattens to average)"
	mode_tooltips[HT_TerrainPainter.MODE_ERODE] = "Erode"
	
	_toolbar.add_child(VSeparator.new())
	
	# I want modes to be in that order in the GUI
	var ordered_brush_modes := [
		HT_TerrainPainter.MODE_RAISE,
		HT_TerrainPainter.MODE_LOWER,
		HT_TerrainPainter.MODE_SMOOTH,
		HT_TerrainPainter.MODE_LEVEL,
		HT_TerrainPainter.MODE_FLATTEN,
		HT_TerrainPainter.MODE_ERODE,
		HT_TerrainPainter.MODE_SPLAT,
		HT_TerrainPainter.MODE_COLOR,
		HT_TerrainPainter.MODE_DETAIL,
		HT_TerrainPainter.MODE_MASK
	]
	
	var mode_group := ButtonGroup.new()
	
	for mode in ordered_brush_modes:
		var button := Button.new()
		button.flat = true
		button.icon = mode_icons[mode]
		button.tooltip_text = mode_tooltips[mode]
		button.set_toggle_mode(true)
		button.set_button_group(mode_group)
		
		if mode == _terrain_painter.get_mode():
			button.button_pressed = true
		
		button.pressed.connect(_on_mode_selected.bind(mode))
		_toolbar.add_child(button)
		
		_toolbar_brush_buttons[mode] = button
	
	_generator_dialog = HT_GeneratorDialogScene.instantiate()
	_generator_dialog.set_image_cache(_image_cache)
	_generator_dialog.set_undo_redo(get_undo_redo())
	base_control.add_child(_generator_dialog)
	_generator_dialog.apply_dpi_scale(dpi_scale)

	_import_dialog = HT_ImportDialogScene.instantiate()
	_import_dialog.permanent_change_performed.connect(_on_permanent_change_performed)
	HT_Util.apply_dpi_scale(_import_dialog, dpi_scale)
	base_control.add_child(_import_dialog)

	_progress_window = HT_ProgressWindowScene.instantiate()
	base_control.add_child(_progress_window)
	
	_generate_mesh_dialog = HT_GenerateMeshDialogScene.instantiate()
	_generate_mesh_dialog.generate_selected.connect(_on_GenerateMeshDialog_generate_selected)
	HT_Util.apply_dpi_scale(_generate_mesh_dialog, dpi_scale)
	base_control.add_child(_generate_mesh_dialog)
	
	_resize_dialog = HT_ResizeDialogScene.instantiate()
	_resize_dialog.permanent_change_performed.connect(_on_permanent_change_performed)
	HT_Util.apply_dpi_scale(_resize_dialog, dpi_scale)
	base_control.add_child(_resize_dialog)
	
	_globalmap_baker = HT_GlobalMapBaker.new()
	_globalmap_baker.progress_notified.connect(_progress_window.handle_progress)
	_globalmap_baker.permanent_change_performed.connect(_on_permanent_change_performed)
	add_child(_globalmap_baker)
	
	_export_image_dialog = HT_ExportImageDialogScene.instantiate()
	HT_Util.apply_dpi_scale(_export_image_dialog, dpi_scale)
	base_control.add_child(_export_image_dialog)
	# Need to call deferred because in the specific case where you start the editor
	# with the plugin enabled, _ready won't be called at this point
	_export_image_dialog.call_deferred("setup_dialogs", base_control)
	
	_about_dialog = HT_AboutDialogScene.instantiate()
	HT_Util.apply_dpi_scale(_about_dialog, dpi_scale)
	base_control.add_child(_about_dialog)

	_texture_set_editor = HT_TextureSetEditorScene.instantiate()
	_texture_set_editor.set_undo_redo(get_undo_redo())
	HT_Util.apply_dpi_scale(_texture_set_editor, dpi_scale)
	base_control.add_child(_texture_set_editor)
	_texture_set_editor.call_deferred("setup_dialogs", base_control)

	_texture_set_import_editor = HT_TextureSetImportEditorScene.instantiate()
	_texture_set_import_editor.set_undo_redo(get_undo_redo())
	_texture_set_import_editor.set_editor_file_system(
		get_editor_interface().get_resource_filesystem())
	HT_Util.apply_dpi_scale(_texture_set_import_editor, dpi_scale)
	base_control.add_child(_texture_set_import_editor)
	_texture_set_import_editor.call_deferred("setup_dialogs", base_control)

	_texture_set_editor.import_selected.connect(_on_TextureSetEditor_import_selected)
	

func _exit_tree():
	_logger.debug("HTerrain plugin Exit tree")
	
	# Make sure we release all references to edited stuff
	_edit(null)

	_panel.queue_free()
	_panel = null
	
	_toolbar.queue_free()
	_toolbar = null
	
	_generator_dialog.queue_free()
	_generator_dialog = null
	
	_import_dialog.queue_free()
	_import_dialog = null
	
	_progress_window.queue_free()
	_progress_window = null
	
	_generate_mesh_dialog.queue_free()
	_generate_mesh_dialog = null
	
	_resize_dialog.queue_free()
	_resize_dialog = null
	
	_export_image_dialog.queue_free()
	_export_image_dialog = null
	
	_about_dialog.queue_free()
	_about_dialog = null

	_texture_set_editor.queue_free()
	_texture_set_editor = null

	_texture_set_import_editor.queue_free()
	_texture_set_import_editor = null

	get_editor_interface().get_resource_previewer().remove_preview_generator(_preview_generator)
	_preview_generator = null
	
	# TODO Manual clear cuz it can't do it automatically due to a Godot bug
	_image_cache.clear()
	
	# TODO https://github.com/godotengine/godot/issues/6254#issuecomment-246139694
	# This was supposed to be automatic, but was never implemented it seems...
	remove_custom_type("HTerrain")
	remove_custom_type("HTerrainDetailLayer")
	remove_custom_type("HTerrainData")
	remove_custom_type("HTerrainTextureSet")


func _handles(object):
	return _get_terrain_from_object(object) != null


func _edit(object):
	_logger.debug(str("Edit ", object))
	
	var node = _get_terrain_from_object(object)
	
	if _node != null:
		_node.tree_exited.disconnect(_terrain_exited_scene)
	
	_node = node
	
	if _node != null:
		_node.tree_exited.connect(_terrain_exited_scene)
	
	_update_brush_buttons_availability()
	
	_panel.set_terrain(_node)
	_generator_dialog.set_terrain(_node)
	_import_dialog.set_terrain(_node)
	_terrain_painter.set_terrain(_node)
	_brush_decal.set_terrain(_node)
	_generate_mesh_dialog.set_terrain(_node)
	_resize_dialog.set_terrain(_node)
	_export_image_dialog.set_terrain(_node)
	
	if object is HTerrainDetailLayer:
		# Auto-select layer for painting
		if object.is_layer_index_valid():
			_panel.set_detail_layer_index(object.get_layer_index())
		_on_detail_selected(object.get_layer_index())
	
	_update_toolbar_menu_availability()


static func _get_terrain_from_object(object):
	if object != null and object is Node3D:
		if not object.is_inside_tree():
			return null
		if object is HTerrain:
			return object
		if object is HTerrainDetailLayer and object.get_parent() is HTerrain:
			return object.get_parent()
	return null


func _update_brush_buttons_availability():
	if _node == null:
		return
	if _node.get_data() != null:
		var data = _node.get_data()
		var has_details = (data.get_map_count(HTerrainData.CHANNEL_DETAIL) > 0)
		
		if has_details:
			var button = _toolbar_brush_buttons[HT_TerrainPainter.MODE_DETAIL]
			button.disabled = false
		else:
			var button = _toolbar_brush_buttons[HT_TerrainPainter.MODE_DETAIL]
			if button.button_pressed:
				_select_brush_mode(HT_TerrainPainter.MODE_RAISE)
			button.disabled = true


func _update_toolbar_menu_availability():
	var data_available := false
	if _node != null and _node.get_data() != null:
		data_available = true
	var popup : PopupMenu = _menu_button.get_popup()
	for i in popup.get_item_count():
		#var id = popup.get_item_id(i)
		# Turn off items if there is no data for them to work on
		if data_available:
			popup.set_item_disabled(i, false)
			popup.set_item_tooltip(i, "")
		else:
			popup.set_item_disabled(i, true)
			popup.set_item_tooltip(i, "Terrain has no data")


func _make_visible(visible: bool):
	_panel.set_visible(visible)
	_toolbar.set_visible(visible)
	_brush_decal.update_visibility()

	# TODO Workaround https://github.com/godotengine/godot/issues/6459
	# When the user selects another node,
	# I want the plugin to release its references to the terrain.
	# This is important because if we don't do that, some modified resources will still be
	# loaded in memory, so if the user closes the scene and reopens it later, the changes will
	# still be partially present, and this is not expected.
	if not visible:
		_edit(null)


# TODO Can't hint return as `Vector2?` because it's nullable
func _get_pointed_cell_position(mouse_position: Vector2, p_camera: Camera3D):# -> Vector2:
	# Need to do an extra conversion in case the editor viewport is in half-resolution mode
	var viewport := p_camera.get_viewport()
	var viewport_container : Control = viewport.get_parent()
	var screen_pos = mouse_position * Vector2(viewport.size) / viewport_container.size
	
	var origin = p_camera.project_ray_origin(screen_pos)
	var dir = p_camera.project_ray_normal(screen_pos)

	var ray_distance := p_camera.far * 1.2
	return _node.cell_raycast(origin, dir, ray_distance)


func _forward_3d_gui_input(p_camera: Camera3D, p_event: InputEvent) -> int:
	if _node == null || _node.get_data() == null:
		return AFTER_GUI_INPUT_PASS
	
	_node._edit_update_viewer_position(p_camera)
	_panel.set_camera_transform(p_camera.global_transform)

	var captured_event = false
	
	if p_event is InputEventMouseButton:
		var mb = p_event
		
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed == false:
				_mouse_pressed = false

			# Need to check modifiers before capturing the event,
			# because they are used in navigation schemes
			if (not mb.ctrl_pressed) and (not mb.alt_pressed) and mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					# TODO Allow to paint on click
					# TODO `pressure` is not available in button press events
					# So I have to assume zero to avoid discontinuities with move events
					#_terrain_painter.paint_input(hit_pos_in_cells, 0.0)
					_mouse_pressed = true
				
				captured_event = true
				
				if not _mouse_pressed:
					# Just finished painting
					_pending_paint_commit = true
					_terrain_painter.get_brush().on_paint_end()
		
			if _terrain_painter.get_mode() == HT_TerrainPainter.MODE_FLATTEN \
			and _terrain_painter.has_meta("pick_height") \
			and _terrain_painter.get_meta("pick_height"):
				_terrain_painter.set_meta("pick_height", false)
				# Pick height
				var hit_pos_in_cells = _get_pointed_cell_position(mb.position, p_camera)
				if hit_pos_in_cells != null:
					var h = _node.get_data().get_height_at(
						int(hit_pos_in_cells.x), int(hit_pos_in_cells.y))
					_logger.debug("Picking height {0}".format([h]))
					_terrain_painter.set_flatten_height(h)

	elif p_event is InputEventMouseMotion:
		var mm = p_event
		var hit_pos_in_cells = _get_pointed_cell_position(mm.position, p_camera)
		if hit_pos_in_cells != null:
			_brush_decal.set_position(Vector3(hit_pos_in_cells.x, 0, hit_pos_in_cells.y))
			
			if _mouse_pressed:
				if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					_terrain_painter.paint_input(hit_pos_in_cells, mm.pressure)
					captured_event = true

		# This is in case the data or textures change as the user edits the terrain,
		# to keep the decal working without having to noodle around with nested signals
		_brush_decal.update_visibility()

	if captured_event:
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _process(delta: float):
	if _node == null:
		return

	var has_data = (_node.get_data() != null)
	
	if _pending_paint_commit:
		if has_data:
			if not _terrain_painter.is_operation_pending():
				_pending_paint_commit = false
				if _terrain_painter.has_modified_chunks():
					_logger.debug("Paint completed")
					var changes : Dictionary = _terrain_painter.commit()
					_paint_completed(changes)
		else:
			_pending_paint_commit = false
	
	# Poll presence of data resource
	if has_data != _terrain_had_data_previous_frame:
		_terrain_had_data_previous_frame = has_data
		_update_toolbar_menu_availability()


func _paint_completed(changes: Dictionary):
	var time_before = Time.get_ticks_msec()

	var heightmap_data = _node.get_data()
	assert(heightmap_data != null)
	
	var chunk_positions : Array = changes.chunk_positions
	# Should not create an UndoRedo action if nothing changed
	assert(len(chunk_positions) > 0)
	var changed_maps : Array = changes.maps
	
	var action_name := "Modify HTerrainData "
	for i in len(changed_maps):
		var mm = changed_maps[i]
		var map_debug_name := HTerrainData.get_map_debug_name(mm.map_type, mm.map_index)
		if i > 0:
			action_name += " and "
		action_name += map_debug_name

	var redo_maps := []
	var undo_maps := []
	var chunk_size := _terrain_painter.get_undo_chunk_size()
	
	for map in changed_maps:
		# Cache images to disk so RAM does not continuously go up (or at least much slower)
		for chunks in [map.chunk_initial_datas, map.chunk_final_datas]:
			for i in len(chunks):
				var im : Image = chunks[i]
				chunks[i] = _image_cache.save_image(im)
		
		redo_maps.append({
			"map_type": map.map_type,
			"map_index": map.map_index,
			"chunks": map.chunk_final_datas
		})
		undo_maps.append({
			"map_type": map.map_type,
			"map_index": map.map_index,
			"chunks": map.chunk_initial_datas
		})
	
	var undo_data := {
		"chunk_positions": chunk_positions,
		"chunk_size": chunk_size,
		"maps": undo_maps
	}
	var redo_data := {
		"chunk_positions": chunk_positions,
		"chunk_size": chunk_size,
		"maps": redo_maps
	}
	
#	{
#		chunk_positions: [Vector2, Vector2, ...]
#		chunk_size: int
#		maps: [
#			{
#				map_type: int
#				map_index: int
#				chunks: [
#					int, int, ...
#				]
#			},
#			...
#		]
#	}

	var ur := get_undo_redo()

	ur.create_action(action_name)
	ur.add_do_method(heightmap_data, "_edit_apply_undo", redo_data, _image_cache)
	ur.add_undo_method(heightmap_data, "_edit_apply_undo", undo_data, _image_cache)

	# Small hack here:
	# commit_actions executes the do method, however terrain modifications are heavy ones,
	# so we don't really want to re-run an update in every chunk that was modified during painting.
	# The data is already in its final state,
	# so we just prevent the resource from applying changes here.
	heightmap_data._edit_set_disable_apply_undo(true)
	ur.commit_action()
	heightmap_data._edit_set_disable_apply_undo(false)
	
	var time_spent = Time.get_ticks_msec() - time_before
	_logger.debug(str(action_name, " | ", len(chunk_positions), " chunks | ", time_spent, " ms"))


func _terrain_exited_scene():
	_logger.debug("HTerrain exited the scene")
	_edit(null)


func _menu_item_selected(id: int):
	_logger.debug(str("Menu item selected ", id))
	
	match id:
		MENU_IMPORT_MAPS:
			_import_dialog.popup_centered()
					
		MENU_GENERATE:
			_generator_dialog.popup_centered()
		
		MENU_BAKE_GLOBALMAP:
			var data = _node.get_data()
			if data != null:
				_globalmap_baker.bake(_node)
		
		MENU_RESIZE:
			_resize_dialog.popup_centered()
			
		MENU_UPDATE_EDITOR_COLLIDER:
			# This is for editor tools to be able to use terrain collision.
			# It's not automatic because keeping this collider up to date is
			# expensive, but not too bad IMO because that feature is not often
			# used in editor for now.
			# If users complain too much about this, there are ways to improve it:
			#
			# 1) When the terrain gets deselected, update the terrain collider
			#    in a thread automatically. This is still expensive but should
			#    be easy to do.
			#
			# 2) Bullet actually support modifying the heights dynamically,
			#    as long as we stay within min and max bounds,
			#    so PR a change to the Godot heightmap collider to support passing
			#    a Float Image directly, and make it so the data is in sync
			#    (no CoW plz!!). It's trickier than 1) but almost free.
			#
			_node.update_collider()
		
		MENU_GENERATE_MESH:
			if _node != null and _node.get_data() != null:
				_generate_mesh_dialog.popup_centered()
		
		MENU_EXPORT_HEIGHTMAP:
			if _node != null and _node.get_data() != null:
				_export_image_dialog.popup_centered()
		
		MENU_LOOKDEV:
			# No actions here, it's a submenu
			pass

		MENU_DOCUMENTATION:
			OS.shell_open(DOCUMENTATION_URL)
		
		MENU_ABOUT:
			_about_dialog.popup_centered()


func _on_lookdev_menu_about_to_show():
	_lookdev_menu.clear()
	_lookdev_menu.add_check_item("Disabled")
	_lookdev_menu.set_item_checked(0, not _node.is_lookdev_enabled())
	_lookdev_menu.add_separator()
	var terrain_data : HTerrainData = _node.get_data()
	if terrain_data == null:
		_lookdev_menu.add_item("No terrain data")
		_lookdev_menu.set_item_disabled(0, true)
	else:
		for map_type in HTerrainData.CHANNEL_COUNT:
			var count := terrain_data.get_map_count(map_type)
			for map_index in count:
				var map_name := HTerrainData.get_map_debug_name(map_type, map_index)
				var lookdev_item_index := _lookdev_menu.get_item_count()
				_lookdev_menu.add_item(map_name, lookdev_item_index)
				_lookdev_menu.set_item_metadata(lookdev_item_index, {
					"map_type": map_type,
					"map_index": map_index
				})


func _on_lookdev_menu_id_pressed(id: int):
	var meta = _lookdev_menu.get_item_metadata(id)
	if meta == null:
		_node.set_lookdev_enabled(false)
	else:
		_node.set_lookdev_enabled(true)
		var data : HTerrainData = _node.get_data()
		var map_texture = data.get_texture(meta.map_type, meta.map_index)
		_node.set_lookdev_shader_param("u_map", map_texture)
	_lookdev_menu.set_item_checked(0, not _node.is_lookdev_enabled())


func _on_mode_selected(mode: int):
	_logger.debug(str("On mode selected ", mode))
	_terrain_painter.set_mode(mode)
	_panel.set_brush_editor_display_mode(mode)


func _on_texture_selected(index: int):
	# Switch to texture paint mode when a texture is selected
	_select_brush_mode(HT_TerrainPainter.MODE_SPLAT)
	_terrain_painter.set_texture_index(index)


func _on_detail_selected(index: int):
	# Switch to detail paint mode when a detail item is selected
	_select_brush_mode(HT_TerrainPainter.MODE_DETAIL)
	_terrain_painter.set_detail_index(index)


func _select_brush_mode(mode: int):
	_toolbar_brush_buttons[mode].button_pressed = true
	_on_mode_selected(mode)


static func get_size_from_raw_length(flen: int):
	var side_len = roundf(sqrt(float(flen/2)))
	return int(side_len)


func _on_GenerateMeshDialog_generate_selected(lod: int):
	var data := _node.get_data()
	if data == null:
		_logger.error("Terrain has no data, cannot generate mesh")
		return
	var heightmap := data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var scale := _node.map_scale
	var mesh := HTerrainMesher.make_heightmap_mesh(heightmap, lod, scale, _logger)
	var mi := MeshInstance3D.new()
	mi.name = str(_node.name, "_FullMesh")
	mi.mesh = mesh
	mi.transform = _node.transform
	_node.get_parent().add_child(mi)
	mi.set_owner(get_editor_interface().get_edited_scene_root())


# TODO Workaround for https://github.com/Zylann/godot_heightmap_plugin/issues/101
func _on_permanent_change_performed(message: String):
	var data := _node.get_data()
	if data == null:
		_logger.error("Terrain has no data, cannot mark it as changed")
		return
	var ur := get_undo_redo()
	ur.create_action(message)
	ur.add_do_method(data, "_dummy_function")
	#ur.add_undo_method(data, "_dummy_function")
	ur.commit_action()


func _on_brush_size_changed(size):
	_brush_decal.set_size(size)


func _on_Panel_edit_texture_pressed(index: int):
	var ts := _node.get_texture_set()
	_texture_set_editor.set_texture_set(ts)
	_texture_set_editor.select_slot(index)
	_texture_set_editor.popup_centered()


func _on_TextureSetEditor_import_selected():
	_open_texture_set_import_editor()


func _on_Panel_import_textures_pressed():
	_open_texture_set_import_editor()


func _open_texture_set_import_editor():
	var ts := _node.get_texture_set()
	_texture_set_import_editor.set_texture_set(ts)
	_texture_set_import_editor.popup_centered()


################
# DEBUG LAND

# TEST
#func _physics_process(delta):
#	if Input.is_key_pressed(KEY_KP_0):
#		_debug_spawn_collider_indicators()


func _debug_spawn_collider_indicators():
	var root = get_editor_interface().get_edited_scene_root()
	var terrain := HT_Util.find_first_node(root, HTerrain) as HTerrain
	if terrain == null:
		return
	
	var test_root : Node3D
	if not terrain.has_node("__DEBUG"):
		test_root = Node3D.new()
		test_root.name = "__DEBUG"
		terrain.add_child(test_root)
	else:
		test_root = terrain.get_node("__DEBUG")
	
	var space_state := terrain.get_world_3d().direct_space_state
	var hit_material := StandardMaterial3D.new()
	hit_material.albedo_color = Color(0, 1, 1)
	var cube := BoxMesh.new()
	
	for zi in 16:
		for xi in 16:
			var hit_name := str(xi, "_", zi)
			var pos := Vector3(xi * 16, 1000, zi * 16)
			
			var query := PhysicsRayQueryParameters3D.new()
			query.from = pos
			query.to = pos + Vector3(0, -2000, 0)

			var hit := space_state.intersect_ray(query)

			var mi : MeshInstance3D
			if not test_root.has_node(hit_name):
				mi = MeshInstance3D.new()
				mi.name = hit_name
				mi.material_override = hit_material
				mi.mesh = cube
				test_root.add_child(mi)
			else:
				mi = test_root.get_node(hit_name)
			if hit.is_empty():
				mi.hide()
			else:
				mi.show()
				mi.position = hit.position


func _spawn_vertical_bound_boxes():
	var data := _node.get_data()
#	var sy = data._chunked_vertical_bounds_size_y
#	var sx = data._chunked_vertical_bounds_size_x
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1,1,1,0.2)
	for cy in range(30, 60):
		for cx in range(30, 60):
			var vb := data._chunked_vertical_bounds.get_pixel(cx, cy)
			var minv := vb.r
			var maxv := vb.g
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			var cs := HTerrainData.VERTICAL_BOUNDS_CHUNK_SIZE
			mi.mesh.size = Vector3(cs, maxv - minv, cs)
			mi.position = Vector3(
				(float(cx) + 0.5) * cs,
				minv + mi.mesh.size.y * 0.5, 
				(float(cy) + 0.5) * cs)
			mi.position *= _node.map_scale
			mi.scale = _node.map_scale
			mi.material_override = mat
			_node.add_child(mi)
			mi.owner = get_editor_interface().get_edited_scene_root()
	
#	if p_event is InputEventKey:
#		if p_event.pressed == false:
#			if p_event.scancode == KEY_SPACE and p_event.control:
#				_spawn_vertical_bound_boxes()
