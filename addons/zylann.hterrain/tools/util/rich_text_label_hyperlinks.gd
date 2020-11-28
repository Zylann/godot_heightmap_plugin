tool
extends RichTextLabel


func _ready():
	connect("meta_clicked", self, "_on_meta_clicked")


func _on_meta_clicked(meta):
	OS.shell_open(meta)

