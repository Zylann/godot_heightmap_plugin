@tool
extends Control

const HT_DetailEditor = preload("./detail_editor/detail_editor.gd")


# Emitted when a texture item is selected
signal texture_selected(index)
signal edit_texture_pressed(index)
signal import_textures_pressed

# Emitted when a detail item is selected (grass painting)
signal detail_selected(index)
signal detail_list_changed


@onready var _minimap = $HSplitContainer/HSplitContainer/MinimapContainer/Minimap
@onready var _brush_editor = $HSplitContainer/BrushEditor
@onready var _texture_editor = $HSplitContainer/HSplitContainer/HSplitContainer/TextureEditor
@onready var _detail_editor : HT_DetailEditor = \
	$HSplitContainer/HSplitContainer/HSplitContainer/DetailEditor


func setup_dialogs(base_control: Control):
	_brush_editor.setup_dialogs(base_control)


func set_terrain(terrain):
	_minimap.set_terrain(terrain)
	_texture_editor.set_terrain(terrain)
	_detail_editor.set_terrain(terrain)


func set_undo_redo(undo_manager: EditorUndoRedoManager):
	_detail_editor.set_undo_redo(undo_manager)


func set_image_cache(image_cache):
	_detail_editor.set_image_cache(image_cache)


func set_camera_transform(cam_transform: Transform3D):
	_minimap.set_camera_transform(cam_transform)


func set_terrain_painter(terrain_painter):
	_brush_editor.set_terrain_painter(terrain_painter)


func _on_TextureEditor_texture_selected(index):
	texture_selected.emit(index)


func _on_DetailEditor_detail_selected(index):
	detail_selected.emit(index)


func set_brush_editor_display_mode(mode):
	_brush_editor.set_display_mode(mode)


func set_detail_layer_index(index):
	_detail_editor.set_layer_index(index)


func _on_DetailEditor_detail_list_changed():
	detail_list_changed.emit()


func _on_TextureEditor_import_pressed():
	import_textures_pressed.emit()


func _on_TextureEditor_edit_pressed(index: int):
	edit_texture_pressed.emit(index)
