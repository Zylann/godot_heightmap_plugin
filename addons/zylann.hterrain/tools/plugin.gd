tool
extends EditorPlugin


const HTerrain = preload("../hterrain.gd")
const HTerrainDetailLayer = preload("../hterrain_detail_layer.gd")
const HTerrainData = preload("../hterrain_data.gd")
const HTerrainMesher = preload("../hterrain_mesher.gd")
const PreviewGenerator = preload("preview_generator.gd")
const Brush = preload("../hterrain_brush.gd")
const BrushDecal = preload("brush/decal.gd")
const Util = preload("../util/util.gd")
const LoadTextureDialog = preload("load_texture_dialog.gd")
const EditPanel = preload("panel.tscn")
const ProgressWindow = preload("progress_window.tscn")
const GeneratorDialog = preload("generator/generator_dialog.tscn")
const ImportDialog = preload("importer/importer_dialog.tscn")
const GenerateMeshDialog = preload("generate_mesh_dialog.tscn")
const ResizeDialog = preload("resize_dialog/resize_dialog.tscn")
const GlobalMapBaker = preload("globalmap_baker.gd")
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

var _brush = null
var _brush_decal = null
var _mouse_pressed = false
var _pending_paint_action = null
var _pending_paint_completed = false


static func get_icon(name):
	return load("res://addons/zylann.hterrain/tools/icons/icon_" + name + ".svg")


func _enter_tree():
	print("HTerrain plugin Enter tree")
	
	add_custom_type("HTerrain", "Spatial", HTerrain, get_icon("heightmap_node"))
	add_custom_type("HTerrainDetailLayer", "Spatial", HTerrainDetailLayer, get_icon("detail_layer_node"))
	add_custom_type("HTerrainData", "Resource", HTerrainData, get_icon("heightmap_data"))
	
	_preview_generator = PreviewGenerator.new()
	get_editor_interface().get_resource_previewer().add_preview_generator(_preview_generator)
	
	_brush = Brush.new()
	_brush.set_radius(5)

	_brush_decal = BrushDecal.new()
	_brush_decal.set_shape(_brush.get_shape())
	_brush.connect("shape_changed", _brush_decal, "set_shape")
	
	var editor_interface = get_editor_interface()
	var base_control = editor_interface.get_base_control()
	_load_texture_dialog = LoadTextureDialog.new()
	base_control.add_child(_load_texture_dialog)
	
	_panel = EditPanel.instance()
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
	
	var menu = MenuButton.new()
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
	
	var mode_icons = {}
	mode_icons[Brush.MODE_ADD] = get_icon("heightmap_raise")
	mode_icons[Brush.MODE_SUBTRACT] = get_icon("heightmap_lower")
	mode_icons[Brush.MODE_SMOOTH] = get_icon("heightmap_smooth")
	mode_icons[Brush.MODE_FLATTEN] = get_icon("heightmap_flatten")
	# TODO Have different icons
	mode_icons[Brush.MODE_SPLAT] = get_icon("heightmap_paint")
	mode_icons[Brush.MODE_COLOR] = get_icon("heightmap_color")
	mode_icons[Brush.MODE_DETAIL] = get_icon("grass")
	mode_icons[Brush.MODE_MASK] = get_icon("heightmap_mask")
	
	var mode_tooltips = {}
	mode_tooltips[Brush.MODE_ADD] = "Raise"
	mode_tooltips[Brush.MODE_SUBTRACT] = "Lower"
	mode_tooltips[Brush.MODE_SMOOTH] = "Smooth"
	mode_tooltips[Brush.MODE_FLATTEN] = "Flatten"
	mode_tooltips[Brush.MODE_SPLAT] = "Texture paint"
	mode_tooltips[Brush.MODE_COLOR] = "Color paint"
	mode_tooltips[Brush.MODE_DETAIL] = "Grass paint"
	mode_tooltips[Brush.MODE_MASK] = "Cut holes"
	
	_toolbar.add_child(VSeparator.new())
	
	# I want modes to be in that order in the GUI
	var ordered_brush_modes = [
		Brush.MODE_ADD,
		Brush.MODE_SUBTRACT,
		Brush.MODE_SMOOTH,
		Brush.MODE_FLATTEN,
		Brush.MODE_SPLAT,
		Brush.MODE_COLOR,
		Brush.MODE_DETAIL,
		Brush.MODE_MASK
	]
	
	var mode_group = ButtonGroup.new()
	
	for mode in ordered_brush_modes:
		var button = ToolButton.new()
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
	_generator_dialog.connect("permanent_change_performed", self, "_on_permanent_change_performed")
	base_control.add_child(_generator_dialog)

	_import_dialog = ImportDialog.instance()
	_import_dialog.connect("permanent_change_performed", self, "_on_permanent_change_performed")
	base_control.add_child(_import_dialog)

	_progress_window = ProgressWindow.instance()
	base_control.add_child(_progress_window)
	
	_generate_mesh_dialog = GenerateMeshDialog.instance()
	_generate_mesh_dialog.connect("generate_selected", self, "_on_GenerateMeshDialog_generate_selected")
	base_control.add_child(_generate_mesh_dialog)
	
	_resize_dialog = ResizeDialog.instance()
	_resize_dialog.connect("permanent_change_performed", self, "_on_permanent_change_performed")
	base_control.add_child(_resize_dialog)
	
	_globalmap_baker = GlobalMapBaker.new()
	_globalmap_baker.connect("progress_notified", self, "_terrain_progress_notified")
	_globalmap_baker.connect("permanent_change_performed", self, "_on_permanent_change_performed")
	add_child(_globalmap_baker)
	
	_export_image_dialog = ExportImageDialog.instance()
	base_control.add_child(_export_image_dialog)
	# Need to call deferred because in the specific case where you start the editor
	# with the plugin enabled, _ready won't be called at this point
	_export_image_dialog.call_deferred("setup_dialogs", base_control)


func _exit_tree():
	print("HTerrain plugin Exit tree")
	
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
	
	# TODO https://github.com/godotengine/godot/issues/6254#issuecomment-246139694
	# This was supposed to be automatic, but was never implemented it seems...
	remove_custom_type("HTerrain")
	remove_custom_type("HTerrainDetailLayer")
	remove_custom_type("HTerrainData")


func handles(object):
	return _get_terrain_from_object(object) != null


func edit(object):
	print("Edit ", object)
	
	var node = _get_terrain_from_object(object)
	
	if _node != null:
		_node.disconnect("tree_exited", self, "_terrain_exited_scene")
		_node.disconnect("progress_notified", self, "_terrain_progress_notified")
	
	_node = node
	
	if _node != null:
		_node.connect("tree_exited", self, "_terrain_exited_scene")
		_node.connect("progress_notified", self, "_terrain_progress_notified")
	
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
		if object is HTerrain:
			return object
		if object is HTerrainDetailLayer and object.is_inside_tree() and object.get_parent() is HTerrain:
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
	# When the user selects another node, I want the plugin to release its references to the terrain.
	if not visible:
		edit(null)


func forward_spatial_gui_input(p_camera, p_event):
	if _node == null || _node.get_data() == null:
		return false
	
	_node._edit_set_manual_viewer_pos(p_camera.global_transform.origin)
	
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
		
		var screen_pos = mm.position
		var origin = p_camera.project_ray_origin(screen_pos)
		var dir = p_camera.project_ray_normal(screen_pos)
		
		var hit_pos_in_cells = [0, 0]
		if _node.cell_raycast(origin, dir, hit_pos_in_cells):
			
			_brush_decal.set_position(Vector3(hit_pos_in_cells[0], 0, hit_pos_in_cells[1]))
						
			if _mouse_pressed:
				if Input.is_mouse_button_pressed(BUTTON_LEFT):
					
					# Deferring this to be done once per frame,
					# because mouse events may happen more often than frames,
					# which can result in unpleasant stuttering/freezes when painting large areas
					_pending_paint_action = [hit_pos_in_cells[0], hit_pos_in_cells[1]]
					
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
			paint_completed()
		
		has_data = (_node.get_data() != null)
	
	# Poll presence of data resource
	if has_data != _terrain_had_data_previous_frame:
		_terrain_had_data_previous_frame = has_data
		_update_toolbar_menu_availability()

	_pending_paint_completed = false
	_pending_paint_action = null


func paint_completed():
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
	print("HTerrain exited the scene")
	edit(null)


func _menu_item_selected(id):
	print("Menu item selected ", id)
	match id:
		
		MENU_IMPORT_MAPS:
			_import_dialog.popup_centered_minsize()
					
		MENU_GENERATE:
			_generator_dialog.popup_centered_minsize()
		
		MENU_BAKE_GLOBALMAP:
			var data = _node.get_data()
			if data != null:
				_globalmap_baker.bake(_node)
		
		MENU_RESIZE:
			_resize_dialog.popup_centered_minsize()
			
		MENU_UPDATE_EDITOR_COLLIDER:
			# This is for editor tools to be able to use terrain collision.
			# It's not automatic because keeping this collider up to date is expensive,
			# but not too bad IMO because that feature is not often used in editor for now.
			# If users complain too much about this, there are ways to improve it:
			#
			# 1) When the terrain gets deselected, update the terrain collider in a thread automatically.
			#    This is still expensive but should be easy to do.
			#
			# 2) Bullet actually support modifying the heights dynamically,
			#    as long as we stay within min and max bounds,
			#    so PR a change to the Godot heightmap collider to support passing a Float Image directly,
			#    and make it so the data is in sync (no CoW plz!!). It's trickier than 1) but almost free.
			#
			_node.update_collider()
		
		MENU_GENERATE_MESH:
			if _node != null and _node.get_data() != null:
				_generate_mesh_dialog.popup_centered_minsize()
		
		MENU_EXPORT_HEIGHTMAP:
			if _node != null and _node.get_data() != null:
				_export_image_dialog.popup_centered_minsize()


func _on_mode_selected(mode):
	print("On mode selected ", mode)
	_brush.set_mode(mode)
	_panel.set_brush_editor_display_mode(mode)


func _on_texture_selected(index):
	# Switch to texture paint mode when a texture is selected
	_select_brush_mode(Brush.MODE_SPLAT)
	_brush.set_texture_index(index)


func _on_detail_selected(index):
	# Switch to detail paint mode when a detail item is selected
	_select_brush_mode(Brush.MODE_DETAIL)
	_brush.set_detail_index(index)


func _select_brush_mode(mode):
	_toolbar_brush_buttons[mode].pressed = true
	_on_mode_selected(mode)


static func get_size_from_raw_length(flen):
	var side_len = round(sqrt(float(flen/2)))
	return int(side_len)


func _terrain_progress_notified(info):
	#print("Plugin received: ", info.message, ", ", int(info.progress * 100.0), "%")
	
	if info.has("finished") and info.finished:
		_progress_window.hide()
	
	else:
		if not _progress_window.visible:
			_progress_window.popup_centered_minsize()
		
		var message = ""
		if info.has("message"):
			message = info.message
		
		_progress_window.show_progress(info.message, info.progress)
		# TODO Have builtin modal progress bar
		# https://github.com/godotengine/godot/issues/17763


func _on_GenerateMeshDialog_generate_selected(lod):
	var data = _node.get_data()
	if data == null:
		printerr("Terrain has no data")
		return
	var heightmap = data.get_image(HTerrainData.CHANNEL_HEIGHT)
	var scale = _node.map_scale
	var mesh = HTerrainMesher.make_heightmap_mesh(heightmap, lod, scale)
	var mi = MeshInstance.new()
	mi.name = str(_node.name, "_FullMesh")
	mi.mesh = mesh
	mi.transform = _node.transform
	_node.get_parent().add_child(mi)
	mi.set_owner(get_editor_interface().get_edited_scene_root())


# TODO Workaround for https://github.com/Zylann/godot_heightmap_plugin/issues/101
func _on_permanent_change_performed(message):
	var data = _node.get_data()
	if data == null:
		printerr("Terrain has no data")
		return
	var ur = get_undo_redo()
	ur.create_action(message)
	ur.add_do_method(data, "_dummy_function")
	#ur.add_undo_method(data, "_dummy_function")
	ur.commit_action()

