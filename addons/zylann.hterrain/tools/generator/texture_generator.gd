# Holds a viewport on which several passes may run to generate a final image.
# Passes can have different shaders and re-use what was drawn by a previous pass.
# TODO I'd like to make such a system working as a graph of passes for more possibilities.

@tool
extends Node

const HT_Util = preload("res://addons/zylann.hterrain/util/util.gd")
const HT_TextureGeneratorPass = preload("./texture_generator_pass.gd")
const HT_Logger = preload("../../util/logger.gd")
# TODO Can't preload because it causes the plugin to fail loading if assets aren't imported
const DUMMY_TEXTURE_PATH = "res://addons/zylann.hterrain/tools/icons/empty.png"

signal progress_reported(info)
# Emitted when an output is generated.
signal output_generated(image, metadata)
# Emitted when all passes are complete
signal completed

class HT_TextureGeneratorViewport:
	var viewport : SubViewport
	var ci : TextureRect

var _passes := []
var _resolution := Vector2i(512, 512)
var _output_padding := [0, 0, 0, 0]

# Since Godot 4.0, we use ping-pong viewports because `hint_screen_texture` always returns `1.0`
# for transparent pixels, which is wrong, but sadly appears to be intented...
# https://github.com/godotengine/godot/issues/78207
var _viewports : Array[HT_TextureGeneratorViewport] = [null, null]
var _viewport_index := 0

var _dummy_texture : Texture2D
var _running := false
var _rerun := false
#var _tiles = PoolVector2Array([Vector2()])

var _running_passes := []
var _running_pass_index := 0
var _running_iteration := 0
var _shader_material : ShaderMaterial = null
#var _uv_offset = 0 # Offset de to padding

var _logger = HT_Logger.get_for(self)


func _ready():
	_dummy_texture = load(DUMMY_TEXTURE_PATH)
	if _dummy_texture == null:
		_logger.error(str("Failed to load dummy texture ", DUMMY_TEXTURE_PATH))
	
	for viewport_index in len(_viewports):
		var viewport = SubViewport.new()
		# We render with 2D shaders, but we don't want the parent world to interfere
		viewport.own_world_3d = true
		viewport.world_3d = World3D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		# Require RGBA8 so we can pack heightmap floats into pixels
		viewport.transparent_bg = true
		add_child(viewport)

		var ci := TextureRect.new()
		ci.stretch_mode = TextureRect.STRETCH_SCALE
		ci.texture = _dummy_texture
		viewport.add_child(ci)
		
		var vp := HT_TextureGeneratorViewport.new()
		vp.viewport = viewport
		vp.ci = ci
		_viewports[viewport_index] = vp
	
	_shader_material = ShaderMaterial.new()
	
	set_process(false)


func is_running() -> bool:
	return _running


func clear_passes():
	_passes.clear()


func add_pass(p: HT_TextureGeneratorPass):
	assert(_passes.find(p) == -1)
	assert(p.iterations > 0)
	_passes.append(p)


func add_output(meta):
	assert(len(_passes) > 0)
	var p = _passes[-1]
	p.output = true
	p.metadata = meta


# Sets at which base resolution the generator will work on.
# In tiled rendering, this is the resolution of one tile.
# The internal viewport may be larger if some passes need more room,
# and the resulting images might include some of these pixels if output padding is used.
func set_resolution(res: Vector2i):
	assert(not _running)
	_resolution = res


# Tell image outputs to include extra pixels on the edges.
# This extends the resolution of images compared to the base resolution.
# The initial use case for this is to generate terrain tiles where edge pixels are
# shared with the neighor tiles.
func set_output_padding(p: Array):
	assert(typeof(p) == TYPE_ARRAY)
	assert(len(p) == 4)
	for v in p:
		assert(typeof(v) == TYPE_INT)
	_output_padding = p


func run():
	assert(len(_passes) > 0)
	
	if _running:
		_rerun = true
		return
	
	for vp in _viewports:
		assert(vp.viewport != null)
		assert(vp.ci != null)
	
	# Copy passes
	var passes := []
	passes.resize(len(_passes))
	for i in len(_passes):
		passes[i] = _passes[i].duplicate()
	_running_passes = passes

	# Pad pixels according to largest padding
	var largest_padding := 0
	for p in passes:
		if p.padding > largest_padding:
			largest_padding = p.padding
	for v in _output_padding:
		if v > largest_padding:
			largest_padding = v
	var padded_size := _resolution + 2 * Vector2i(largest_padding, largest_padding)
	
#	_uv_offset = Vector2( \
#		float(largest_padding) / padded_size.x,
#		float(largest_padding) / padded_size.y)
	
	for vp in _viewports:
		vp.ci.size = padded_size
		vp.viewport.size = padded_size
	
	# First viewport index doesn't matter.
	# Maybe one issue of resetting it to zero would be that the previous run 
	# could have ended with the same viewport that will be sent as a texture as 
	# one of the uniforms of the shader material, which causes an error in the 
	# renderer because it's not allowed to use a viewport texture while 
	# rendering on the same viewport
#	_viewport_index = 0

	var first_vp := _viewports[_viewport_index]
	first_vp.viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	# I don't trust `UPDATE_ONCE`, it also doesn't reset so we never know if it actually works...
	# https://github.com/godotengine/godot/issues/33351
	first_vp.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	for vp in _viewports:
		if vp != first_vp:
			vp.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	_running_pass_index = 0
	_running_iteration = 0
	_running = true
	set_process(true)


func _process(delta: float):
	# TODO because of https://github.com/godotengine/godot/issues/7894
	if not is_processing():
		return
	
	var prev_vpi := 0 if _viewport_index == 1 else 1
	var prev_vp := _viewports[prev_vpi]
	
	if _running_pass_index > 0:
		var prev_pass : HT_TextureGeneratorPass = _running_passes[_running_pass_index - 1]
		if prev_pass.output:
			_create_output_image(prev_pass.metadata, prev_vp)
	
	if _running_pass_index >= len(_running_passes):
		_running = false
		
		completed.emit()
		
		if _rerun:
			# run() was requested again before we complete...
			# this will happen very frequently because we are forced to wait multiple frames
			# before getting a result
			_rerun = false
			run()
		else:
			# Done
			for vp in _viewports:
				vp.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			set_process(false)
			return
	
	var p : HT_TextureGeneratorPass = _running_passes[_running_pass_index]
	
	var vp := _viewports[_viewport_index]
	vp.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	prev_vp.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	
	if _running_iteration == 0:
		_setup_pass(p, vp)
	
	_setup_iteration(vp, prev_vp)
	
	_report_progress(_running_passes, _running_pass_index, _running_iteration)
	# Wait one frame for render, and this for EVERY iteration and every pass,
	# because Godot doesn't provide any way to run multiple feedback render passes in one go.
	_running_iteration += 1
	
	if _running_iteration == p.iterations:
		_running_iteration = 0
		_running_pass_index += 1
	
	# Swap viewport for next pass
	_viewport_index = (_viewport_index + 1) % 2
	
	# The viewport should render after the tree was processed


# Called at the beginning of each pass
func _setup_pass(p: HT_TextureGeneratorPass, vp: HT_TextureGeneratorViewport):
	if p.texture != null:
		vp.ci.texture = p.texture
	else:
		vp.ci.texture = _dummy_texture

	if p.shader != null:
		if _shader_material == null:
			_shader_material = ShaderMaterial.new()
		_shader_material.shader = p.shader
		
		vp.ci.material = _shader_material
		
		if p.params != null:
			for param_name in p.params:
				_shader_material.set_shader_parameter(param_name, p.params[param_name])
		
		var vp_size_f := Vector2(vp.viewport.size)
		var res_f := Vector2(_resolution)
		var scale_ndc := vp_size_f / res_f
		var pad_offset_ndc := ((vp_size_f - res_f) / 2.0) / vp_size_f
		var offset_ndc := -pad_offset_ndc + p.tile_pos / scale_ndc
		
		# Because padding may be used around the generated area,
		# the shader can use these predefined parameters,
		# and apply the following to SCREEN_UV to adjust its calculations:
		# 	vec2 uv = (SCREEN_UV + u_uv_offset) * u_uv_scale;
		
		if p.params == null or not p.params.has("u_uv_scale"):
			_shader_material.set_shader_parameter("u_uv_scale", scale_ndc)
		
		if p.params == null or not p.params.has("u_uv_offset"):
			_shader_material.set_shader_parameter("u_uv_offset", offset_ndc)
			
	else:
		vp.ci.material = null

	if p.clear:
		vp.viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE


# Called for every iteration of every pass
func _setup_iteration(vp: HT_TextureGeneratorViewport, prev_vp: HT_TextureGeneratorViewport):
	assert(vp != prev_vp)
	if _shader_material != null:
		_shader_material.set_shader_parameter("u_previous_pass", prev_vp.viewport.get_texture())


func _create_output_image(metadata, vp: HT_TextureGeneratorViewport):
	var tex := vp.viewport.get_texture()
	var src := tex.get_image()
#	src.save_png(str("ddd_tgen_output", metadata.maptype, ".png"))
	
	# Pick the center of the image
	var subrect := Rect2i( \
		(src.get_width() - _resolution.x) / 2, \
		(src.get_height() - _resolution.y) / 2, \
		_resolution.x, _resolution.y)
	
	# Make sure we are pixel-perfect. If not, padding is odd
#	assert(int(subrect.position.x) == subrect.position.x)
#	assert(int(subrect.position.y) == subrect.position.y)
	
	subrect.position.x -= _output_padding[0]
	subrect.position.y -= _output_padding[2]
	subrect.size.x += _output_padding[0] + _output_padding[1]
	subrect.size.y += _output_padding[2] + _output_padding[3]
		
	var dst : Image
	if subrect == Rect2i(0, 0, src.get_width(), src.get_height()):
		dst = src
	else:
		# Note: size MUST match at this point.
		# If it doesn't, the viewport has not been configured properly,
		# or padding has been modified while the generator was running
		dst = Image.create( \
			_resolution.x + _output_padding[0] + _output_padding[1], \
			_resolution.y + _output_padding[2] + _output_padding[3], \
			false, src.get_format())
		dst.blit_rect(src, subrect, Vector2i())

	output_generated.emit(dst, metadata)


func _report_progress(passes: Array, pass_index: int, iteration: int):
	var p = passes[pass_index]
	progress_reported.emit({
		"name": p.debug_name,
		"pass_index": pass_index,
		"pass_count": len(passes),
		"iteration": iteration,
		"iteration_count": p.iterations
	})

