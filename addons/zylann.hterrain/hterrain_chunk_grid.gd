
const HTerrainChunk = preload("./hterrain_chunk.gd")

var _chunks: Array[HTerrainChunk] = []
var _size := Vector2i()


func resize(res: Vector2i) -> void:
	assert(res.x > 0 and res.y > 0)
	_chunks.resize(res.x * res.y)
	_size = res


func clear() -> void:
	_chunks.clear()
	_size = Vector2i()


func is_valid_position(cpos: Vector2i) -> bool:
	return Rect2i(Vector2i(), _size).has_point(cpos)


func try_get_chunk(cpos: Vector2i) -> HTerrainChunk:
	if not is_valid_position(cpos):
		return null
	var i := cpos.x + _size.x * cpos.y
	return _chunks[i]


func set_chunk(cpos: Vector2i, chunk: HTerrainChunk) -> void:
	assert(is_valid_position(cpos))
	var i := cpos.x + _size.x * cpos.y
	_chunks[i] = chunk


func for_each_chunk(action) -> void:
	for chunk in _chunks:
		if chunk != null:
			action.exec(chunk)
