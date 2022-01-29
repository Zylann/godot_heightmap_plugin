class_name XYZMeta

const MAX_INT = 9223372036854775807 # 2^63 - 1

var size_x = -1
var size_y = -1
var min_x = MAX_INT
var min_y = MAX_INT
var max_x = 0
var max_y = 0


func get_XYZ_Meta(f, logger):
	if size_x < 0 or size_y < 0:
		var splitted_line: PoolRealArray

		while !f.eof_reached():
			splitted_line = f.get_line().split_floats(" ")
			# logger.debug("{0}|{1}".format([splitted_line[0], splitted_line[1]]))
			# logger.debug("{0}|{1}|{2}|{3}".format([min_x, min_y, max_x, max_y]))
			if splitted_line.size() > 1:
				min_x = min(min_x, splitted_line[0])
				max_x = max(max_x, splitted_line[0])
				min_y = min(min_y, splitted_line[1])
				max_y = max(max_y, splitted_line[1])

		# logger.debug("{0}|{1}|{2}|{3}".format([min_x, min_y, max_x, max_y]))
		size_x = max_x - min_x
		size_y = max_y - min_y
	return {
		"width": size_x,
		"height": size_y,
		"min_x": min_x,
		"max_x": max_x,
		"min_y": min_y,
		"max_y": max_y
	}