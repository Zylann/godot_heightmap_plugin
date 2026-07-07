@tool
extends Control

const HT_DetailEditor = preload("./detail_editor/detail_editor.gd")
const HT_EditorMinimap = preload("res://addons/zylann.hterrain/tools/minimap/minimap.gd")


# Emitted when a texture item is selected
signal texture_selected(index: int)
signal edit_texture_pressed(index: int)
signal import_textures_pressed

# Emitted when a detail item is selected (grass painting)
signal detail_selected(index: int)
signal detail_list_changed


@onready var _minimap: HT_EditorMinimap = $HSplitContainer/HSplitContainer/MinimapContainer/Minimap
@onready var _brush_editor = $HSplitContainer/BrushEditor
@onready var _texture_editor = $HSplitContainer/HSplitContainer/HSplitContainer/TextureEditor
@onready var _detail_editor : HT_DetailEditor = \
	$HSplitContainer/HSplitContainer/HSplitContainer/DetailEditor


func setup_dialogs(base_control: Control) -> void:
	_brush_editor.setup_dialogs(base_control)


func set_terrain(terrain) -> void:
	_minimap.set_terrain(terrain)
	_texture_editor.set_terrain(terrain)
	_detail_editor.set_terrain(terrain)


func set_undo_redo(undo_manager: EditorUndoRedoManager) -> void:
	_detail_editor.set_undo_redo(undo_manager)


func set_image_cache(image_cache) -> void:
	_detail_editor.set_image_cache(image_cache)


func set_camera_transform(cam_transform: Transform3D):
	_minimap.set_camera_transform(cam_transform)


func set_terrain_painter(terrain_painter) -> void:
	_brush_editor.set_terrain_painter(terrain_painter)


func _on_TextureEditor_texture_selected(index: int) -> void:
	texture_selected.emit(index)


func _on_DetailEditor_detail_selected(index: int) -> void:
	detail_selected.emit(index)
	_minimap.set_layer_index(index)


func set_brush_editor_display_mode(mode) -> void:
	_brush_editor.set_display_mode(mode)


func set_detail_layer_index(index: int) -> void:
	_detail_editor.set_layer_index(index)


func _on_DetailEditor_detail_list_changed() -> void:
	detail_list_changed.emit()


func _on_TextureEditor_import_pressed() -> void:
	import_textures_pressed.emit()


func _on_TextureEditor_edit_pressed(index: int) -> void:
	edit_texture_pressed.emit(index)
