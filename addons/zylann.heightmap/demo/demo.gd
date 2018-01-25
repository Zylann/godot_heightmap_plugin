extends Node

const HeightMap2 = preload("res://addons/zylann.heightmap/height_map.gdns")
const HeightMapData2 = preload("res://addons/zylann.heightmap/height_map_data.gdns")

var _terrain = null

func _ready():
	print("---------------------------->>>")
	test()
	print("----------------------------<<<")


func test():
	_terrain = HeightMap2.new()
	add_child(_terrain)
	var data = HeightMapData2.new()
	data.set_resolution(64)
	_terrain.set_data(data)
	print(_terrain.get_data())
