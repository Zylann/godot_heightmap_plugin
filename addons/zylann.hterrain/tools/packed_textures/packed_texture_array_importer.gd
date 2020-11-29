tool
extends EditorImportPlugin

const TextureLayeredImporter = preload("./texture_layered_importer.gd")
const PackedTextureUtil = preload("./packed_texture_util.gd")
const Errors = preload("../../util/errors.gd")
const Result = preload("../util/result.gd")
const Logger = preload("../../util/logger.gd")

const IMPORTER_NAME = "hterrain_packed_texture_array_importer"
const RESOURCE_TYPE = "TextureArray"

var _logger = Logger.get_for(self)


func get_importer_name() -> String:
	return IMPORTER_NAME


func get_visible_name() -> String:
	# This shows up next to "Import As:"
	return "HTerrainPackedTextureArray"


func get_recognized_extensions() -> Array:
	return ["packed_texarr"]


func get_save_extension() -> String:
	return "texarr"


func get_resource_type() -> String:
	return RESOURCE_TYPE


func get_preset_count() -> int:
	return 1


func get_preset_name(preset_index: int) -> String:
	return ""


func get_import_options(preset_index: int) -> Array:
	return [
		{
			"name": "compress/mode",
			"default_value": TextureLayeredImporter.COMPRESS_VIDEO_RAM,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": TextureLayeredImporter.COMPRESS_HINT_STRING
		},
		{
			"name": "flags/repeat",
			"default_value": TextureLayeredImporter.REPEAT_ENABLED,
			"property_hint": PROPERTY_HINT_ENUM,
			"hint_string": TextureLayeredImporter.REPEAT_HINT_STRING
		},
		{
			"name": "flags/filter",
			"default_value": true
		},
		{
			"name": "flags/mipmaps",
			"default_value": true
		}
	]


func get_option_visibility(option: String, options: Dictionary) -> bool:
	return true


func import(p_source_path: String, p_save_path: String, options: Dictionary, 
	r_platform_variants: Array, r_gen_files: Array) -> int:

	var result := _import(p_source_path, p_save_path, options, r_platform_variants, r_gen_files)
	
	if not result.success:
		_logger.error(result.get_message())
		# TODO Show detailed error in a popup if result is negative
	
	var code : int = result.value
	return code


func _import(p_source_path: String, p_save_path: String, options: Dictionary, 
	r_platform_variants: Array, r_gen_files: Array) -> Result:
	
	var f := File.new()
	var err := f.open(p_source_path, File.READ)
	if err != OK:
		return Result.new(false, "Could not open file {0}: {1}" \
			.format([p_source_path, Errors.get_message(err)])) \
			.with_value(err)
	var text := f.get_as_text()
	f.close()
	
	var json_result := JSON.parse(text)
	if json_result.error != OK:
		return Result.new(false, "Failed to parse file {0}: {1}" \
			.format([p_source_path, json_result.error_string])) \
			.with_value(json_result.error)
	var json_data : Dictionary = json_result.result
	
	var resolution : int = int(json_data.resolution)
	var contains_albedo : bool = json_data.get("contains_albedo", false)
	var layers = json_data.get("layers")
	
	var images = []
	
	for layer_index in len(layers):
		var sources = layers[layer_index]
		var result = PackedTextureUtil.generate_image(sources, resolution, _logger)

		if not result.success:
			return Result.new(false, 
				"While importing layer {0}".format([layer_index]), result) \
				.with_value(result.value)
		
		var im : Image = result.value
		images.append(im)
	
	var result = TextureLayeredImporter.import(
		p_source_path, 
		images, 
		p_save_path, 
		r_platform_variants, 
		r_gen_files, 
		contains_albedo,
		get_visible_name(),
		options["compress/mode"],
		options["flags/repeat"],
		options["flags/filter"],
		options["flags/mipmaps"])
	
	if not result.success:
		return Result.new(false, 
			"While importing {0}".format([p_source_path]), result) \
			.with_value(result.value)
	
	return Result.new(true).with_value(OK)

