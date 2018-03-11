tool
extends Control


onready var _minimap = get_node("HSplitContainer/HSplitContainer/Minimap")
onready var _brush_editor = get_node("HSplitContainer/BrushEditor")


func set_terrain(terrain):
	_minimap.set_terrain(terrain)


func set_brush(brush):
	_brush_editor.set_brush(brush)

