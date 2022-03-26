tool

# TODO Godot does not have an API to make custom texture importers easier.
# So we have to re-implement the entire logic of `ResourceImporterLayeredTexture`.
# See https://github.com/godotengine/godot/issues/24381

const HT_Result = preload("../util/result.gd")
const HT_Errors = preload("../../util/errors.gd")
const HT_Util = preload("../../util/util.gd")

const COMPRESS_LOSSLESS = 0
const COMPRESS_VIDEO_RAM = 1
const COMPRESS_UNCOMPRESSED = 2
# For some reason lossy TextureArrays are not implemented in Godot -_-

const COMPRESS_HINT_STRING = "Lossless,VRAM,Uncompressed"

const REPEAT_NONE = 0
const REPEAT_ENABLED = 1
const REPEAT_MIRRORED = 2

const REPEAT_HINT_STRING = "None,Enabled,Mirrored"

# TODO COMPRESS_SOURCE_LAYERED is not exposed 
# https://github.com/godotengine/godot/issues/43387
const Image_COMPRESS_SOURCE_LAYERED = 3


static func import(
	p_source_path: String,
	p_images: Array,
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
	var no_bptc_if_rgb := false#p_options["compress/no_bptc_if_rgb"];
	var repeat := p_repeat
	var filter := p_filter
	var mipmaps := p_mipmaps
	var srgb := 1 if p_contains_albedo else 2#p_options["flags/srgb"];
#	int hslices = p_options["slices/horizontal"];
#	int vslices = p_options["slices/vertical"];

	var tex_flags := 0
	if repeat > 0:
		tex_flags |= Texture.FLAG_REPEAT
	if repeat == 2:
		tex_flags |= Texture.FLAG_MIRRORED_REPEAT
	if filter:
		tex_flags |= Texture.FLAG_FILTER
	if mipmaps or compress_mode == COMPRESS_VIDEO_RAM:
		tex_flags |= Texture.FLAG_MIPMAPS
	if srgb == 1:
		tex_flags |= Texture.FLAG_CONVERT_TO_LINEAR
	if p_anisotropic:
		tex_flags |= Texture.FLAG_ANISOTROPIC_FILTER

#	Vector<Ref<Image> > slices;
#
#	int slice_w = image->get_width() / hslices;
#	int slice_h = image->get_height() / vslices;

	# Can't do any of this in our case...
	#optimize
#	if compress_mode == COMPRESS_VIDEO_RAM:
		#if using video ram, optimize
#		if srgb:
			#remove alpha if not needed, so compression is more efficient
#			if image.get_format() == Image.FORMAT_RGBA8 and !image.detect_alpha():
#				image.convert(Image.FORMAT_RGB8)
			
#		else:
#			pass
			# Not exposed to GDScript...
			#image.optimize_channels()

	var extension := "texarr"
	var formats_imported := []

	if compress_mode == COMPRESS_VIDEO_RAM:
		#must import in all formats,
		#in order of priority (so platform choses the best supported one. IE, etc2 over etc).
		#Android, GLES 2.x

		var ok_on_pc := false
		var encode_bptc := false

		if ProjectSettings.get("rendering/vram_compression/import_bptc"):
#			return Result.new(false, "{0} cannot handle BPTC compression on {1}, " +
#				"because the required logic is not exposed to the script API. " +
#				"If you don't aim to export for a platform requiring BPTC, " +
#				"you can turn it off in your ProjectSettings." \
#				.format([importer_name, p_source_path])) \
#				.with_value(ERR_UNAVAILABLE)
			
			# Can't do this optimization because not exposed to GDScript
#			var encode_bptc := true
#			if no_bptc_if_rgb:
#				var channels := image.get_detected_channels()
#				if channels != Image.DETECTED_LA and channels != Image.DETECTED_RGBA:
#					encode_bptc = false

			formats_imported.push_back("bptc");

		if encode_bptc:
			var result = _save_tex(
				p_images, 
				p_save_path + ".bptc." + extension, 
				compress_mode, 
				Image.COMPRESS_BPTC, 
				mipmaps, 
				tex_flags)

			if not result.success:
				return result
				
			r_platform_variants.push_back("bptc")
			ok_on_pc = true

		if ProjectSettings.get("rendering/vram_compression/import_s3tc"):
			var result = _save_tex(
				p_images, 
				p_save_path + ".s3tc." + extension, 
				compress_mode, 
				Image.COMPRESS_S3TC, 
				mipmaps, 
				tex_flags)

			if not result.success:
				return result
				
			r_platform_variants.push_back("s3tc")
			ok_on_pc = true
			formats_imported.push_back("s3tc")

		if ProjectSettings.get("rendering/vram_compression/import_etc2"):
			var result = _save_tex(
				p_images, 
				p_save_path + ".etc2." + extension, 
				compress_mode, 
				Image.COMPRESS_ETC2, 
				mipmaps, 
				tex_flags)

			if not result.success:
				return result

			r_platform_variants.push_back("etc2")
			formats_imported.push_back("etc2")

		if ProjectSettings.get("rendering/vram_compression/import_etc"):
			var result = _save_tex(
				p_images, 
				p_save_path + ".etc." + extension, 
				compress_mode, 
				Image.COMPRESS_ETC,
				mipmaps, 
				tex_flags)

			if not result.success:
				return result

			r_platform_variants.push_back("etc")
			formats_imported.push_back("etc")

		if ProjectSettings.get("rendering/vram_compression/import_pvrtc"):
			var result = _save_tex(
				p_images, 
				p_save_path + ".pvrtc." + extension, 
				compress_mode, 
				Image.COMPRESS_PVRTC4, 
				mipmaps, 
				tex_flags)

			if not result.success:
				return result

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
		var result = _save_tex(
			p_images, 
			p_save_path + "." + extension, 
			compress_mode, 
			Image.COMPRESS_S3TC, #this is ignored 
			mipmaps, 
			tex_flags)

		if not result.success:
			return result

#	if (r_metadata) {
#		Dictionary metadata;
#		metadata["vram_texture"] = compress_mode == COMPRESS_VIDEO_RAM;
#		if (formats_imported.size()) {
#			metadata["imported_formats"] = formats_imported;
#		}
#		*r_metadata = metadata;
#	}

	return HT_Result.new(true).with_value(OK)


# The input image can be modified
static func _save_tex(
	p_images: Array, 
	p_to_path: String, 
	p_compress_mode: int,
	p_vram_compression: int, # Image.CompressMode
	p_mipmaps: bool,
	p_texture_flags: int
	) -> HT_Result:
		
	# We only do TextureArrays for now
	var is_3d = false
		
	var f := File.new()
	var err := f.open(p_to_path, File.WRITE)
	f.store_8(ord('G'))
	f.store_8(ord('D'))
	if is_3d:
		f.store_8(ord('3'))
	else:
		f.store_8(ord('A'))
	f.store_8(ord('T')) # godot streamable texture
	
	var slice_count := len(p_images)

	f.store_32(p_images[0].get_width())
	f.store_32(p_images[0].get_height())
	f.store_32(slice_count) # depth
	f.store_32(p_texture_flags)
	var image_format : int = p_images[0].get_format()
	var image_size : Vector2 = p_images[0].get_size()
	if p_compress_mode != COMPRESS_VIDEO_RAM:
		# vram needs to do a first compression to tell what the format is, for the rest its ok
		f.store_32(image_format)
		f.store_32(p_compress_mode) # 0 - lossless (PNG), 1 - vram, 2 - uncompressed

	if (p_compress_mode == COMPRESS_LOSSLESS) and image_format > Image.FORMAT_RGBA8:
		p_compress_mode = COMPRESS_UNCOMPRESSED # these can't go as lossy

	for i in slice_count:
		var image : Image = p_images[i]
		
		if image.get_format() != image_format:
			return HT_Result.new(false, "Layer {0} has different format, got {1}, expected {2}" \
				.format([i, image.get_format(), image_format])).with_value(ERR_INVALID_DATA)
		
		if image.get_size() != image_size:
			return HT_Result.new(false, "Layer {0} has different size, got {1}, expected {2}" \
				.format([i, image.get_size(), image_size])).with_value(ERR_INVALID_DATA)

		# We need to operate on a copy,
		# because the calling code can invoke the function multiple times
		image = image.duplicate()

		match p_compress_mode:
			COMPRESS_LOSSLESS:
				# We save each mip as PNG so we dont need to do that.
				# The engine code does it anyways :shrug: (see below why...)
#				var image = p_images[i].duplicate()
#				if p_mipmaps:
#					image.generate_mipmaps()
#				else:
#					image.clear_mipmaps()

				var mmc := _get_required_mipmap_count(image)
				f.store_32(mmc)

				for j in mmc:
					if j > 0:
						# TODO This function does something fishy behind the scenes:
						# It assumes mipmaps are downscaled versions of the image.
						# This is not necessarily true.
						# See https://www.kotaku.com.au/2018/03/
						# how-nintendo-did-the-water-effects-in-super-mario-sunshine/
						image.shrink_x2()

					#var data = Image::lossless_packer(image);
					var data = image.save_png_to_buffer()
					f.store_32(data.size() + 4)
					f.store_8(ord('P'))
					f.store_8(ord('N'))
					f.store_8(ord('G'))
					f.store_8(ord(' '))
					f.store_buffer(data)

			COMPRESS_VIDEO_RAM:
#				var image : Image = p_images[i]->duplicate();
				image.generate_mipmaps(false)

				var csource := Image_COMPRESS_SOURCE_LAYERED
				image.compress(p_vram_compression, csource, 0.7)

				if i == 0:
					#hack so we can properly tell the format
					f.store_32(image.get_format())
					f.store_32(p_compress_mode); # 0 - lossless (PNG), 1 - vram, 2 - uncompressed

				var data := image.get_data()
				f.store_buffer(data)
			
			COMPRESS_UNCOMPRESSED:
#				Ref<Image> image = p_images[i]->duplicate();

				if p_mipmaps:
					image.generate_mipmaps()
				else:
					image.clear_mipmaps()

				var data := image.get_data()
				f.store_buffer(data)
	
	return HT_Result.new(true)


# TODO Godot doesn't expose `Image.get_mipmap_count()`
# And the implementation involves shittons of unexposed code,
# so we have to fallback on a simplified version
static func _get_required_mipmap_count(image: Image) -> int:
	var dim := max(image.get_width(), image.get_height())
	return int(log(dim) / log(2) + 1)
