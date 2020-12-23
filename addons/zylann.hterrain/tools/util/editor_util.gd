
# Editor-specific utilities.
# This script cannot be loaded in an exported game.

tool

# TODO There is no script API to access editor scale
# Ported from https://github.com/godotengine/godot/blob/
# 5fede4a81c67961c6fb2309b9b0ceb753d143566/editor/editor_node.cpp#L5515-L5554
static func get_dpi_scale(editor_settings: EditorSettings) -> float:
	var display_scale = editor_settings.get("interface/editor/display_scale")
	var custom_display_scale = editor_settings.get("interface/editor/custom_display_scale")
	var edscale := 0.0

	match display_scale:
		0:
			# Try applying a suitable display scale automatically
			var screen = OS.current_screen
			var large = OS.get_screen_dpi(screen) >= 192 and OS.get_screen_size(screen).x > 2000
			edscale = 2.0 if large else 1.0
		1:
			edscale = 0.75
		2:
			edscale = 1.0
		3:
			edscale = 1.25
		4:
			edscale = 1.5
		5:
			edscale = 1.75
		6:
			edscale = 2.0
		_:
			edscale = custom_display_scale

	return edscale


# This is normally an `EditorFileDialog`. I can't type-hint this one properly,
# because when I test UI in isolation, I can't use `EditorFileDialog`.
static func create_open_file_dialog() -> ConfirmationDialog:
	var d
	if Engine.editor_hint:
		d = EditorFileDialog.new()
		d.mode = EditorFileDialog.MODE_OPEN_FILE
		d.access = EditorFileDialog.ACCESS_RESOURCES
	else:
		# Duh. I need to be able to test it.
		d = FileDialog.new()
		d.mode = FileDialog.MODE_OPEN_FILE
		d.access = FileDialog.ACCESS_RESOURCES
	d.resizable = true
	return d


static func create_open_dir_dialog() -> ConfirmationDialog:
	var d
	if Engine.editor_hint:
		d = EditorFileDialog.new()
		d.mode = EditorFileDialog.MODE_OPEN_DIR
		d.access = EditorFileDialog.ACCESS_RESOURCES
	else:
		# Duh. I need to be able to test it.
		d = FileDialog.new()
		d.mode = FileDialog.MODE_OPEN_DIR
		d.access = FileDialog.ACCESS_RESOURCES
	d.resizable = true
	return d


# If you want to open using Image.load()
static func create_open_image_dialog() -> ConfirmationDialog:
	var d = create_open_file_dialog()
	_add_image_filters(d)
	return d


# If you want to open using load(),
# although it might still fail if the file is imported as Image...
static func create_open_texture_dialog() -> ConfirmationDialog:
	var d = create_open_file_dialog()
	_add_texture_filters(d)
	return d


static func create_open_texture_array_dialog() -> ConfirmationDialog:
	var d = create_open_file_dialog()
	_add_texture_array_filters(d)
	return d

# TODO Post a proposal, we need a file dialog filtering on resource types, not on file extensions!

static func _add_image_filters(file_dialog):
	file_dialog.add_filter("*.png ; PNG files")
	file_dialog.add_filter("*.jpg ; JPG files")
	#file_dialog.add_filter("*.exr ; EXR files")


static func _add_texture_filters(file_dialog):
	_add_image_filters(file_dialog)
	file_dialog.add_filter("*.stex ; StreamTexture files")
	file_dialog.add_filter("*.packed_tex ; HTerrainPackedTexture files")


static func _add_texture_array_filters(file_dialog):
	_add_image_filters(file_dialog)
	file_dialog.add_filter("*.texarr ; TextureArray files")
	file_dialog.add_filter("*.packed_texarr ; HTerrainPackedTextureArray files")
