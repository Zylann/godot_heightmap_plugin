@tool
extends AcceptDialog

const HT_Util = preload("../../util/util.gd")
const HT_Logger = preload("../../util/logger.gd")
const HTerrain = preload("../../hterrain.gd")
const HTerrainData = preload("../../hterrain_data.gd")

const ANCHOR_TOP_LEFT = 0
const ANCHOR_TOP = 1
const ANCHOR_TOP_RIGHT = 2
const ANCHOR_LEFT = 3
const ANCHOR_CENTER = 4
const ANCHOR_RIGHT = 5
const ANCHOR_BOTTOM_LEFT = 6
const ANCHOR_BOTTOM = 7
const ANCHOR_BOTTOM_RIGHT = 8
const ANCHOR_COUNT = 9

const _anchor_dirs = [
	[-1, -1],
	[0, -1],
	[1, -1],
	[-1, 0],
	[0, 0],
	[1, 0],
	[-1, 1],
	[0, 1],
	[1, 1]
]

const _anchor_icon_names = [
	"anchor_top_left",
	"anchor_top",
	"anchor_top_right",
	"anchor_left",
	"anchor_center",
	"anchor_right",
	"anchor_bottom_left",
	"anchor_bottom",
	"anchor_bottom_right"
]

signal permanent_change_performed(message)

@onready var _resolution_dropdown : OptionButton = $VBoxContainer/GridContainer/ResolutionDropdown
@onready var _stretch_checkbox : CheckBox = $VBoxContainer/GridContainer/StretchCheckBox
@onready var _anchor_control : Control = $VBoxContainer/GridContainer/HBoxContainer/AnchorControl

const _resolutions = HTerrainData.SUPPORTED_RESOLUTIONS

var _anchor_buttons := []
var _anchor_buttons_grid := {}
var _anchor_button_group : ButtonGroup = null
var _selected_anchor = ANCHOR_TOP_LEFT
var _logger = HT_Logger.get_for(self)

var _terrain : HTerrain = null


func set_terrain(terrain: HTerrain):
	_terrain = terrain


static func _get_icon(name) -> Texture2D:
	return load("res://addons/zylann.hterrain/tools/icons/icon_" + name + ".svg")


func _init():
	get_ok_button().hide()


func _ready():
	if HT_Util.is_in_edited_scene(self):
		return
	# TEST
	#show()
	
	for i in len(_resolutions):
		_resolution_dropdown.add_item(str(_resolutions[i]), i)
	
	_anchor_button_group = ButtonGroup.new()
	_anchor_buttons.resize(ANCHOR_COUNT)
	var x := 0
	var y := 0
	for i in _anchor_control.get_child_count():
		var child_node = _anchor_control.get_child(i)
		assert(child_node is Button)
		var child := child_node as Button
		child.toggle_mode = true
		child.custom_minimum_size = child.size
		child.icon = null
		child.pressed.connect(_on_AnchorButton_pressed.bind(i, x, y))
		child.button_group = _anchor_button_group
		_anchor_buttons[i] = child
		_anchor_buttons_grid[Vector2(x, y)] = child
		x += 1
		if x >= 3:
			x = 0
			y += 1

	_anchor_buttons[_selected_anchor].button_pressed = true
	# The signal apparently doesn't trigger in this case
	_on_AnchorButton_pressed(_selected_anchor, 0, 0)


func _notification(what: int):
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			# Select current resolution
			if _terrain != null and _terrain.get_data() != null:
				var res := _terrain.get_data().get_resolution()
				for i in len(_resolutions):
					if res == _resolutions[i]:
						_resolution_dropdown.select(i)
						break


func _on_AnchorButton_pressed(anchor0: int, x0: int, y0: int):
	_selected_anchor = anchor0
	
	for button in _anchor_buttons:
		button.icon = null
	
	for anchor in ANCHOR_COUNT:
		var d = _anchor_dirs[anchor]
		var nx = x0 + d[0]
		var ny = y0 + d[1]
		var k = Vector2(nx, ny)
		if not _anchor_buttons_grid.has(k):
			continue
		var button : Button = _anchor_buttons_grid[k]
		var icon := _get_icon(_anchor_icon_names[anchor])
		button.icon = icon


func _set_anchor_control_active(active: bool):
	for button in _anchor_buttons:
		button.disabled = not active


func _on_ResolutionDropdown_item_selected(id):
	pass


func _on_StretchCheckBox_toggled(button_pressed: bool):
	_set_anchor_control_active(not button_pressed)


func _on_ApplyButton_pressed():
	var stretch = _stretch_checkbox.button_pressed
	var res = _resolutions[_resolution_dropdown.get_selected_id()]
	var dir = _anchor_dirs[_selected_anchor]
	_apply(res, stretch, Vector2(dir[0], dir[1]))
	hide()


func _on_CancelButton_pressed():
	hide()


func _apply(p_resolution: int, p_stretch: bool, p_anchor: Vector2):
	if _terrain == null:
		_logger.error("Cannot apply resize, terrain is not set")
		return
	
	var data = _terrain.get_data()
	if data == null:
		_logger.error("Cannot apply resize, terrain has no data")
		return
	
	data.resize(p_resolution, p_stretch, p_anchor)
	data.notify_full_change()
	permanent_change_performed.emit("Resize terrain")
