
const NATIVE_PATH = "res://addons/zylann.hterrain/native/"

const HT_ImageUtilsGeneric = preload("./image_utils_generic.gd")
const HT_QuadTreeLodGeneric = preload("./quad_tree_lod_generic.gd")

# See https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-get-name
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
	return v.major == 3 and v.minor >= 2 and v.minor <= 5


static func get_image_utils():
	if is_native_available():
		var HT_ImageUtilsNative = load(NATIVE_PATH + "image_utils.gdns")
		if HT_ImageUtilsNative != null:
			return HT_ImageUtilsNative.new()
	return HT_ImageUtilsGeneric.new()


static func get_quad_tree_lod():
	if is_native_available():
		var HT_QuadTreeLod = load(NATIVE_PATH + "quad_tree_lod.gdns")
		if HT_QuadTreeLod != null:
			return HT_QuadTreeLod.new()
	return HT_QuadTreeLodGeneric.new()
