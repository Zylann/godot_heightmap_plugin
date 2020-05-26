# Holds a viewport on which several passes may run to generate a final image.
# Passes can have different shaders and re-use what was drawn by a previous pass.
# TODO I'd like to make such a system working as a graph of passes for more possibilities.

tool
extends Node

class Pass:
	# Name of the pass, for debug purposes
	var debug_name = ""
	# The viewport will be cleared at this pass
	var clear = false
	# Which main texture should be drawn.
	# If not set, a default texture will be drawn.
	# Note that it won't matter if the shader disregards it,
	# and will only serve to provide UVs, due to https://github.com/godotengine/godot/issues/7298.
	var texture = null
	# Which shader to use
	var shader = null
	# Parameters for the shader
	var params = null
	# How many pixels to pad the viewport on all edges, in case neighboring matters.
	# Outputs won't have that padding, but can pick part of it in case output padding is used.
	var padding = 0
	# How many times this pass must be run
	var iterations = 1
	# If not empty, the viewport will be downloaded as an image before the next pass
	var output = false
	# Sent along the output
	var metadata = null
	# Used for tiled rendering, where each tile has the base resolution,
	# in case the viewport cannot be made big enough to cover the final image,
	# of if you are generating a pseudo-infinite terrain.
	# TODO Have an API for this?
	var tile_pos = Vector2()
	
	func duplicate():
		var p = get_script().new()
		p.debug_name = debug_name
		p.clear = clear
		p.texture = texture
		p.shader = shader
		p.params = params
		p.padding = padding
		p.iterations = iterations
		p.output = output
		p.metadata = metadata
		p.tile_pos = tile_pos
		return p


const Util = preload("res://addons/zylann.hterrain/util/util.gd")

signal progress_reported(info)
# Emitted when an output is generated.
signal output_generated(image, metadata)
# Emitted when all passes are complete
signal completed

var _passes := []
var _resolution := Vector2(512, 512)
var _output_padding := [0, 0, 0, 0]
var _viewport : Viewport = null
var _ci : TextureRect = null
var _dummy_texture = load("res://addons/zylann.hterrain/tools/icons/empty.png")
var _running := false
var _rerun := false
#var _tiles = PoolVector2Array([Vector2()])

var _running_passes := []
var _running_pass_index := 0
var _running_iteration := 0
var _shader_material : ShaderMaterial = null
#var _uv_offset = 0 # Offset de to padding


func _ready():
	assert(_viewport == null)
	assert(_ci == null)

	_viewport = Viewport.new()
	_viewport.own_world = true
	_viewport.world = World.new()
	_viewport.render_target_v_flip = true
	_viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
	add_child(_viewport)

	_ci = TextureRect.new()
	_ci.expand = true
	_ci.texture = _dummy_texture
	_viewport.add_child(_ci)
	
	_shader_material = ShaderMaterial.new()
	
	set_process(false)


func is_running() -> bool:
	return _running


func clear_passes():
	_passes.clear()


func add_pass(p: Pass):
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
func set_resolution(res: Vector2):
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
	
	assert(_viewport != null)
	assert(_ci != null)
	
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
	var padded_size := _resolution + 2 * Vector2(largest_padding, largest_padding)
	
#	_uv_offset = Vector2( \
#		float(largest_padding) / padded_size.x,
#		float(largest_padding) / padded_size.y)

	_ci.rect_size = padded_size

	_viewport.size = padded_size
	_viewport.render_target_update_mode = Viewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ONLY_NEXT_FRAME

	_running_pass_index = 0
	_running_iteration = 0
	_running = true
	set_process(true)


func _process(delta: float):
	# TODO because of https://github.com/godotengine/godot/issues/7894
	if not is_processing():
		return
	
	if _running_pass_index > 0:
		var prev_pass = _running_passes[_running_pass_index - 1]
		if prev_pass.output:
			_create_output_image(prev_pass.metadata)
	
	if _running_pass_index >= len(_running_passes):
		_running = false
		
		emit_signal("completed")
		
		if _rerun:
			# run() was requested again before we complete...
			# this will happen very frequently because we are forced to wait multiple frames
			# before getting a result
			_rerun = false
			run()
		else:
			_viewport.render_target_update_mode = Viewport.UPDATE_DISABLED
			set_process(false)
			return
	
	var p = _running_passes[_running_pass_index]
	
	if _running_iteration == 0:
		_setup_pass(p)
	
	_report_progress(_running_passes, _running_pass_index, _running_iteration)
	# Wait one frame for render, and this for EVERY iteration and every pass,
	# because Godot doesn't provide any way to run multiple feedback render passes in one go.
	_running_iteration += 1
	
	if _running_iteration == p.iterations:
		_running_iteration = 0
		_running_pass_index += 1
	
	# The viewport should render after the tree was processed


func _setup_pass(p: Pass):
	if p.texture != null:
		_ci.texture = p.texture
	else:
		_ci.texture = _dummy_texture

	if p.shader != null:
		if _shader_material == null:
			_shader_material = ShaderMaterial.new()
		_shader_material.shader = p.shader
		
		_ci.material = _shader_material
		
		if p.params != null:
			for param_name in p.params:
				_shader_material.set_shader_param(param_name, p.params[param_name])
		
		var scale_ndc = _viewport.size / _resolution
		var pad_offset_ndc = ((_viewport.size - _resolution) / 2) / _viewport.size
		var offset_ndc = -pad_offset_ndc + p.tile_pos / scale_ndc
		
		# Because padding may be used around the generated area,
		# the shader can use these predefined parameters,
		# and apply the following to SCREEN_UV to adjust its calculations:
		# 	vec2 uv = (SCREEN_UV + u_uv_offset) * u_uv_scale;
		
		if p.params == null or not p.params.has("u_uv_scale"):
			_shader_material.set_shader_param("u_uv_scale", scale_ndc)
			
		if p.params == null or not p.params.has("u_uv_offset"):
			_shader_material.set_shader_param("u_uv_offset", offset_ndc)
		
	else:
		_ci.material = null

	if p.clear:
		_viewport.render_target_clear_mode = Viewport.CLEAR_MODE_ONLY_NEXT_FRAME


func _create_output_image(metadata):
	var tex := _viewport.get_texture()
	var src := tex.get_data()
	
	# Pick the center of the image
	var subrect := Rect2( \
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
		
	var dst
	if subrect == Rect2(0, 0, src.get_width(), src.get_height()):
		dst = src
	else:
		dst = Image.new()
		# Note: size MUST match at this point.
		# If it doesn't, the viewport has not been configured properly,
		# or padding has been modified while the generator was running
		dst.create( \
			_resolution.x + _output_padding[0] + _output_padding[1], \
			_resolution.y + _output_padding[2] + _output_padding[3], \
			false, src.get_format())
		dst.blit_rect(src, subrect, Vector2())

	emit_signal("output_generated", dst, metadata)


func _report_progress(passes: Array, pass_index: int, iteration: int):
	var p = passes[pass_index]
	emit_signal("progress_reported", {
		"name": p.debug_name,
		"pass_index": pass_index,
		"pass_count": len(passes),
		"iteration": iteration,
		"iteration_count": p.iterations
	})

