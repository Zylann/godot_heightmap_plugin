tool
extends EditorPlugin


const HTerrain = preload("../hterrain.gd")
const HTerrainDetailLayer = preload("../hterrain_detail_layer.gd")
const HTerrainData = preload("../hterrain_data.gd")
const HTerrainMesher = preload("../hterrain_mesher.gd")
const PreviewGenerator = preload("./preview_generator.gd")
const Brush = preload("../hterrain_brush.gd")
const BrushDecal = preload("./brush/decal.gd")
const Util = preload("../util/util.gd")
const EditorUtil = preload("./util/editor_util.gd")
const LoadTextureDialog = preload("./load_texture_dialog.gd")
const GlobalMapBaker = preload("./globalmap_baker.gd")
const ImageFileCache = preload("../util/image_file_cache.gd")
const Logger = preload("../util/logger.gd")

const EditPanel = preload("./panel.tscn")
const ProgressWindow = preload("./progress_window.tscn")
const GeneratorDialog = preload("./generator/generator_dialog.tscn")
const ImportDialog = preload("./importer/importer_dialog.tscn")
const GenerateMeshDialog = preload("./generate_mesh_dialog.tscn")
const ResizeDialog = preload("./resize_dialog/resize_dialog.tscn")
const ExportImageDialog = preload("./exporter/export_image_dialog.tscn")

const MENU_IMPORT_MAPS = 0
const MENU_GENERATE = 1
const MENU_BAKE_GLOBALMAP = 2
const MENU_RESIZE = 3
const MENU_UPDATE_EDITOR_COLLIDER = 4
const MENU_GENERATE_MESH = 5
const MENU_EXPORT_HEIGHTMAP = 6


# TODO Rename _terrain
var _node : HTerrain = null

var _panel = null
var _toolbar = null
var _toolbar_brush_buttons = {}
var _generator_dialog = null
var _import_dialog = null
var _export_image_dialog = null
var _progress_window = null
var _load_texture_dialog = null
var _generate_mesh_dialog = null
var _preview_generator = null
var _resize_dialog = null
var _globalmap_baker = null
var _menu_button : MenuButton
var _terrain_had_data_previous_frame = false
var _image_cache : ImageFileCache

var _brush : Brush = null
var _brush_decal : BrushDecal = null
var _mouse_pressed := false
var _pending_paint_action = null
var _pending_paint_completed := false

var _logger = Logger.get_for(self)


static func get_icon(name: String) -> Texture:
	return load("res://addons/zylann.hterrain/tools/icons/icon_" + name + ".svg") as Texture


func _enter_tree():
	_logger.debug("HTerrain plugin Enter tree")
	
	var dpi_scale = EditorUtil.get_dpi_scale(get_editor_interface().get_editor_settings())
	_logger.debug(str("DPI scale: ", dpi_scale))
	
	add_custom_type("HTerrain", "Spatial", HTerrain, get_icon("heightmap_node"))
	add_custom_type("HTerrainDetailLayer", "Spatial", HTerrainDetailLayer, 
		get_icon("detail_layer_node"))
	add_custom_type("HTerrainData", "Resource", HTerrainData, get_icon("heightmap_data"))
	
	_preview_generator = PreviewGenerator.new()
	get_editor_interface().get_resource_previewer().add_preview_generator(_preview_generator)
	
	_brush = Brush.new()
	_brush.set_radius(5)

	_brush_decal = BrushDecal.new()
	_brush_decal.set_shape(_brush.get_shape())
	_brush.connect("shape_changed", _brush_decal, "set_shape")
	
	_image_cache = ImageFileCache.new("user://hterrain_image_cache")
	
	var editor_interface := get_editor_interface()
	var base_control := editor_interface.get_base_control()
	_load_texture_dialog = LoadTextureDialog.new()
	base_control.add_child(_load_texture_dialog)
	
	_panel = EditPanel.instance()
	Util.apply_dpi_scale(_panel, dpi_scale)
	_panel.hide()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, _panel)
	# Apparently _ready() still isn't called at this point...
	_panel.call_deferred("set_brush", _brush)
	_panel.call_deferred("set_load_texture_dialog", _load_texture_dialog)
	_panel.call_deferred("setup_dialogs", base_control)
	_panel.connect("detail_selected", self, "_on_detail_selected")
	_panel.connect("texture_selected", self, "_on_texture_selected")
	_panel.connect("detail_list_changed", self, "_update_brush_buttons_availability")
	
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
	menu.get_popup().connect("id_pressed", self, "_menu_item_selected")
	_toolbar.add_child(menu)
	_menu_button = menu
	
	var mode_icons := {}
	mode_icons[Brush.MODE_ADD] = get_icon("heightmap_raise")
	mode_icons[Brush.MODE_SUBTRACT] = get_icon("heightmap_lower")
	mode_icons[Brush.MODE_SMOOTH] = get_icon("heightmap_smooth")
	mode_icons[Brush.MODE_FLATTEN] = get_icon("heightmap_flatten")
	# TODO Have different icons
	mode_icons[Brush.MODE_SPLAT] = get_icon("heightmap_paint")
	mode_icons[Brush.MODE_COLOR] = get_icon("heightmap_color")
	mode_icons[Brush.MODE_DETAIL] = get_icon("grass")
	mode_icons[Brush.MODE_MASK] = get_icon("heightmap_mask")
	mode_icons[Brush.MODE_LEVEL] = get_icon("heightmap_level")
	
	var mode_tooltips := {}
	mode_tooltips[Brush.MODE_ADD] = "Raise height"
	mode_tooltips[Brush.MODE_SUBTRACT] = "Lower height"
	mode_tooltips[Brush.MODE_SMOOTH] = "Smooth height"
	mode_tooltips[Brush.MODE_FLATTEN] = "Flatten (flatten to a specific height)"
	mode_tooltips[Brush.MODE_SPLAT] = "Texture paint"
	mode_tooltips[Brush.MODE_COLOR] = "Color paint"
	mode_tooltips[Brush.MODE_DETAIL] = "Grass paint"
	mode_tooltips[Brush.MODE_MASK] = "Cut holes"
	mode_tooltips[Brush.MODE_LEVEL] = "Level (smoothly flattens to average)"
	
	_toolbar.add_child(VSeparator.new())
	
	# I want modes to be in that order in the GUI
	var ordered_brush_modes := [
		Brush.MODE_ADD,
		Brush.MODE_SUBTRACT,
		Brush.MODE_SMOOTH,
		Brush.MODE_LEVEL,
		Brush.MODE_FLATTEN,
		Brush.MODE_SPLAT,
		Brush.MODE_COLOR,
		Brush.MODE_DETAIL,
		Brush.MODE_MASK
	]
	
	var mode_group := ButtonGroup.new()
	
	for mode in ordered_brush_modes:
		var button := ToolButton.new()
		button.icon = mode_icons[mode]
		button.set_tooltip(mode_tooltips[mode])
		button.set_toggle_mode(true)
		button.set_button_group(mode_group)
		
		if mode == _brush.get_mode():
			button.set_pressed(true)
		
		button.connect("pressed", self, "_on_mode_selected", [mode])
		_toolbar.add_child(button)
		
		_toolbar_brush_buttons[mode] = button
	
	_generator_dialog = GeneratorDialog.instance()
	_generator_dialog.connect("progress_notified", self, "_terrain_progress_notified")
	_generator_dialog.set_image_cache(_image_cache)
	_generator_dialog.set_undo_redo(get_undo_redo())
	base_control.add_child(_generator_dialog)
	_generator_dialog.apply_dpi_scale(dpi_scale)

	_import_dialog = ImportDialog.instance()
	_import_dialog.connect("permanent_change_performed", self, "_on_permanent_change_performed")
	Util.apply_dpi_scale(_import_dialog, dpi_scale)
	base_control.add_child(_import_dialog)

	_progress_window = ProgressWindow.instance()
	base_control.add_child(_progress_window)
	
	_generate_mesh_dialog = GenerateMeshDialog.instance()
	_generate_mesh_dialog.connect("generate_selected", self, "_on_GenerateMeshDialog_generate_selected")
	Util.apply_dpi_scale(_generate_mesh_dialog, dpi_scale)
	base_control.add_child(_generate_mesh_dialog)
	
	_resize_dialog = ResizeDialog.instance()
	_resize_dialog.connect("permanent_change_performed", self, "_on_permanent_change_performed")
	Util.apply_dpi_scale(_resize_dialog, dpi_scale)
	base_control.add_child(_resize_dialog)
	
	_globalmap_baker = GlobalMapBaker.new()
	_globalmap_baker.connect("progress_notified", self, "_terrain_progress_notified")
	_globalmap_baker.connect("permanent_change_performed", self, "_on_permanent_change_performed")
	add_child(_globalmap_baker)
	
	_export_image_dialog = ExportImageDialog.instance()
	Util.apply_dpi_scale(_export_image_dialog, dpi_scale)
	base_control.add_child(_export_image_dialog)
	# Need to call deferred because in the specific case where you start the editor
	# with the plugin enabled, _ready won't be called at this point
	_export_image_dialog.call_deferred("setup_dialogs", base_control)


func _exit_tree():
	_logger.debug("HTerrain plugin Exit tree")
	
	# Make sure we release all references to edited stuff
	edit(null)

	_panel.queue_free()
	_panel = null
	
	_toolbar.queue_free()
	_toolbar = null
	
	_load_texture_dialog.queue_free()
	_load_texture_dialog = null
	
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

	get_editor_interface().get_resource_previewer().remove_preview_generator(_preview_generator)
	_preview_generator = null
	
	# TODO Manual clear cuz it can't do it automatically due to a Godot bug
	_image_cache.clear()
	
	# TODO https://github.com/godotengine/godot/issues/6254#issuecomment-246139694
	# This was supposed to be automatic, but was never implemented it seems...
	remove_custom_type("HTerrain")
	remove_custom_type("HTerrainDetailLayer")
	remove_custom_type("HTerrainData")


func handles(object):
	return _get_terrain_from_object(object) != null


func edit(object):
	_logger.debug(str("Edit ", object))
	
	var node = _get_terrain_from_object(object)
	
	if _node != null:
		_node.disconnect("tree_exited", self, "_terrain_exited_scene")
	
	_node = node
	
	if _node != null:
		_node.connect("tree_exited", self, "_terrain_exited_scene")
	
	_update_brush_buttons_availability()
	
	_panel.set_terrain(_node)
	_generator_dialog.set_terrain(_node)
	_import_dialog.set_terrain(_node)
	_brush_decal.set_terrain(_node)
	_generate_mesh_dialog.set_terrain(_node)
	_resize_dialog.set_terrain(_node)
	_export_image_dialog.set_terrain(_node)
	
	if object is HTerrainDetailLayer:
		# Auto-select layer for painting
		_panel.set_detail_layer_index(object.get_layer_index())
		_on_detail_selected(object.get_layer_index())
	
	_update_toolbar_menu_availability()


static func _get_terrain_from_object(object):
	if object != null and object is Spatial:
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
			var button = _toolbar_brush_buttons[Brush.MODE_DETAIL]
			button.disabled = false
		else:
			var button = _toolbar_brush_buttons[Brush.MODE_DETAIL]
			if button.pressed:
				_select_brush_mode(Brush.MODE_ADD)
			button.disabled = true


func _update_toolbar_menu_availability():
	var data_available = false
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


func make_visible(visible):
	_panel.set_visible(visible)
	_toolbar.set_visible(visible)
	_brush_decal.update_visibility()

	# TODO Workaround https://github.com/godotengine/godot/issues/6459
	# When the user selects another node,
	# I want the plugin to release its references to the terrain.
	if not visible:
		edit(null)


func forward_spatial_gui_input(p_camera: Camera, p_event: InputEvent) -> bool:
	if _node == null || _node.get_data() == null:
		return false
	
	_node._edit_update_viewer_position(p_camera)

	var captured_event = false
	
	if p_event is InputEventMouseButton:
		var mb = p_event
		
		if mb.button_index == BUTTON_LEFT or mb.button_index == BUTTON_RIGHT:
			if mb.pressed == false:
				_mouse_pressed = false

			# Need to check modifiers before capturing the event,
			# because they are used in navigation schemes
			if (not mb.control) and (not mb.alt) and mb.button_index == BUTTON_LEFT:
				if mb.pressed:
					_mouse_pressed = true
				
				captured_event = true
				
				if not _mouse_pressed:
					# Just finished painting
					_pending_paint_completed = true

	elif p_event is InputEventMouseMotion:
		var mm = p_event
		
		# Need to do an extra conversion in case the editor viewport is in half-resolution mode
		var viewport = p_camera.get_viewport()
		var viewport_container = viewport.get_parent()
		var screen_pos = mm.position * viewport.size / viewport_container.rect_size
		
		var origin = p_camera.project_ray_origin(screen_pos)
		var dir = p_camera.project_ray_normal(screen_pos)

		var ray_distance := p_camera.far * 1.2
		var hit_pos_in_cells = _node.cell_raycast(origin, dir, ray_distance)
		if hit_pos_in_cells != null:
			_brush_decal.set_position(Vector3(hit_pos_in_cells.x, 0, hit_pos_in_cells.y))
			
			if _mouse_pressed:
				if Input.is_mouse_button_pressed(BUTTON_LEFT):
					
					# Deferring this to be done once per frame,
					# because mouse events may happen more often than frames,
					# which can result in unpleasant stuttering/freezes when painting large areas
					_pending_paint_action = [
						int(hit_pos_in_cells.x),
						int(hit_pos_in_cells.y)
					]
					
					captured_event = true

		# This is in case the data or textures change as the user edits the terrain,
		# to keep the decal working without having to noodle around with nested signals
		_brush_decal.update_visibility()

	return captured_event


func _process(delta):
	var has_data = false
	
	if _node != null:
		if _pending_paint_action != null:
			var override_mode = -1
			_brush.paint(_node, _pending_paint_action[0], _pending_paint_action[1], override_mode)

		if _pending_paint_completed:
			_paint_completed()
		
		has_data = (_node.get_data() != null)
	
	# Poll presence of data resource
	if has_data != _terrain_had_data_previous_frame:
		_terrain_had_data_previous_frame = has_data
		_update_toolbar_menu_availability()

	_pending_paint_completed = false
	_pending_paint_action = null


func _paint_completed():
	var heightmap_data = _node.get_data()
	assert(heightmap_data != null)
	
	var ur_data = _brush._edit_pop_undo_redo_data(heightmap_data)
	
	var ur = get_undo_redo()
	
	var action_name = ""
	match ur_data.channel:
		
		HTerrainData.CHANNEL_COLOR:
			action_name = "Modify HeightMapData Color"
			
		HTerrainData.CHANNEL_SPLAT:
			action_name = "Modify HeightMapData Splat"
			
		HTerrainData.CHANNEL_HEIGHT:
			action_name = "Modify HeightMapData Height"

		HTerrainData.CHANNEL_DETAIL:
			action_name = "Modify HeightMapData Detail"
			
		_:
			action_name = "Modify HeightMapData"
	
	var undo_data = {
		"chunk_positions": ur_data.chunk_positions,
		"data": ur_data.redo,
		"channel": ur_data.channel,
		"index": ur_data.index,
		"chunk_size": ur_data.chunk_size
	}
	var redo_data = {
		"chunk_positions": ur_data.chunk_positions,
		"data": ur_data.undo,
		"channel": ur_data.channel,
		"index": ur_data.index,
		"chunk_size": ur_data.chunk_size
	}

	ur.create_action(action_name)
	ur.add_do_method(heightmap_data, "_edit_apply_undo", undo_data)
	ur.add_undo_method(heightmap_data, "_edit_apply_undo", redo_data)

	# Small hack here:
	# commit_actions executes the do method, however terrain modifications are heavy ones,
	# so we don't really want to re-run an update in every chunk that was modified during painting.
	# The data is already in its final state,
	# so we just prevent the resource from applying changes here.
	heightmap_data._edit_set_disable_apply_undo(true)
	ur.commit_action()
	heightmap_data._edit_set_disable_apply_undo(false)


func _terrain_exited_scene():
	_logger.debug("HTerrain exited the scene")
	edit(null)


func _menu_item_selected(id):
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


func _on_mode_selected(mode: int):
	_logger.debug(str("On mode selected ", mode))
	_brush.set_mode(mode)
	_panel.set_brush_editor_display_mode(mode)


func _on_texture_selected(index: int):
	# Switch to texture paint mode when a texture is selected
	_select_brush_mode(Brush.MODE_SPLAT)
	_brush.set_texture_index(index)


func _on_detail_selected(index: int):
	# Switch to detail paint mode when a detail item is selected
	_select_brush_mode(Brush.MODE_DETAIL)
	_brush.set_detail_index(index)


func _select_brush_mode(mode: int):
	_toolbar_brush_buttons[mode].pressed = true
	_on_mode_selected(mode)


static func get_size_from_raw_length(flen: int):
	var side_len = round(sqrt(float(flen/2)))
	return int(side_len)


func _terrain_progress_notified(info):
	if info.has("finished") and info.finished:
		_progress_window.hide()
	
	else:
		if not _progress_window.visible:
			_progress_window.popup_centered()
		
		var message = ""
		if info.has("message"):
			message = info.message
		
		_progress_window.show_progress(info.message, info.progress)
		# TODO Have builtin modal progress bar
		# https://github.com/godotengine/godot/issues/17763


func _on_GenerateMeshDialog_generate_selected(lod: int):
	var data := _node.get_data()
	if data == null:
		_logger.error("Terrain has no data, cannot generate mesh")
		return
	var heightmap := data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var scale := _node.map_scale
	var mesh := HTerrainMesher.make_heightmap_mesh(heightmap, lod, scale, _logger)
	var mi := MeshInstance.new()
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


################
# DEBUG LAND

# TEST
#func _physics_process(delta):
#	if Input.is_key_pressed(KEY_KP_0):
#		_debug_spawn_collider_indicators()


func _debug_spawn_collider_indicators():
	var root = get_editor_interface().get_edited_scene_root()
	var terrain := Util.find_first_node(root, HTerrain) as HTerrain
	if terrain == null:
		return
	
	var test_root : Spatial
	if not terrain.has_node("__DEBUG"):
		test_root = Spatial.new()
		test_root.name = "__DEBUG"
		terrain.add_child(test_root)
	else:
		test_root = terrain.get_node("__DEBUG")
	
	var space_state := terrain.get_world().direct_space_state
	var hit_material = SpatialMaterial.new()
	hit_material.albedo_color = Color(0, 1, 1)
	var cube = CubeMesh.new()
	
	for zi in 16:
		for xi in 16:
			var hit_name = str(xi, "_", zi)
			var pos = Vector3(xi * 16, 1000, zi * 16)
			var hit = space_state.intersect_ray(pos, pos + Vector3(0, -2000, 0))
			var mi : MeshInstance
			if not test_root.has_node(hit_name):
				mi = MeshInstance.new()
				mi.name = hit_name
				mi.material_override = hit_material
				mi.mesh = cube
				test_root.add_child(mi)
			else:
				mi = test_root.get_node(hit_name)
			if hit.empty():
				mi.hide()
			else:
				mi.show()
				mi.translation = hit.position


func _spawn_vertical_bound_boxes():
	var data = _node.get_data()
#	var sy = data._chunked_vertical_bounds_size_y
#	var sx = data._chunked_vertical_bounds_size_x
	var mat = SpatialMaterial.new()
	mat.flags_transparent = true
	mat.albedo_color = Color(1,1,1,0.2)
	for cy in range(30, 60):
		for cx in range(30, 60):
			var vb = data._chunked_vertical_bounds[cy][cx]
			var mi = MeshInstance.new()
			mi.mesh = CubeMesh.new()
			var cs = HTerrainData.VERTICAL_BOUNDS_CHUNK_SIZE
			mi.mesh.size = Vector3(cs, vb.maxv - vb.minv, cs)
			mi.translation = Vector3(
				(float(cx) + 0.5) * cs,
				vb.minv + mi.mesh.size.y * 0.5, 
				(float(cy) + 0.5) * cs)
			mi.translation *= _node.map_scale
			mi.scale = _node.map_scale
			mi.material_override = mat
			_node.add_child(mi)
			mi.owner = get_editor_interface().get_edited_scene_root()
			
#	if p_event is InputEventKey:
#		if p_event.pressed == false:
#			if p_event.scancode == KEY_SPACE and p_event.control:
#				_spawn_vertical_bound_boxes()
