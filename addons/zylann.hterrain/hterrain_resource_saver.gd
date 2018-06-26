tool
extends CustomResourceSaver


const HTerrainData = preload("hterrain_data.gd")


func get_recognized_extensions(res):
	if res != null and res is HTerrainData:
		return PoolStringArray(["hterrain"])
	return PoolStringArray()


func recognize(res):
	return res is HTerrainData


func save(path, resource, flags):
	resource.save_data(path.get_base_dir())

