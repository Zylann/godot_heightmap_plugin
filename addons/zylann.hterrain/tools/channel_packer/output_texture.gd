tool
extends Control


const _index_to_channel = ["r", "g", "b", "a"]


func get_slot(channel_index):
	var c = _index_to_channel[channel_index]
	return get_node("Channels/" + c.capitalize())

