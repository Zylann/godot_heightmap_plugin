
# Note: `tool` is optional but without it there are no error reporting in the editor
@tool

# TODO Remove grid_ prefixes, context is already given by the script itself


# Performs a positive integer division rounded to upper (4/2 = 2, 5/3 = 2)
static func up_div(a: int, b: int):
	if a % b != 0:
		return a / b + 1
	return a / b


# Creates a 2D array as an array of arrays.
# if v is provided, all cells will contain the same value.
# if v is a funcref, it will be executed to fill the grid cell per cell.
static func create_grid(w: int, h: int, v=null):
	var is_create_func = typeof(v) == TYPE_CALLABLE
	var grid := []
	grid.resize(h)
	for y in range(grid.size()):
		var row := []
		row.resize(w)
		if is_create_func:
			for x in range(row.size()):
				row[x] = v.call(x, y)
		else:
			for x in range(row.size()):
				row[x] = v
		grid[y] = row
	return grid


# Creates a 2D array that is a copy of another 2D array
static func clone_grid(other_grid):
	var grid := []
	grid.resize(other_grid.size())
	for y in range(0, grid.size()):
		var row := []
		var other_row = other_grid[y]
		row.resize(other_row.size())
		grid[y] = row
		for x in range(0, row.size()):
			row[x] = other_row[x]
	return grid


# Resizes a 2D array and allows to set or call functions for each deleted and created cells.
# This is especially useful if cells contain objects and you don't want to loose existing data.
static func resize_grid(grid, new_width, new_height, create_func=null, delete_func=null):
	# Check parameters
	assert(new_width >= 0 and new_height >= 0)
	assert(grid != null)
	if delete_func != null:
		assert(typeof(delete_func) == TYPE_CALLABLE)
	# `create_func` can also be a default value
	var is_create_func = typeof(create_func) == TYPE_CALLABLE

	# Get old size (supposed to be rectangular!)
	var old_height = grid.size()
	var old_width = 0
	if grid.size() != 0:
		old_width = grid[0].size()
	
	# Delete old rows
	if new_height < old_height:
		if delete_func != null:
			for y in range(new_height, grid.size()):
				var row = grid[y]
				for x in len(row):
					var elem = row[x]
					delete_func.call(elem)
		grid.resize(new_height)
	
	# Delete old columns
	if new_width < old_width:
		for y in len(grid):
			var row = grid[y]
			if delete_func != null:
				for x in range(new_width, row.size()):
					var elem = row[x]
					delete_func.call(elem)
			row.resize(new_width)
	
	# Create new columns
	if new_width > old_width:
		for y in len(grid):
			var row = grid[y]
			row.resize(new_width)
			if is_create_func:
				for x in range(old_width, new_width):
					row[x] = create_func.call(x,y)
			else:
				for x in range(old_width, new_width):
					row[x] = create_func
	
	# Create new rows
	if new_height > old_height:
		grid.resize(new_height)
		for y in range(old_height, new_height):
			var row = []
			row.resize(new_width)
			grid[y] = row
			if is_create_func:
				for x in new_width:
					row[x] = create_func.call(x,y)
			else:
				for x in new_width:
					row[x] = create_func
	
	# Debug test check
	assert(grid.size() == new_height)
	for y in len(grid):
		assert(len(grid[y]) == new_width)


# Retrieves the minimum and maximum values from a grid
static func grid_min_max(grid):
	if grid.size() == 0 or grid[0].size() == 0:
		return [0,0]
	var vmin = grid[0][0]
	var vmax = vmin
	for y in len(grid):
		var row = grid[y]
		for x in len(row):
			var v = row[x]
			if v > vmax:
				vmax = v
			elif v < vmin:
				vmin = v
	return [vmin, vmax]


# Copies a sub-region of a grid as a new grid. No boundary check!
static func grid_extract_area(src_grid, x0, y0, w, h):
	var dst = create_grid(w, h)
	for y in h:
		var dst_row = dst[y]
		var src_row = src_grid[y0+y]
		for x in w:
			dst_row[x] = src_row[x0+x]
	return dst


# Extracts data and crops the result if the requested rect crosses the bounds
static func grid_extract_area_safe_crop(src_grid, x0, y0, w, h):
	# Return empty is completely out of bounds
	var gw = src_grid.size()
	if gw == 0:
		return []
	var gh = src_grid[0].size()
	if x0 >= gw or y0 >= gh:
		return []
	
	# Crop min pos
	if x0 < 0:
		w += x0
		x0 = 0
	if y0 < 0:
		h += y0
		y0 = 0
	
	# Crop max pos
	if x0 + w >= gw:
		w = gw-x0
	if y0 + h >= gh:
		h = gh-y0

	return grid_extract_area(src_grid, x0, y0, w, h)


# Sets values from a grid inside another grid. No boundary check!
static func grid_paste(src_grid, dst_grid, x0, y0):
	for y in range(0, src_grid.size()):
		var src_row = src_grid[y]
		var dst_row = dst_grid[y0+y]
		for x in range(0, src_row.size()):
			dst_row[x0+x] = src_row[x]


# Tests if two grids are the same size and contain the same values
static func grid_equals(a, b):
	if a.size() != b.size():
		return false
	for y in a.size():
		var a_row = a[y]
		var b_row = b[y]
		if a_row.size() != b_row.size():
			return false
		for x in b_row.size():
			if a_row[x] != b_row[x]:
				return false
	return true


static func grid_get_or_default(grid, x, y, defval=null):
	if y >= 0 and y < len(grid):
		var row = grid[y]
		if x >= 0 and x < len(row):
			return row[x]
	return defval

