tool
extends CustomResourceLoader


const HTerrainData = preload("hterrain_data.gd")


func get_recognized_extensions():
	return PoolStringArray(["hterrain"])


func get_resource_type(path):
	var ext = path.get_extension().to_lower()
	if ext == "hterrain":
		return "Resource"
	return ""


func handles_type(typename):
	return typename == "Resource"


func load(path, original_path):
	var res = HTerrainData.new()
	res.load_data(path.get_base_dir())
	return res

