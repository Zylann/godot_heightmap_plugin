# Low-resolution representation of a density map, 
# used to roughly tell if there are any non-zero pixels in chunks of the map
class_name HTerrainDataOccupancyMap

const HT_Util = preload("res://addons/zylann.hterrain/util/util.gd")

var data := PackedByteArray()
var chunk_size := 32 # should  be power of two (future proofing)
var resolution := Vector2i() # in chunks
var threshold := 0.01


func get_state(cpos: Vector2i) -> bool:
	assert(Rect2i(Vector2i(), resolution).has_point(cpos))
	var i := cpos.x + cpos.y * resolution.x
	return data[i] == 1


#func set_state(cpos: Vector2i, state: bool) -> void:
	#var i := cpos.x + cpos.y * resolution.x
	#data[i] = 1 if state else 0


func update(im: Image) -> void:
	var res_chunks := HT_Util.ceildiv_vec2i_int(im.get_size(), chunk_size)
	var num_chunks := res_chunks.x * res_chunks.y
	data.resize(num_chunks)
	resolution = res_chunks
	update_from_pixel_rect(Rect2i(Vector2i(), im.get_size()), im)


func update_from_pixel_rect(rect_pixels: Rect2i, im: Image) -> void:
	var cmin := HT_Util.floordiv_vec2i_int(rect_pixels.position, chunk_size)
	var cmax := HT_Util.ceildiv_vec2i_int(rect_pixels.end, chunk_size)
	
	for cy in range(cmin.x, cmax.x):
		for cx in range(cmin.y, cmax.y):
			update_chunk(Vector2i(cx, cy), im)


func update_chunk(cpos: Vector2i, im: Image) -> void:
	assert(Rect2i(Vector2i(), resolution).has_point(cpos))
	var rect := Rect2i(cpos * chunk_size, Vector2i(chunk_size, chunk_size))
	# The image may not have a size multiple of chunk size
	rect = rect.intersection(Rect2i(Vector2i(), im.get_size()))
	var any := _has_any_pixel_above_threshold_l8(im, rect, threshold)
	var i := cpos.x + cpos.y * resolution.x
	data[i] = 1 if any else 0


static func _has_any_pixel_above_threshold_l8(im: Image, rect: Rect2i, threshold: float) -> bool:
	var minp := rect.position
	var maxp := rect.end
	for y in range(minp.y, maxp.y):
		for x in range(minp.x, maxp.x):
			var col := im.get_pixel(x, y)
			if col.r > threshold:
				return true
	return false
