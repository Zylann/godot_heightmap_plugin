@tool
class_name HTerrainDataSaver
extends ResourceFormatSaver


const HTerrainData = preload("./hterrain_data.gd")


func _get_recognized_extensions(res: Resource) -> PackedStringArray:
	if res != null and res is HTerrainData:
		return PackedStringArray([HTerrainData.META_EXTENSION])
	return PackedStringArray()


func _recognize(res: Resource) -> bool:
	return res is HTerrainData


func _save(resource: Resource, path: String, flags: int) -> Error:
	if resource.save_data(path.get_base_dir()):
		return OK
	# This can occur if at least one map of the terrain fails to save.
	# It doesnt necessarily mean the entire terrain failed to save.
	return FAILED


# TODO Handle UIDs
# func _set_uid(path: String, uid: int) -> int:
# 	???
