
# Editor-specific utilities.
# This script cannot be loaded in an exported game.

@tool


# This is normally an `EditorFileDialog`. I can't type-hint this one properly,
# because when I test UI in isolation, I can't use `EditorFileDialog`.
static func create_open_file_dialog() -> ConfirmationDialog:
	var d
	if Engine.is_editor_hint():
		# TODO Workaround bug when editor-only classes are created in source code, even if not run
		# https://github.com/godotengine/godot/issues/73525
#		d = EditorFileDialog.new()
		d = ClassDB.instantiate(&"EditorFileDialog")
		d.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
		d.access = EditorFileDialog.ACCESS_RESOURCES
	else:
		d = FileDialog.new()
		d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		d.access = FileDialog.ACCESS_RESOURCES
	d.unresizable = false
	return d


static func create_open_dir_dialog() -> ConfirmationDialog:
	var d
	if Engine.is_editor_hint():
		# TODO Workaround bug when editor-only classes are created in source code, even if not run
		# https://github.com/godotengine/godot/issues/73525
#		d = EditorFileDialog.new()
		d = ClassDB.instantiate(&"EditorFileDialog")
		d.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
		d.access = EditorFileDialog.ACCESS_RESOURCES
	else:
		d = FileDialog.new()
		d.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		d.access = FileDialog.ACCESS_RESOURCES
	d.unresizable = false
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
	# Godot
	file_dialog.add_filter("*.ctex ; CompressedTexture files")
	# Packed textures
	file_dialog.add_filter("*.packed_tex ; HTerrainPackedTexture files")


static func _add_texture_array_filters(file_dialog):
	_add_image_filters(file_dialog)
	# Godot
	file_dialog.add_filter("*.ctexarray ; TextureArray files")
	# Packed textures
	file_dialog.add_filter("*.packed_texarr ; HTerrainPackedTextureArray files")


# Tries to load a texture with the ResourceLoader, and if it fails, attempts
# to load it manually as an ImageTexture
static func load_texture(path: String, logger) -> Texture:
	var tex : Texture = load(path)
	if tex != null:
		return tex
	# This can unfortunately happen when the editor didn't import assets yet.
	# See https://github.com/godotengine/godot/issues/17483
	logger.error(str("Failed to load texture ", path, ", attempting to load manually"))
	var im := Image.new()
	var err = im.load(path)
	if err != OK:
		logger.error(str("Failed to load image ", path))
		return null
	var itex := ImageTexture.create_from_image(im)
	return itex

