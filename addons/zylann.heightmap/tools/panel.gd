tool
extends Control


onready var _minimap = get_node("HSplitContainer/HSplitContainer/Minimap")


func set_terrain(terrain):
	_minimap.set_terrain(terrain)

