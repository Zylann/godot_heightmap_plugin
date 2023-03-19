@tool
class_name HTerrainDataLoader
extends ResourceFormatLoader


const HTerrainData = preload("./hterrain_data.gd")


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray([HTerrainData.META_EXTENSION])


func _get_resource_type(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if ext == HTerrainData.META_EXTENSION:
		return "Resource"
	return ""


# TODO Handle UIDs?
# By default Godot will return INVALID_ID,
# which makes this resource only tracked by path, like scripts
#
# func _get_resource_uid(path: String) -> int:
# 	return ???


func _handles_type(typename: StringName) -> bool:
	return typename == &"Resource"


func _load(path: String, original_path: String, use_sub_threads: bool, cache_mode: int):
	var res = HTerrainData.new()
	res.load_data(path.get_base_dir())
	return res
