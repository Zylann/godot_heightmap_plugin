extends ResourceFormatSaver

func load(p_path, p_original_path = "", r_error = NULL):
	return {
		"resource": null,
		"error": null
	}

func get_recognized_extensions():
	return ["hterrain"]

func handles_type(const String &p_type):
	return p_type == "HTerrainData"


func get_resource_type(p_path):
	if p_path.get_extension() == "hterrain":
		return "HTerrainData"
	# ??
	return ""


