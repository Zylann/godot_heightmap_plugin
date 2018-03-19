tool
extends Control


onready var _minimap = get_node("HSplitContainer/HSplitContainer/Minimap")
onready var _brush_editor = get_node("HSplitContainer/BrushEditor")
onready var _texture_editor = get_node("HSplitContainer/HSplitContainer/TextureEditor")


func set_terrain(terrain):
	_minimap.set_terrain(terrain)
	_texture_editor.set_terrain(terrain)


func set_brush(brush):
	_brush_editor.set_brush(brush)
	_texture_editor.set_brush(brush)


func set_load_texture_dialog(dialog):
	_texture_editor.set_load_texture_dialog(dialog)


