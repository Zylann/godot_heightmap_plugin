@tool
extends AcceptDialog

const HT_Util = preload("../../util/util.gd")
const HTerrain = preload("../../hterrain.gd")
const HTerrainData = preload("../../hterrain_data.gd")
const HT_Errors = preload("../../util/errors.gd")
const HT_Logger = preload("../../util/logger.gd")
const HT_XYZFormat = preload("../../util/xyz_format.gd")
const HT_Inspector = preload("../inspector/inspector.gd")

signal permanent_change_performed(message)

@onready var _inspector : HT_Inspector = $VBoxContainer/Inspector
@onready var _errors_label : Label = $VBoxContainer/ColorRect/ScrollContainer/VBoxContainer/Errors
@onready var _warnings_label : Label = \
	$VBoxContainer/ColorRect/ScrollContainer/VBoxContainer/Warnings


enum {
	RAW_LITTLE_ENDIAN,
	RAW_BIG_ENDIAN
}

var _terrain : HTerrain = null
var _logger = HT_Logger.get_for(self)


func _init():
	get_ok_button().hide()


func _ready():
	_inspector.set_prototype({
		"heightmap": {
			"type": TYPE_STRING,
			"usage": "file",
			"exts": ["raw", "png", "exr", "xyz"]
		},
		"raw_endianess": {
			"type": TYPE_INT,
			"usage": "enum",
			"enum_items": [[RAW_LITTLE_ENDIAN, "Little Endian"], [RAW_BIG_ENDIAN, "Big Endian"]],
			"enabled": false
		},
		"bit_depth": {
			"type": TYPE_INT,
			"usage": "enum",
			"enum_items": [[HTerrainData.BIT_DEPTH_16, "16-bit"], [HTerrainData.BIT_DEPTH_32, "32-bit"]],
			"enabled": false
		},
		"min_height": {
			"type": TYPE_FLOAT,
			"range": {"min": -2000.0, "max": 2000.0, "step": 0.01},
			"default_value": 0.0
		},
		"max_height": {
			"type": TYPE_FLOAT,
			"range": {"min": -2000.0, "max": 2000.0, "step": 0.01},
			"default_value": 400.0
		},
		"splatmap": {
			"type": TYPE_STRING,
			"usage": "file",
			"exts": ["png"]
		},
		"colormap": {
			"type": TYPE_STRING,
			"usage": "file",
			"exts": ["png"]
		}
	})

	# Testing
#	_errors_label.text = "- Hello World!"
#	_warnings_label.text = "- Yolo Jesus!"


func set_terrain(terrain: HTerrain):
	_terrain = terrain


func _notification(what: int):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		# Checking a node set in _ready,
		# because visibility can also change between _enter_tree and _ready...
		if visible and _inspector != null:
			_clear_feedback()


static func _format_feedbacks(feed):
	var a := []
	for s in feed:
		a.append("- " + s)
	return "\n".join(PackedStringArray(a))


func _clear_feedback():
	_errors_label.text = ""
	_warnings_label.text = ""


class HT_ErrorCheckReport:
	var errors := []
	var warnings := []


func _show_feedback(res: HT_ErrorCheckReport):
	for e in res.errors:
		_logger.error(e)

	for w in res.warnings:
		_logger.warn(w)
	
	_clear_feedback()
	
	if len(res.errors) > 0:
		_errors_label.text = _format_feedbacks(res.errors)

	if len(res.warnings) > 0:
		_warnings_label.text = _format_feedbacks(res.warnings)


func _on_CheckButton_pressed():
	var res := _validate_form()
	_show_feedback(res)


func _on_ImportButton_pressed():
	assert(_terrain != null and _terrain.get_data() != null)

	# Verify input to inform the user of potential issues
	var res := _validate_form()
	_show_feedback(res)

	if len(res.errors) != 0:
		_logger.debug("Cannot import due to errors, aborting")
		return

	var params := {}

	var heightmap_path = _inspector.get_value("heightmap")
	if heightmap_path != "":
		var endianess = _inspector.get_value("raw_endianess")
		params[HTerrainData.CHANNEL_HEIGHT] = {
			"path": heightmap_path,
			"min_height": _inspector.get_value("min_height"),
			"max_height": _inspector.get_value("max_height"),
			"big_endian": endianess == RAW_BIG_ENDIAN,
			"bit_depth": _inspector.get_value("bit_depth"),
		}

	var colormap_path = _inspector.get_value("colormap")
	if colormap_path != "":
		params[HTerrainData.CHANNEL_COLOR] = {
			"path": colormap_path
		}

	var splatmap_path = _inspector.get_value("splatmap")
	if splatmap_path != "":
		params[HTerrainData.CHANNEL_SPLAT] = {
			"path": splatmap_path
		}

	var data = _terrain.get_data()
	data._edit_import_maps(params)
	emit_signal("permanent_change_performed", "Import maps")
	
	_logger.debug("Terrain import finished")
	hide()


func _on_CancelButton_pressed():
	hide()


func _on_Inspector_property_changed(key: String, value):
	if key == "heightmap":
		var is_raw = value.get_extension().to_lower() == "raw"
		_inspector.set_property_enabled("raw_endianess", is_raw)
		_inspector.set_property_enabled("bit_depth", is_raw)
		if is_raw:
			var bit_depth:int = _estimate_bit_depth_for_raw_file(value)
			if bit_depth == HTerrainData.BIT_DEPTH_UNDEFINED:
				bit_depth = HTerrainData.BIT_DEPTH_16 # fallback depth value
			_inspector.set_value("bit_depth", bit_depth)


# _estimate_bit_depth_for_raw_file returns the file's identified bit depth, or 0.
static func _estimate_bit_depth_for_raw_file(path: String) -> int:
	var ext := path.get_extension().to_lower()
	if ext == "raw":
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			return HTerrainData.BIT_DEPTH_UNDEFINED

		var file_len := f.get_length()
		f = null # close file

		for bit_depth in [HTerrainData.BIT_DEPTH_16, HTerrainData.BIT_DEPTH_32]:
			var file_res := HT_Util.integer_square_root(file_len / (bit_depth/8))
			if file_res > 0:
				return bit_depth

	return HTerrainData.BIT_DEPTH_UNDEFINED


func _validate_form() -> HT_ErrorCheckReport:
	var res := HT_ErrorCheckReport.new()

	var heightmap_path : String = _inspector.get_value("heightmap")
	var splatmap_path : String = _inspector.get_value("splatmap")
	var colormap_path : String = _inspector.get_value("colormap")
	var bit_depth = _inspector.get_value("bit_depth")

	if colormap_path == "" and heightmap_path == "" and splatmap_path == "":
		res.errors.append("No maps specified.")
		return res

	# If a heightmap is specified, it will override the size of the existing terrain.
	# If not specified, maps will have to match the resolution of the existing terrain.
	var heightmap_size := _terrain.get_data().get_resolution()

	if heightmap_path != "":
		var min_height = _inspector.get_value("min_height")
		var max_height = _inspector.get_value("max_height")

		if min_height >= max_height:
			res.errors.append("Minimum height must be lower than maximum height")
			# Returning early because min and max can be slided,
			# so we avoid loading other maps every time to do further checks.
			return res

		var image_size_result = _load_image_size(heightmap_path, _logger, bit_depth)
		if image_size_result.error_code != OK:
			res.errors.append(str("Cannot open heightmap file: ", image_size_result.to_string()))
			return res

		var adjusted_size = HTerrainData.get_adjusted_map_size(
			image_size_result.width, image_size_result.height)

		if adjusted_size != image_size_result.width:
			res.warnings.append(
				"The square resolution deduced from heightmap file size is not power of two + 1.\n" + \
				"The heightmap will be cropped.")

		heightmap_size = adjusted_size

	if splatmap_path != "":
		_check_map_size(splatmap_path, "splatmap", heightmap_size, bit_depth, res, _logger)

	if colormap_path != "":
		_check_map_size(colormap_path, "colormap", heightmap_size, bit_depth, res, _logger)

	return res


static func _check_map_size(path: String, map_name: String, heightmap_size: int, bit_depth: int, 
	res: HT_ErrorCheckReport, logger):
	
	var size_result := _load_image_size(path, logger, bit_depth)
	if size_result.error_code != OK:
		res.errors.append(str("Cannot open splatmap file: ", size_result.to_string()))
		return
	var adjusted_size := HTerrainData.get_adjusted_map_size(size_result.width, size_result.height)
	if adjusted_size != heightmap_size:
		res.errors.append(str(
			"The ", map_name, 
			" must have the same resolution as the heightmap (", heightmap_size, ")"))
	else:
		if adjusted_size != size_result.width:
			res.warnings.append(str(
				"The square resolution deduced from ", map_name, 
				" file size is not power of two + 1.\nThe ", 
				map_name, " will be cropped."))


class HT_ImageSizeResult:
	var width := 0
	var height := 0
	var error_code := OK
	var error_message := ""
	
	func to_string() -> String:
		if error_message != "":
			return error_message
		return HT_Errors.get_message(error_code)


static func _load_image_size(path: String, logger, bit_depth: int) -> HT_ImageSizeResult:
	var ext := path.get_extension().to_lower()
	var result := HT_ImageSizeResult.new()

	if ext == "png" or ext == "exr":
		# Godot can load these formats natively
		var im := Image.new()
		var err := im.load(path)
		if err != OK:
			logger.error("An error occurred loading image '{0}', code {1}".format([path, err]))
			result.error_code = err
			return result
		
		result.width = im.get_width()
		result.height = im.get_height()
		return result

	elif ext == "raw":
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			var err := FileAccess.get_open_error()
			logger.error("Error opening file {0}".format([path]))
			result.error_code = err
			return result

		# Assume the raw data is square, so its size is function of file length
		var flen := f.get_length()
		f = null
		var size_px = HT_Util.integer_square_root(flen / (bit_depth/8))
		if size_px == -1:
			result.error_code = ERR_INVALID_DATA
			result.error_message = "RAW image is not square or your bit depth choice is incorrect…"
			return result
		
		logger.debug("Deduced RAW heightmap resolution: {0}*{1}, for a length of {2}" \
			.format([size_px, size_px, flen]))

		result.width = size_px
		result.height = size_px
		return result

	elif ext == "xyz":
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			var err := FileAccess.get_open_error()
			logger.error("Error opening file {0}".format([path]))
			result.error_code = err
			return result

		var bounds := HT_XYZFormat.load_bounds(f)

		result.width = bounds.image_width
		result.height = bounds.image_height
		return result

	else:
		result.error_code = ERR_FILE_UNRECOGNIZED
		return result
