@tool
extends AcceptDialog

const HT_Util = preload("../../util/util.gd")
const HT_Logger = preload("../../util/logger.gd")
const HT_Errors = preload("../../util/errors.gd")

const PLUGIN_CFG_PATH = "res://addons/zylann.hterrain/plugin.cfg"


@onready var _about_rich_text_label : RichTextLabel = $VB/HB2/TC/About

var _logger = HT_Logger.get_for(self)


func _ready():
	if HT_Util.is_in_edited_scene(self):
		return

	var plugin_cfg = ConfigFile.new()
	var err := plugin_cfg.load(PLUGIN_CFG_PATH)
	if err != OK:
		_logger.error("Could not load {0}: {1}" \
			.format([PLUGIN_CFG_PATH, HT_Errors.get_message(err)]))
		return
	var version = plugin_cfg.get_value("plugin", "version", "--.--.--")
	
	_about_rich_text_label.text = _about_rich_text_label.text.format({"version": version})
