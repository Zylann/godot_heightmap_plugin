
const NATIVE_PATH = "res://addons/zylann.hterrain/native/"

const ImageUtilsGeneric = preload("./image_utils_generic.gd")

const _supported_os = {
	"Windows": true
}


static func is_native_available() -> bool:
	#return false
	var os = OS.get_name()
	return _supported_os.has(os)


static func get_image_utils():
	if is_native_available():
		var ImageUtilsNative = load(NATIVE_PATH + "image_utils.gdns")
		return ImageUtilsNative.new()
	else:
		return ImageUtilsGeneric.new()

