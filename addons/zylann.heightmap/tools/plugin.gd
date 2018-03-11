tool
extends EditorPlugin


const HTerrain = preload("../hterrain.gd")#preload("hterrain.gdns")
const HTerrainData = preload("../hterrain_data.gd")
const Brush = preload("../hterrain_brush.gd")#preload("hterrain_brush.gdns")
const Util = preload("../util.gd")

const EditPanel = preload("panel.tscn")

const MENU_IMPORT_RAW = 0


var _node = null

var _panel = null
var _toolbar = null
var _brush = null
var _mouse_pressed = false

var _import_dialog = null
var _import_confirmation_dialog = null
var _accept_dialog = null
var _import_file_path = ""


static func get_icon(name):
	return load("res://addons/zylann.heightmap/tools/icons/icon_" + name + ".svg")


func _enter_tree():
	print("Heightmap plugin Enter tree")
	
	add_custom_type("HTerrain", "Spatial", HTerrain, get_icon("heightmap_node"))
	add_custom_type("HTerrainData", "Resource", HTerrain, get_icon("heightmap_data"))
	
	_brush = Brush.new()
	_brush.set_radius(5)
	
	_panel = EditPanel.instance()
	_panel.hide()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, _panel)
	
#	_panel = memnew(HeightMapEditorPanel);
#	_panel->connect(HeightMapEditorPanel::SIGNAL_TEXTURE_INDEX_SELECTED, this, "_on_texture_index_selected");
#	HeightMapBrushEditor &brush_editor = _panel->get_brush_editor();
#	brush_editor.init_params(
#			_brush.get_radius(),
#			_brush.get_opacity(),
#			_brush.get_flatten_height(),
#			_brush.get_color());
#	brush_editor.connect(HeightMapBrushEditor::SIGNAL_PARAM_CHANGED, this, "_on_brush_param_changed");
#	add_control_to_container(CONTAINER_SPATIAL_EDITOR_BOTTOM, _panel);
#	_panel->hide();
	
	_toolbar = HBoxContainer.new()
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_toolbar.hide()
	
	var menu = MenuButton.new()
	menu.set_text("HeightMap")
	menu.get_popup().add_item("Import RAW", MENU_IMPORT_RAW)
	menu.get_popup().connect("id_pressed", self, "_menu_item_selected")
	_toolbar.add_child(menu)
	
	var mode_icons = {}
	mode_icons[Brush.MODE_ADD] = get_icon("heightmap_raise")
	mode_icons[Brush.MODE_SUBTRACT] = get_icon("heightmap_lower")
	mode_icons[Brush.MODE_SMOOTH] = get_icon("heightmap_smooth")
	mode_icons[Brush.MODE_FLATTEN] = get_icon("heightmap_flatten")
	mode_icons[Brush.MODE_SPLAT] = get_icon("heightmap_paint")
	mode_icons[Brush.MODE_COLOR] = get_icon("heightmap_paint")
	mode_icons[Brush.MODE_MASK] = get_icon("heightmap_mask")
	
	var mode_tooltips = {}
	mode_tooltips[Brush.MODE_ADD] = "Raise"
	mode_tooltips[Brush.MODE_SUBTRACT] = "Lower"
	mode_tooltips[Brush.MODE_SMOOTH] = "Smooth"
	mode_tooltips[Brush.MODE_FLATTEN] = "Flatten"
	mode_tooltips[Brush.MODE_SPLAT] = "Texture paint"
	mode_tooltips[Brush.MODE_COLOR] = "Color paint"
	mode_tooltips[Brush.MODE_MASK] = "Mask"
	
	_toolbar.add_child(VSeparator.new())
	
	var mode_group = ButtonGroup.new()
	
	for mode in range(Brush.MODE_COUNT):
		var button = ToolButton.new()
		button.icon = mode_icons[mode]
		button.set_tooltip(mode_tooltips[mode])
		button.set_toggle_mode(true)
		button.set_button_group(mode_group)
		
		if mode == _brush.get_mode():
			button.set_pressed(true)
		
		button.connect("pressed", self, "_on_mode_selected", [mode])
		_toolbar.add_child(button)
	
	var editor_interface = get_editor_interface()
	var base_control = editor_interface.get_base_control()
	
	_import_dialog = FileDialog.new()
	_import_dialog.connect("file_selected", self, "_import_raw_file_selected")
	_import_dialog.mode = FileDialog.MODE_OPEN_FILE
	_import_dialog.add_filter("*.raw ; RAW files")
	_import_dialog.resizable = true
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	base_control.add_child(_import_dialog)
	
	_import_confirmation_dialog = ConfirmationDialog.new()
	_import_confirmation_dialog.get_ok().text = "Import anyways"
	_import_confirmation_dialog.connect("confirmed", self, "_import_raw_file");
	base_control.add_child(_import_confirmation_dialog)
	
	_accept_dialog = AcceptDialog.new()
	base_control.add_child(_accept_dialog)


func _exit_tree():
	pass


func handles(object):
	return object is HTerrain


func edit(object):
	print("Edit ", object)
	
	var node = null
	if object != null and object is HTerrain:
		node = object
	
	if _node != null:
		_node.disconnect("tree_exited", self, "_height_map_exited_scene")
	
	_node = node
	
	if _node != null:
		_node.connect("tree_exited", self, "_height_map_exited_scene")
	
	_panel.set_terrain(_node)


func make_visible(visible):
	_panel.set_visible(visible)
	_toolbar.set_visible(visible)


func forward_spatial_gui_input(p_camera, p_event):
	if _node == null:
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
					paint_completed()

	elif p_event is InputEventMouseMotion and _mouse_pressed:
		var mm = p_event
		
		if Input.is_mouse_button_pressed(BUTTON_LEFT):
			paint(p_camera, mm.position)
			captured_event = true

	return captured_event


func paint(camera, screen_pos):
	assert(_node != null)
	
	var origin = camera.project_ray_origin(screen_pos)
	var dir = camera.project_ray_normal(screen_pos)
	
	var hit_pos_in_cells = [0, 0]
	if _node.cell_raycast(origin, dir, hit_pos_in_cells):
		var override_mode = -1
		_brush.paint(_node, hit_pos_in_cells[0], hit_pos_in_cells[1], override_mode)


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

		HTerrainData.CHANNEL_MASK:
			action_name = "Modify HeightMapData Mask"
			
		_:
			action_name = "Modify HeightMapData"
	
	var undo_data = {
		"chunk_positions": ur_data.chunk_positions,
		"data": ur_data.redo,
		"channel": ur_data.channel
	}
	var redo_data = {
		"chunk_positions": ur_data.chunk_positions,
		"data": ur_data.undo,
		"channel": ur_data.channel
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


func _height_map_exited_scene():
	print("HeightMap exited the scene")
	edit(null)


func _menu_item_selected(id):
	print("Menu item selected ", id)
	if id == MENU_IMPORT_RAW:
		_import_dialog.popup_centered_minsize(Vector2(800, 600))


func _on_mode_selected(mode):
	print("On mode selected ", mode)
	_brush.set_mode(mode)


static func get_size_from_raw_length(flen):
	var side_len = round(sqrt(float(flen/2)))
	return int(side_len)


func _import_raw_file_selected(path):
	print("Import raw file selected ", path)
	
	assert(_node != null)
	var data = _node.get_data()
	assert(data != null)

	var f = File.new()
	var err = f.open(path, File.READ)
	if err != OK:
		print("Error opening file ", path)
		return
	
	# Assume the raw data is square, so its size is function of file length
	var flen = f.get_len()
	f.close()
	var size = get_size_from_raw_length(flen)
	
	print("Deduced RAW heightmap resolution: {0}*{1}, for a length of {2}".format(size, size, flen))

	if flen / 2 != size * size:
		_accept_dialog.window_title = "Import RAW heightmap error"
		_accept_dialog.dialog_text = "The square resolution deducted from file size is not square."
		_accept_dialog.popup_centered_minsize()
	
	_import_file_path = path
	
	if Util.next_power_of_two(size) + 1 != size:
		_import_confirmation_dialog.window_title = "Import RAW heightmap"
		_import_confirmation_dialog.dialog_text = \
			"The square resolution deduced from file size is not power of two + 1.\n" + \
			"The heightmap will be cropped.\n Continue?"
		_import_confirmation_dialog.popup_centered_minsize()
	else:
		# Go!
		_import_raw_file()


func _import_raw_file():
	print("Import raw file ", _import_path)


