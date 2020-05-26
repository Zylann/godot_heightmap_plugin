tool
extends Control


# Emitted when a texture item is selected
signal texture_selected(index)

# Emitted when a detail item is selected (grass painting)
signal detail_selected(index)

signal detail_list_changed


onready var _minimap = $HSplitContainer/HSplitContainer/MinimapContainer/Minimap
onready var _brush_editor = $HSplitContainer/BrushEditor
onready var _texture_editor = $HSplitContainer/HSplitContainer/HSplitContainer/TextureEditor
onready var _detail_editor = $HSplitContainer/HSplitContainer/HSplitContainer/DetailEditor


func setup_dialogs(base_control):
	_brush_editor.setup_dialogs(base_control)


func set_terrain(terrain):
	_minimap.set_terrain(terrain)
	_texture_editor.set_terrain(terrain)
	_detail_editor.set_terrain(terrain)


func set_camera_transform(cam_transform: Transform):
	_minimap.set_camera_transform(cam_transform)


func set_brush(brush):
	_brush_editor.set_brush(brush)


func set_load_texture_dialog(dialog):
	_texture_editor.set_load_texture_dialog(dialog)


func _on_TextureEditor_texture_selected(index):
	emit_signal("texture_selected", index)


func _on_DetailEditor_detail_selected(index):
	emit_signal("detail_selected", index)


func set_brush_editor_display_mode(mode):
	_brush_editor.set_display_mode(mode)


func set_detail_layer_index(index):
	_detail_editor.set_layer_index(index)


func _on_DetailEditor_detail_list_changed():
	emit_signal("detail_list_changed")
