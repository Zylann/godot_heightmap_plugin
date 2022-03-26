tool

# TODO Godot does not have an API to make custom texture importers easier.
# So we have to re-implement the entire logic of `ResourceImporterTexture`.
# See https://github.com/godotengine/godot/issues/24381

const HT_Result = preload("../util/result.gd")
const HT_Errors = preload("../../util/errors.gd")
const HT_Util = preload("../../util/util.gd")

const COMPRESS_LOSSLESS = 0
const COMPRESS_LOSSY = 1
const COMPRESS_VIDEO_RAM = 2
const COMPRESS_UNCOMPRESSED = 3

const COMPRESS_HINT_STRING = "Lossless,Lossy,VRAM,Uncompressed"

const REPEAT_NONE = 0
const REPEAT_ENABLED = 1
const REPEAT_MIRRORED = 2

const REPEAT_HINT_STRING = "None,Enabled,Mirrored"

# StreamTexture.FormatBits, not exposed to GDScript
const StreamTexture_FORMAT_MASK_IMAGE_FORMAT = (1 << 20) - 1
const StreamTexture_FORMAT_BIT_LOSSLESS = 1 << 20
const StreamTexture_FORMAT_BIT_LOSSY = 1 << 21
const StreamTexture_FORMAT_BIT_STREAM = 1 << 22
const StreamTexture_FORMAT_BIT_HAS_MIPMAPS = 1 << 23
const StreamTexture_FORMAT_BIT_DETECT_3D = 1 << 24
const StreamTexture_FORMAT_BIT_DETECT_SRGB = 1 << 25
const StreamTexture_FORMAT_BIT_DETECT_NORMAL = 1 << 26


static func import(
	p_source_path: String, 
	image: Image, 
	p_save_path: String,
	r_platform_variants: Array, 
	r_gen_files: Array, 
	p_contains_albedo: bool,
	importer_name: String,
	p_compress_mode: int,
	p_repeat: int,
	p_filter: bool,
	p_mipmaps: bool,
	p_anisotropic: bool) -> HT_Result:

	var compress_mode := p_compress_mode
	var lossy := 0.7
	var repeat := p_repeat
	var filter := p_filter
	var mipmaps := p_mipmaps
	var anisotropic := p_anisotropic
	var srgb := 1 if p_contains_albedo else 2
	var fix_alpha_border := false
	var premult_alpha := false
	var invert_color := false
	var stream := false
	var size_limit := 0
	var hdr_as_srgb := false
	var normal := 0
	var scale := 1.0
	var force_rgbe := false
	var bptc_ldr := 0
	var detect_3d := false

	var formats_imported := []

	var tex_flags := 0
	if repeat > 0:
		tex_flags |= Texture.FLAG_REPEAT
	if repeat == 2:
		tex_flags |= Texture.FLAG_MIRRORED_REPEAT
	if filter:
		tex_flags |= Texture.FLAG_FILTER
	if mipmaps or compress_mode == COMPRESS_VIDEO_RAM:
		tex_flags |= Texture.FLAG_MIPMAPS
	if anisotropic:
		tex_flags |= Texture.FLAG_ANISOTROPIC_FILTER
	if srgb == 1:
		tex_flags |= Texture.FLAG_CONVERT_TO_LINEAR

	if size_limit > 0 and (image.get_width() > size_limit or image.get_height() > size_limit):
		#limit size
		if image.get_width() >= image.get_height():
			var new_width := size_limit
			var new_height := image.get_height() * new_width / image.get_width()

			image.resize(new_width, new_height, Image.INTERPOLATE_CUBIC)
			
		else:
			var new_height := size_limit
			var new_width := image.get_width() * new_height / image.get_height()

			image.resize(new_width, new_height, Image.INTERPOLATE_CUBIC)

		if normal == 1:
			image.normalize()

	if fix_alpha_border:
		image.fix_alpha_edges()

	if premult_alpha:
		image.premultiply_alpha()

	if invert_color:
		var height = image.get_height()
		var width = image.get_width()

		image.lock()
		for i in width:
			for j in height:
				image.set_pixel(i, j, image.get_pixel(i, j).inverted())

		image.unlock()

	var detect_srgb := srgb == 2
	var detect_normal := normal == 0
	var force_normal := normal == 1

	if compress_mode == COMPRESS_VIDEO_RAM:
		#must import in all formats, 
		#in order of priority (so platform choses the best supported one. IE, etc2 over etc).
		#Android, GLES 2.x

		var ok_on_pc := false
		var is_hdr := \
			(image.get_format() >= Image.FORMAT_RF and image.get_format() <= Image.FORMAT_RGBE9995)
		var is_ldr := \
			(image.get_format() >= Image.FORMAT_L8 and image.get_format() <= Image.FORMAT_RGBA5551)
		var can_bptc : bool = ProjectSettings.get("rendering/vram_compression/import_bptc")
		var can_s3tc : bool = ProjectSettings.get("rendering/vram_compression/import_s3tc")

		if can_bptc:
#			return Result.new(false, "{0} cannot handle BPTC compression on {1}, " +
#				"because the required logic is not exposed to the script API. " +
#				"If you don't aim to export for a platform requiring BPTC, " +
#				"you can turn it off in your ProjectSettings." \
#				.format([importer_name, p_source_path])) \
#				.with_value(ERR_UNAVAILABLE)

			# Can't do this optimization because not exposed to GDScript				
#			var channels = image.get_detected_channels()
#			if is_hdr:
#				if channels == Image.DETECTED_LA or channels == Image.DETECTED_RGBA:
#					can_bptc = false
#			elif is_ldr:
#				#handle "RGBA Only" setting
#				if bptc_ldr == 1 and channels != Image.DETECTED_LA \
#				and channels != Image.DETECTED_RGBA:
#					can_bptc = false
#
			formats_imported.push_back("bptc")

		if not can_bptc and is_hdr and not force_rgbe:
			#convert to ldr if this can't be stored hdr
			image.convert(Image.FORMAT_RGBA8)

		if can_bptc or can_s3tc:
			_save_stex(
				image, 
				p_save_path + ".s3tc.stex", 
				compress_mode, 
				lossy, 
				Image.COMPRESS_BPTC if can_bptc else Image.COMPRESS_S3TC, 
				mipmaps, 
				tex_flags, 
				stream, 
				detect_3d, 
				detect_srgb, 
				force_rgbe, 
				detect_normal, 
				force_normal, 
				false)
			r_platform_variants.push_back("s3tc")
			formats_imported.push_back("s3tc")
			ok_on_pc = true

		if ProjectSettings.get("rendering/vram_compression/import_etc2"):
			_save_stex(
				image,
				p_save_path + ".etc2.stex",
				compress_mode,
				lossy,
				Image.COMPRESS_ETC2,
				mipmaps,
				tex_flags,
				stream,
				detect_3d,
				detect_srgb,
				force_rgbe,
				detect_normal,
				force_normal,
				true)
			r_platform_variants.push_back("etc2")
			formats_imported.push_back("etc2")

		if ProjectSettings.get("rendering/vram_compression/import_etc"):
			_save_stex(
				image,
				p_save_path + ".etc.stex",
				compress_mode,
				lossy,
				Image.COMPRESS_ETC,
				mipmaps,
				tex_flags,
				stream,
				detect_3d,
				detect_srgb,
				force_rgbe,
				detect_normal,
				force_normal,
				true)
			r_platform_variants.push_back("etc")
			formats_imported.push_back("etc")

		if ProjectSettings.get("rendering/vram_compression/import_pvrtc"):
			_save_stex(
				image,
				p_save_path + ".pvrtc.stex",
				compress_mode,
				lossy,
				Image.COMPRESS_PVRTC4,
				mipmaps,
				tex_flags,
				stream,
				detect_3d,
				detect_srgb,
				force_rgbe,
				detect_normal,
				force_normal,
				true)
			r_platform_variants.push_back("pvrtc")
			formats_imported.push_back("pvrtc")

		if not ok_on_pc:
			# TODO This warning is normally printed by `EditorNode::add_io_error`,
			# which doesn't seem to be exposed to the script API
			return HT_Result.new(false, 
				"No suitable PC VRAM compression enabled in Project Settings. " +
				"The texture {0} will not display correctly on PC.".format([p_source_path])) \
				.with_value(ERR_INVALID_PARAMETER)
	
	else:
		#import normally
		_save_stex(
			image,
			p_save_path + ".stex",
			compress_mode,
			lossy, 
			Image.COMPRESS_S3TC, #this is ignored,
			mipmaps,
			tex_flags,
			stream,
			detect_3d,
			detect_srgb,
			force_rgbe,
			detect_normal,
			force_normal,
			false)
	
	# TODO I have no idea what this part means, but it's not exposed to the script API either.
#	if (r_metadata) {
#		Dictionary metadata;
#		metadata["vram_texture"] = compress_mode == COMPRESS_VIDEO_RAM;
#		if (formats_imported.size()) {
#			metadata["imported_formats"] = formats_imported;
#		}
#		*r_metadata = metadata;
#	}

	return HT_Result.new(true).with_value(OK)


static func _save_stex(
	p_image: Image, 
	p_fpath: String, 
	p_compress_mode: int, # ResourceImporterTexture.CompressMode
	p_lossy_quality: float,
	p_vram_compression: int, # Image.CompressMode
	p_mipmaps: bool, 
	p_texture_flags: int,
	p_streamable: bool, 
	p_detect_3d: bool,
	p_detect_srgb: bool,
	p_force_rgbe: bool, 
	p_detect_normal: bool,
	p_force_normal: bool,
	p_force_po2_for_compressed: bool
	) -> HT_Result:

	# Need to work on a copy because we will modify it,
	# but the calling code may have to call this function multiple times
	p_image = p_image.duplicate()
	
	var f = File.new()
	var err = f.open(p_fpath, File.WRITE)
	if err != OK:
		return HT_Result.new(false, "Could not open file {0}:\n{1}" \
			.format([p_fpath, HT_Errors.get_message(err)]))

	f.store_8(ord('G'))
	f.store_8(ord('D'))
	f.store_8(ord('S'))
	f.store_8(ord('T')) # godot streamable texture

	var resize_to_po2 := false
	
	if p_compress_mode == COMPRESS_VIDEO_RAM and p_force_po2_for_compressed \
	and (p_mipmaps or p_texture_flags & Texture.FLAG_REPEAT):
		resize_to_po2 = true
		f.store_16(HT_Util.next_power_of_two(p_image.get_width()))
		f.store_16(p_image.get_width())
		f.store_16(HT_Util.next_power_of_two(p_image.get_height()))
		f.store_16(p_image.get_height())
	else:
		f.store_16(p_image.get_width())
		f.store_16(0)
		f.store_16(p_image.get_height())
		f.store_16(0)
	
	f.store_32(p_texture_flags)

	var format := 0

	if p_streamable:
		format |= StreamTexture_FORMAT_BIT_STREAM
	if p_mipmaps:
		format |= StreamTexture_FORMAT_BIT_HAS_MIPMAPS # mipmaps bit
	if p_detect_3d:
		format |= StreamTexture_FORMAT_BIT_DETECT_3D
	if p_detect_srgb:
		format |= StreamTexture_FORMAT_BIT_DETECT_SRGB
	if p_detect_normal:
		format |= StreamTexture_FORMAT_BIT_DETECT_NORMAL

	if (p_compress_mode == COMPRESS_LOSSLESS or p_compress_mode == COMPRESS_LOSSY) \
	and p_image.get_format() > Image.FORMAT_RGBA8:
		p_compress_mode = COMPRESS_UNCOMPRESSED # these can't go as lossy

	match p_compress_mode:
		COMPRESS_LOSSLESS:
			# Not required for our use case
#			var image : Image = p_image.duplicate()
#			if p_mipmaps:
#				image.generate_mipmaps()
#			else:
#				image.clear_mipmaps()
			var image := p_image
			
			var mmc := _get_required_mipmap_count(image)

			format |= StreamTexture_FORMAT_BIT_LOSSLESS
			f.store_32(format)
			f.store_32(mmc)

			for i in mmc:
				if i > 0:
					image.shrink_x2()
				#var data = Image::lossless_packer(image);
				# This is actually PNG...
				var data = image.save_png_to_buffer()
				f.store_32(data.size() + 4)
				f.store_8(ord('P'))
				f.store_8(ord('N'))
				f.store_8(ord('G'))
				f.store_8(ord(' '))
				f.store_buffer(data)

		COMPRESS_LOSSY:
			return HT_Result.new(false,
				"Saving a StreamTexture with lossy compression cannot be achieved by scripts.\n"
				+ "Godot would need to either allow to save an image as WEBP to a buffer,\n"
				+ "or expose `ResourceImporterTexture::_save_stex` so custom importers\n"
				+ "would be easier to make.")

		COMPRESS_VIDEO_RAM:
			var image : Image = p_image.duplicate()
			if resize_to_po2:
				image.resize_to_po2()
			
			if p_mipmaps:
				image.generate_mipmaps(p_force_normal)

			if p_force_rgbe \
			and image.get_format() >= Image.FORMAT_R8 \
			and image.get_format() <= Image.FORMAT_RGBE9995:
				image.convert(Image.FORMAT_RGBE9995)
			else:
				var csource := Image.COMPRESS_SOURCE_GENERIC
				if p_force_normal:
					csource = Image.COMPRESS_SOURCE_NORMAL
				elif p_texture_flags & VisualServer.TEXTURE_FLAG_CONVERT_TO_LINEAR:
					csource = Image.COMPRESS_SOURCE_SRGB

				image.compress(p_vram_compression, csource, p_lossy_quality)

			format |= image.get_format()

			f.store_32(format)

			var data = image.get_data();
			f.store_buffer(data)
		
		COMPRESS_UNCOMPRESSED:

			var image := p_image.duplicate()
			if p_mipmaps:
				image.generate_mipmaps()
			else:
				image.clear_mipmaps()

			format |= image.get_format()
			f.store_32(format)

			var data = image.get_data()
			f.store_buffer(data)

		_:
			return HT_Result.new(false, "Invalid compress mode specified: {0}" \
				.format([p_compress_mode]))
	
	return HT_Result.new(true)


# TODO Godot doesn't expose `Image.get_mipmap_count()`
# And the implementation involves shittons of unexposed code,
# so we have to fallback on a simplified version
static func _get_required_mipmap_count(image: Image) -> int:
	var dim := max(image.get_width(), image.get_height())
	return int(log(dim) / log(2) + 1)


