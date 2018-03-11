#ifndef HEIGHT_MAP_DATA_H
#define HEIGHT_MAP_DATA_H

#include <core/Godot.hpp>
#include <Resource.hpp>
#include <Texture.hpp>
#include <ImageTexture.hpp>
#include <Image.hpp>
#include <core/Ref.hpp>
#include <core/Vector3.hpp>

#include "util/point2i.h"
#include "util/pod_grid.h"


class HeightMapData : public godot::GodotScript<godot::Resource> {
	GODOT_CLASS(HeightMapData)

public:
	static void _register_methods();

	enum Channel {
		CHANNEL_HEIGHT = 0,
		CHANNEL_NORMAL,
		CHANNEL_SPLAT,
		CHANNEL_COLOR,
		CHANNEL_MASK,
		CHANNEL_COUNT
	};

	static const int MAX_RESOLUTION;

	static const char *SIGNAL_RESOLUTION_CHANGED;
	static const char *SIGNAL_REGION_CHANGED;

	static HeightMapData *validate(godot::Ref<godot::Resource> &p_res);
	//static HeightMapData *validate(godot::Resource *p_res);

	HeightMapData();
	~HeightMapData();

	void load_default();

	void set_resolution(int p_res);
	int get_resolution() const;

	real_t get_height_at(int x, int y);
	real_t get_interpolated_height_at(godot::Vector3 pos);

	void update_all_normals();
	void update_normals(Point2i min, Point2i size);

	void notify_region_change(Point2i min, Point2i max, Channel channel);

	godot::Ref<godot::Texture> get_texture(Channel channel);
	godot::Ref<godot::Image> get_image(Channel channel) const;

	godot::AABB get_region_aabb(Point2i origin_in_cells, Point2i size_in_cells);
	//float get_estimated_height_at(Point2i pos);

	static godot::Color encode_normal(godot::Vector3 n);
	static godot::Vector3 decode_normal(godot::Color c);

	static godot::Image::Format get_channel_format(Channel channel);

#if TODO
	godot::Error _load(FileAccess &f);
	godot::Error _save(FileAccess &f);
#endif

//#ifdef TOOLS_ENABLED
	bool _disable_apply_undo;
//#endif

private:

//#ifdef TOOLS_ENABLED
	void _apply_undo(godot::Dictionary undo_data);
//#endif

	static void _bind_methods();

	void upload_channel(Channel channel);
	void upload_region(Channel channel, Point2i min, Point2i max);

	void update_vertical_bounds();
	void update_vertical_bounds(Point2i min, Point2i max);
	void compute_vertical_bounds_at(Point2i origin, Point2i size, float &out_min, float &out_max);

private:
	int _resolution;

	godot::Ref<godot::ImageTexture> _textures[CHANNEL_COUNT];
	godot::Ref<godot::Image> _images[CHANNEL_COUNT];

	struct VerticalBounds {
		float min;
		float max;
		VerticalBounds() : min(0), max(0) {}
		VerticalBounds(float p_min, float p_max) : min(p_min), max(p_max) {}
	};

	PodGrid2D<VerticalBounds> _chunked_vertical_bounds;
};

//VARIANT_ENUM_CAST(HeightMapData::Channel)


#if TODO
class HeightMapDataSaver : public ResourceFormatSaver {
public:
	Error save(const String &p_path, const Ref<Resource> &p_resource, uint32_t p_flags);
	bool recognize(const Ref<Resource> &p_resource) const;
	void get_recognized_extensions(const Ref<Resource> &p_resource, List<String> *p_extensions) const;
};


class HeightMapDataLoader : public ResourceFormatLoader {
public:
	Ref<Resource> load(const String &p_path, const String &p_original_path, Error *r_error);
	void get_recognized_extensions(List<String> *p_extensions) const;
	bool handles_type(const String &p_type) const;
	String get_resource_type(const String &p_path) const;
};
#endif

#endif // HEIGHT_MAP_DATA_H
