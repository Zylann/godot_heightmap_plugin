
const NATIVE_PATH = "res://addons/zylann.hterrain/native/"

const ImageUtilsGeneric = preload("./image_utils_generic.gd")


static func is_native_available() -> bool:
	var os = OS.get_name()
	return false#os == "Windows"


static func get_image_utils():
	if is_native_available():
		var ImageUtilsNative = load(NATIVE_PATH + "image_utils.gdns")
		return ImageUtilsNative.new()
	else:
		return ImageUtilsGeneric

