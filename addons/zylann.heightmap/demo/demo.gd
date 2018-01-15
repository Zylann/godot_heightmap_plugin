extends Node

const HeightMap2 = preload("res://addons/zylann.heightmap/height_map.gdns")


func _ready():
	var hello = HeightMap2.new()
	print(hello.get_data())

