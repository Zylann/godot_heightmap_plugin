
const NATIVE_PATH = "res://addons/zylann.hterrain/native/"

const ImageUtilsGeneric = preload("./image_utils_generic.gd")

# See https://docs.godotengine.org/en/3.2/classes/class_os.html#class-os-method-get-name
const _supported_os = {
	"Windows": true,
	"X11": true,
	#"OSX": true
}


static func is_native_available() -> bool:
	var os = OS.get_name()
	if not _supported_os.has(os):
		return false
	# API changes can cause binary incompatibility
	var v = Engine.get_version_info()
	return v.major == 3 and v.minor == 2


static func get_image_utils():
	if is_native_available():
		var ImageUtilsNative = load(NATIVE_PATH + "image_utils.gdns")
		if ImageUtilsNative != null:
			return ImageUtilsNative.new()
	return ImageUtilsGeneric.new()

