#include <core/Defs.hpp>
#include <core/PoolArrays.hpp>

#include "height_map_data.h"
#include "height_map.h"
#include "util/math.h"

#define DEFAULT_RESOLUTION 256
#define HEIGHTMAP_EXTENSION "heightmap"

using namespace godot;

const char *HeightMapData::SIGNAL_RESOLUTION_CHANGED = "resolution_changed";
const char *HeightMapData::SIGNAL_REGION_CHANGED = "region_changed";

const int HeightMapData::MAX_RESOLUTION = 4096 + 1;

// For serialization
const char *HEIGHTMAP_MAGIC_V1 = "GDHM";
const char *HEIGHTMAP_SUB_V = "v3__";

namespace {
	// TODO Not nice, and would need to be thread-safe
	PodVector<void*> s_height_map_data_db;
}

HeightMapData *HeightMapData::validate(Ref<Resource> &p_res) {
	if(p_res.is_null())
		return nullptr;
	void *ptr = godot::nativescript_api->godot_nativescript_get_userdata(*p_res);
	if(s_height_map_data_db.contains(ptr))
		return static_cast<HeightMapData*>(ptr);
	printf("Invalid HeightMapData reference\n");
	p_res.unref();
	return nullptr;
}
//HeightMapData *HeightMapData::validate(Resource *p_res) {
//	void *ptr = godot::nativescript_api->godot_nativescript_get_userdata(p_res);
//	if(s_height_map_data_db.contains(ptr))
//		return static_cast<HeightMapData*>(ptr);
//	printf("ERROR: Invalid HeightMapData reference\n");
//	return nullptr;
//}

void HeightMapData::_register_methods() {

	godot::register_method("set_resolution", &HeightMapData::set_resolution);
	godot::register_method("get_resolution", &HeightMapData::get_resolution);

	godot::register_method("get_height_at", &HeightMapData::get_height_at);
	godot::register_method("get_interpolated_height_at", &HeightMapData::get_interpolated_height_at);

	godot::register_method("_load_default", &HeightMapData::load_default);

	//#ifdef TOOLS_ENABLED
	godot::register_method("_apply_undo", &HeightMapData::_apply_undo);
	//#endif

	// This is not saved, because the custom data loader already assigns it.
	// Setting the STORAGE hint could cause resolution change twice and slowdown loading.
	godot::register_property(
		"resolution",
		&HeightMapData::set_resolution,
		&HeightMapData::get_resolution,
		DEFAULT_RESOLUTION,
		GODOT_METHOD_RPC_MODE_DISABLED,
		GODOT_PROPERTY_USAGE_EDITOR,
		GODOT_PROPERTY_HINT_NONE);

	godot::register_signal<HeightMapData>(SIGNAL_RESOLUTION_CHANGED);

	{
		Dictionary args;
		args["min_x"] = Variant::INT;
		args["min_y"] = Variant::INT;
		args["max_x"] = Variant::INT;
		args["max_y"] = Variant::INT;
		args["channel"] = Variant::INT;
		godot::register_signal<HeightMapData>(SIGNAL_REGION_CHANGED, args);
	}
}


// Important note about heightmap resolution:
//
// There is an off-by-one in the data, so for example a map of 512x512 will actually have 513x513 cells.
// Here is why,
// If we had an even amount of cells, it would produce this situation when making LOD chunks:
//
//   x---x---x---x      x---x---x---x
//   |   |   |   |      |       |
//   x---x---x---x      x   x   x   x
//   |   |   |   |      |       |
//   x---x---x---x      x---x---x---x
//   |   |   |   |      |       |
//   x---x---x---x      x   x   x   x
//
//       LOD 0              LOD 1
//
// We would be forced to ignore the last cells because they would produce an irregular chunk.
// We need an off-by-one because quads making up chunks SHARE their consecutive vertices.
// One quad needs at least 2x2 cells to exist. Two quads of the heightmap share an edge, which needs a total of 3x3 cells, not 4x4.
// One chunk has 16x16 quads, so it needs 17x17 cells, not 16, where the last cell is shared with the next chunk.
// As a result, a map of 4x4 chunks needs 65x65 cells, not 64x64.

HeightMapData::HeightMapData() {

	DDD("Construct HeightMapData\n");

	_resolution = 0;

	//#ifdef TOOLS_ENABLED
	_disable_apply_undo = false;
	//#endif

	s_height_map_data_db.push_back(this);
}

HeightMapData::~HeightMapData() {

	DDD("Destroy HeightMapData\n");

	s_height_map_data_db.unordered_remove(this);
}

void HeightMapData::load_default() {

	DDD("Loading default data");
	set_resolution(DEFAULT_RESOLUTION);
	update_all_normals();
}

int HeightMapData::get_resolution() const {
	return _resolution;
}

void HeightMapData::set_resolution(int p_res) {

	DDD("HeightMapData::set_resolution");

	if (p_res == get_resolution())
		return;

	if (p_res < HeightMap::CHUNK_SIZE)
		p_res = HeightMap::CHUNK_SIZE;

	// Power of two is important for LOD.
	// Also, grid data is off by one,
	// because for an even number of quads you need an odd number of vertices.
	// To prevent size from increasing at every deserialization, remove 1 before applying power of two.
	p_res = Math::next_power_of_2(p_res - 1) + 1;

	_resolution = p_res;

	// Resize heights
	if (_images[CHANNEL_HEIGHT].is_null()) {
		_images[CHANNEL_HEIGHT].instance();
		_images[CHANNEL_HEIGHT]->create(_resolution, _resolution, false, get_channel_format(CHANNEL_HEIGHT));
	} else {
		_images[CHANNEL_HEIGHT]->resize(_resolution, _resolution);
	}

	// Resize normals
	if (_images[CHANNEL_NORMAL].is_null()) {
		_images[CHANNEL_NORMAL].instance();
	}
	_images[CHANNEL_NORMAL]->create(_resolution, _resolution, false, get_channel_format(CHANNEL_NORMAL));
	update_all_normals();

	// Resize colors
	if (_images[CHANNEL_COLOR].is_null()) {
		_images[CHANNEL_COLOR].instance();
		_images[CHANNEL_COLOR]->create(_resolution, _resolution, false, get_channel_format(CHANNEL_COLOR));
		_images[CHANNEL_COLOR]->fill(Color(1, 1, 1));
	} else {
		_images[CHANNEL_COLOR]->resize(_resolution, _resolution);
	}

	// Resize splats
	if (_images[CHANNEL_SPLAT].is_null()) {

		_images[CHANNEL_SPLAT].instance();
		_images[CHANNEL_SPLAT]->create(_resolution, _resolution, false, get_channel_format(CHANNEL_SPLAT));

		Image &im = **_images[CHANNEL_SPLAT];
		PoolByteArray data = im.get_data();
		PoolByteArray::Write w = data.write();

		int len = data.size();
		const int bytes_per_pixel = 2;
		ERR_FAIL_COND(len != im.get_width() * im.get_height() * bytes_per_pixel);

		// Initialize weights so we can see the default texture
		for(int i = 1; i < len; i += 2) {
			w[i] = 128;
		}

	} else {
		_images[CHANNEL_SPLAT]->resize(_resolution, _resolution);
	}

	// Resize mask
	if (_images[CHANNEL_MASK].is_null()) {

		_images[CHANNEL_MASK].instance();
		_images[CHANNEL_MASK]->create(_resolution, _resolution, false, get_channel_format(CHANNEL_MASK));

		Image &im = **_images[CHANNEL_MASK];
		PoolByteArray data = im.get_data();
		PoolByteArray::Write w = data.write();

		int len = data.size();
		ERR_FAIL_COND(len != im.get_width() * im.get_height());

		// Initialize mask so the terrain has no holes by default
		memset(w.ptr(), 255, len);

	} else {
		_images[CHANNEL_SPLAT]->resize(_resolution, _resolution);
	}

	Point2i csize = Point2i(p_res, p_res) / HeightMap::CHUNK_SIZE;
	// TODO Could set `preserve_data` to true, but would require callback to construct new cells
	_chunked_vertical_bounds.resize(csize, false);
	update_vertical_bounds();

	owner->emit_signal(SIGNAL_RESOLUTION_CHANGED);
}

inline Color get_clamped(const Image &im, int x, int y) {

	if (x < 0)
		x = 0;
	else if(x >= im.get_width())
		x = im.get_width() - 1;

	if (y < 0)
		y = 0;
	else if (y >= im.get_height())
		y = im.get_height() - 1;

	return im.get_pixel(x, y);
}

real_t HeightMapData::get_height_at(int x, int y) {
	// This function is relatively slow due to locking, so don't use it to fetch large areas

	// Height data must be loaded in RAM
	ERR_FAIL_COND_V(_images[CHANNEL_HEIGHT].is_null(), 0.0);

	Image &im = **_images[CHANNEL_HEIGHT];
	im.lock();
	real_t h = get_clamped(im, x, y).r;
	im.unlock();
	return h;
}

real_t HeightMapData::get_interpolated_height_at(Vector3 pos) {
	// This function is relatively slow due to locking, so don't use it to fetch large areas

	// Height data must be loaded in RAM
	ERR_FAIL_COND_V(_images[CHANNEL_HEIGHT].is_null(), 0.0);

	// The function takes a Vector3 for convenience so it's easier to use in 3D scripting
	int x0 = pos.x;
	int y0 = pos.z;

	real_t xf = pos.x - x0;
	real_t yf = pos.z - y0;

	Image &im = **_images[CHANNEL_HEIGHT];
	im.lock();
	real_t h00 = get_clamped(im, x0, y0).r;
	real_t h10 = get_clamped(im, x0 + 1, y0).r;
	real_t h01 = get_clamped(im, x0, y0 + 1).r;
	real_t h11 = get_clamped(im, x0 + 1, y0 + 1).r;
	im.unlock();

	// Bilinear filter
	real_t h = Math::lerp(Math::lerp(h00, h10, xf), Math::lerp(h01, h11, xf), yf);

	return h;
}

void HeightMapData::update_all_normals() {
	update_normals(Point2i(), Point2i(_resolution, _resolution));
}

void HeightMapData::update_normals(Point2i min, Point2i size) {

	ERR_FAIL_COND(_images[CHANNEL_HEIGHT].is_null());
	ERR_FAIL_COND(_images[CHANNEL_NORMAL].is_null());

	Image &heights = **_images[CHANNEL_HEIGHT];
	Image &normals = **_images[CHANNEL_NORMAL];

	Point2i max = min + size;
	Point2i pos;

	clamp_min_max_excluded(min, max, Point2i(0, 0), Point2i(heights.get_width(), heights.get_height()));

	heights.lock();
	normals.lock();

	for (pos.y = min.y; pos.y < max.y; ++pos.y) {
		for (pos.x = min.x; pos.x < max.x; ++pos.x) {

			float left = get_clamped(heights, pos.x - 1, pos.y).r;
			float right = get_clamped(heights, pos.x + 1, pos.y).r;
			float fore = get_clamped(heights, pos.x, pos.y + 1).r;
			float back = get_clamped(heights, pos.x, pos.y - 1).r;

			Vector3 n = Vector3(left - right, 2.0, back - fore).normalized();

			normals.set_pixel(pos.x, pos.y, encode_normal(n));
		}
	}

	heights.unlock();
	normals.unlock();
}

void HeightMapData::notify_region_change(Point2i min, Point2i max, HeightMapData::Channel channel) {

	// TODO Hmm not sure if that belongs here // <-- why this, Me from the past?
	switch (channel) {
		case CHANNEL_HEIGHT:
			// TODO Optimization: when drawing very large patches, this might get called too often and would slow down.
			// for better user experience, we could set chunks AABBs to a very large height just while drawing,
			// and set correct AABBs as a background task once done
			update_vertical_bounds(min, max - min);

			upload_region(channel, min, max);
			upload_region(CHANNEL_NORMAL, min, max);
			break;

		case CHANNEL_NORMAL:
		case CHANNEL_SPLAT:
		case CHANNEL_COLOR:
		case CHANNEL_MASK:
			upload_region(channel, min, max);
			break;

		default:
			printf("Unrecognized channel\n");
			break;
	}

	godot::Array args;
	args.append(min.x);
	args.append(min.y);
	args.append(max.x);
	args.append(max.y);
	args.append(channel);
	owner->emit_signal(SIGNAL_REGION_CHANGED, args);
}

//#ifdef TOOLS_ENABLED

// Very specific to the editor.
// undo_data contains chunked grids of modified terrain in a given channel.
void HeightMapData::_apply_undo(Dictionary undo_data) {

	if (_disable_apply_undo)
		return;

	Array chunk_positions = undo_data["chunk_positions"];
	Array chunk_datas = undo_data["data"];
	int channel = undo_data["channel"];

	// Validate input

	ERR_FAIL_COND(channel < 0 || channel >= CHANNEL_COUNT);
	ERR_FAIL_COND(chunk_positions.size() / 2 != chunk_datas.size());

	ERR_FAIL_COND(chunk_positions.size() % 2 != 0);
	for (int i = 0; i < chunk_positions.size(); ++i) {
		Variant p = chunk_positions[i];
		ERR_FAIL_COND(p.get_type() != Variant::INT);
	}
	for (int i = 0; i < chunk_datas.size(); ++i) {
		Variant d = chunk_datas[i];
		ERR_FAIL_COND(d.get_type() != Variant::OBJECT);
	}

	// Apply

	for (int i = 0; i < chunk_datas.size(); ++i) {
		Point2i cpos;
		cpos.x = chunk_positions[2 * i];
		cpos.y = chunk_positions[2 * i + 1];

		Point2i min = cpos * HeightMap::CHUNK_SIZE;
		Point2i max = min + Point2i(1, 1) * HeightMap::CHUNK_SIZE;

		Ref<Image> data = chunk_datas[i];
		ERR_FAIL_COND(data.is_null());

		Rect2 data_rect(0, 0, data->get_width(), data->get_height());

		switch (channel) {

			case CHANNEL_HEIGHT:
				ERR_FAIL_COND(_images[channel].is_null());
				_images[channel]->blit_rect(data, data_rect, Vector2(min.x, min.y));
				// Padding is needed because normals are calculated using neighboring,
				// so a change in height X also requires normals in X-1 and X+1 to be updated
				update_normals(min - Point2i(1, 1), max + Point2i(1, 1));
				break;

			case CHANNEL_SPLAT:
			case CHANNEL_COLOR:
			case CHANNEL_MASK:
				ERR_FAIL_COND(_images[channel].is_null());
				_images[channel]->blit_rect(data, data_rect, Vector2(min.x, min.y));
				break;

			case CHANNEL_NORMAL:
				printf("This is a calculated channel!, no undo on this one\n");
				break;

			default:
				printf("Wut? Unsupported undo channel\n");
				break;
		}

		// TODO This one might be very slow even with partial texture update, due to rebinding...?
		notify_region_change(min, max, (Channel)channel);
	}
}

//#endif

void HeightMapData::upload_channel(Channel channel) {
	upload_region(channel, Point2i(0, 0), Point2i(_resolution, _resolution));
}

void HeightMapData::upload_region(Channel channel, Point2i min, Point2i max) {

	ERR_FAIL_COND(_images[channel].is_null());

	if (_textures[channel].is_null()) {
		_textures[channel].instance();
	}

	int flags = 0;

	if (channel == CHANNEL_NORMAL || channel == CHANNEL_COLOR) {
		// To allow smooth shading in fragment shader
		flags |= Texture::FLAG_FILTER;
	}

	//               ..ooo@@@XXX%%%xx..
	//            .oo@@XXX%x%xxx..     ` .
	//          .o@XX%%xx..               ` .
	//        o@X%..                  ..ooooooo
	//      .@X%x.                 ..o@@^^   ^^@@o
	//    .ooo@@@@@@ooo..      ..o@@^          @X%
	//    o@@^^^     ^^^@@@ooo.oo@@^             %
	//   xzI    -*--      ^^^o^^        --*-     %
	//   @@@o     ooooooo^@@^o^@X^@oooooo     .X%x
	//  I@@@@@@@@@XX%%xx  ( o@o )X%x@ROMBASED@@@X%x
	//  I@@@@XX%%xx  oo@@@@X% @@X%x   ^^^@@@@@@@X%x
	//   @X%xx     o@@@@@@@X% @@XX%%x  )    ^^@X%x
	//    ^   xx o@@@@@@@@Xx  ^ @XX%%x    xxx
	//          o@@^^^ooo I^^ I^o ooo   .  x
	//          oo @^ IX      I   ^X  @^ oo
	//          IX     U  .        V     IX
	//           V     .           .     V
	//
	// TODO Partial update pleaaase! SLOOOOOOOOOOWNESS AHEAD !!
	_textures[channel]->create_from_image(_images[channel], flags);
	//print_line(String("Channel updated ") + String::num(channel));
}

Ref<Image> HeightMapData::get_image(Channel channel) const {
	return _images[channel];
}

Ref<Texture> HeightMapData::get_texture(Channel channel) {
	if (_textures[channel].is_null() && _images[channel].is_valid()) {
		upload_channel(channel);
	}
	return _textures[channel];
}

AABB HeightMapData::get_region_aabb(Point2i origin_in_cells, Point2i size_in_cells) {

	// Get info from cached vertical bounds,
	// which is a lot faster than directly fetching heights from the map.
	// It's not 100% accurate, but enough for culling use case if chunk size is decently chosen.

	Point2i cmin = origin_in_cells / HeightMap::CHUNK_SIZE;
	Point2i cmax = (origin_in_cells + size_in_cells - Point2i(1, 1)) / HeightMap::CHUNK_SIZE + Point2i(1, 1);

	float min_height = _chunked_vertical_bounds[0].min;
	float max_height = min_height;

	for (int y = cmin.y; y < cmax.y; ++y) {
		for (int x = cmin.x; x < cmax.x; ++x) {

			VerticalBounds b = _chunked_vertical_bounds.get(x, y);

			if (b.min < min_height)
				min_height = b.min;

			if (b.max > max_height)
				max_height = b.max;
		}
	}

	AABB aabb;
	aabb.position = Vector3(origin_in_cells.x, min_height, origin_in_cells.y);
	aabb.size = Vector3(size_in_cells.x, max_height - min_height, size_in_cells.y);

	return aabb;
}

//float HeightMapData::get_estimated_height_at(Point2i pos) {
//	pos /= HeightMap::CHUNK_SIZE;
//	pos.x = CLAMP(pos.x, 0, _chunked_vertical_bounds.size().x);
//	pos.y = CLAMP(pos.y, 0, _chunked_vertical_bounds.size().y);
//	VerticalBounds b = _chunked_vertical_bounds.get(pos);
//	return (b.min + b.max) / 2.0;
//}

void HeightMapData::update_vertical_bounds() {
	update_vertical_bounds(Point2i(0,0), Point2i(_resolution-1, _resolution-1));
}

void HeightMapData::update_vertical_bounds(Point2i origin_in_cells, Point2i size_in_cells) {

	Point2i cmin = origin_in_cells / HeightMap::CHUNK_SIZE;
	Point2i cmax = (origin_in_cells + size_in_cells - Point2i(1, 1)) / HeightMap::CHUNK_SIZE + Point2i(1, 1);

	_chunked_vertical_bounds.clamp_min_max_excluded(cmin, cmax);

	// Note: chunks in _chunked_vertical_bounds share their edge cells and have an actual size of CHUNK_SIZE+1.
	const Point2i chunk_size(HeightMap::CHUNK_SIZE + 1, HeightMap::CHUNK_SIZE + 1);

	for (int y = cmin.y; y < cmax.y; ++y) {
		for (int x = cmin.x; x < cmax.x; ++x) {

			int i = _chunked_vertical_bounds.index(x, y);
			VerticalBounds &b = _chunked_vertical_bounds[i];
			Point2i min(x * HeightMap::CHUNK_SIZE, y * HeightMap::CHUNK_SIZE);
			compute_vertical_bounds_at(min, chunk_size, b.min, b.max);
		}
	}
}

void HeightMapData::compute_vertical_bounds_at(Point2i origin, Point2i size, float &out_min, float &out_max) {

	Ref<Image> heights_ref = _images[CHANNEL_HEIGHT];
	ERR_FAIL_COND(heights_ref.is_null());
	Image &heights = **heights_ref;

	Point2i min = origin;
	Point2i max = origin + size;

	heights.lock();

	float min_height = heights.get_pixel(min.x, min.y).r;
	float max_height = min_height;

	for (int y = min.y; y < max.y; ++y) {
		for (int x = min.x; x < max.x; ++x) {

			float h = heights.get_pixel(x, y).r;

			if (h < min_height)
				min_height = h;
			else if (h > max_height)
				max_height = h;
		}
	}

	heights.unlock();

	out_min = min_height;
	out_max = max_height;
}

Color HeightMapData::encode_normal(Vector3 n) {
	return Color(
			0.5 * (n.x + 1.0),
			0.5 * (n.y + 1.0),
			0.5 * (n.z + 1.0), 1.0);
}

Vector3 HeightMapData::decode_normal(Color c) {
	return Vector3(
			2.0 * c.r - 1.0,
			2.0 * c.g - 1.0,
			2.0 * c.b - 1.0);
}

Image::Format HeightMapData::get_channel_format(Channel channel) {
	switch (channel) {
		case CHANNEL_HEIGHT:
			return Image::FORMAT_RH;
		case CHANNEL_NORMAL:
			return Image::FORMAT_RGB8;
		case CHANNEL_SPLAT:
			return Image::FORMAT_RG8;
		case CHANNEL_COLOR:
			return Image::FORMAT_RGBA8;
		case CHANNEL_MASK:
			// TODO A bitmap would be 8 times lighter...
			return Image::FORMAT_R8;
	}
	printf("Unrecognized channel\n");
	return Image::FORMAT_MAX;
}

// FileAccess is not available in GDNative...
#if TODO
static void write_channel(FileAccess &f, Ref<Image> img_ref) {

	PoolVector<uint8_t> data = img_ref->get_data();
	PoolVector<uint8_t>::Read r = data.read();

	f.store_buffer(r.ptr(), data.size());
}

Error HeightMapData::_save(FileAccess &f) {

	// Sub-version
	f.store_buffer((const uint8_t *)HEIGHTMAP_SUB_V, 4);

	// Size
	//print_line(String("String saving resolution ") + String::num(_resolution));
	f.store_32(_resolution);
	f.store_32(_resolution);

	for (int channel = 0; channel < CHANNEL_COUNT; ++channel) {

		Ref<Image> im = _images[channel];
		//print_line(String("Saving channel ") + String::num(channel));

		// Sanity checks
		ERR_FAIL_COND_V(im.is_null(), ERR_FILE_CORRUPT);
		ERR_FAIL_COND_V(im->get_width() != _resolution || im->get_height() != _resolution, ERR_FILE_CORRUPT);

		write_channel(f, _images[channel]);
	}

	return OK;
}

static void load_channel(Ref<Image> &img_ref, int channel, FileAccess &f, Point2i size) {

	if (img_ref.is_null()) {
		img_ref.instance();
	}

	Image::Format format = HeightMapData::get_channel_format((HeightMapData::Channel)channel);
	ERR_FAIL_COND(format == Image::FORMAT_MAX);

	//img_ref->create(size.x, size.y, false, format);
	// I can't create the image before because getting the data array afterwards will increase refcount to 2.
	// Because of this, using a Write to set the bytes will trigger copy-on-write, which will:
	// 1) Needlessly double the amount of memory needed to load the image, and that image can be big
	// 2) Loose any loaded data because it gets loaded on a copy, not the actual image

	PoolVector<uint8_t> data;
	data.resize(Image::get_image_data_size(size.x, size.y, format, false));
	PoolVector<uint8_t>::Write w = data.write();

	//print_line(String("Load channel {0}, size={1}").format(varray(channel, data.size())));
	f.get_buffer(w.ptr(), data.size());

	img_ref->create(size.x, size.y, false, format, data);
}

Error HeightMapData::_load(FileAccess &f) {

	char version[5] = { 0 };
	f.get_buffer((uint8_t *)version, 4);

	if (strncmp(version, HEIGHTMAP_SUB_V, 4) != 0) {
		print_line(String("Invalid version, found {0}, expected {1}").format(varray(version, HEIGHTMAP_SUB_V)));
		return ERR_FILE_UNRECOGNIZED;
	}

	Point2i size;
	size.x = f.get_32();
	size.y = f.get_32();

	// Note: maybe one day we'll support non-square heightmaps
	_resolution = size.x;
	size.y = size.x;
	//print_line(String("Loaded resolution ") + String::num(_resolution));

	ERR_FAIL_COND_V(size.x > MAX_RESOLUTION, ERR_FILE_CORRUPT);
	ERR_FAIL_COND_V(size.y > MAX_RESOLUTION, ERR_FILE_CORRUPT);

	for (int channel = 0; channel < CHANNEL_COUNT; ++channel) {
		load_channel(_images[channel], channel, f, size);
	}

	_chunked_vertical_bounds.resize(size, false);
	update_vertical_bounds();

	return OK;
}

//---------------------------------------
// Saver

Error HeightMapDataSaver::save(const String &p_path, const Ref<Resource> &p_resource, uint32_t p_flags) {
	//print_line("Saving heightmap data");

	Ref<HeightMapData> heightmap_data_ref = p_resource;
	ERR_FAIL_COND_V(heightmap_data_ref.is_null(), ERR_BUG);

	FileAccessCompressed *fac = memnew(FileAccessCompressed);
	fac->configure(HEIGHTMAP_MAGIC_V1);
	Error err = fac->_open(p_path, FileAccess::WRITE);
	if (err) {
		//print_line("Error saving heightmap data");
		memdelete(fac);
		return err;
	}

	Error e = heightmap_data_ref->_save(*fac);

	fac->close();
	// TODO I didn't see examples doing this after close()... how is this freed?
	//memdelete(fac);

	return e;
}

bool HeightMapDataSaver::recognize(const Ref<Resource> &p_resource) const {
	if (p_resource.is_null())
		return false;
	return Object::cast_to<HeightMapData>(*p_resource) != NULL;
}

void HeightMapDataSaver::get_recognized_extensions(const Ref<Resource> &p_resource, List<String> *p_extensions) const {
	if (p_resource.is_null())
		return;
	if (Object::cast_to<HeightMapData>(*p_resource)) {
		p_extensions->push_back(HEIGHTMAP_EXTENSION);
	}
}

//---------------------------------------
// Loader

Ref<Resource> HeightMapDataLoader::load(const String &p_path, const String &p_original_path, Error *r_error) {
	//print_line("Loading heightmap data");

	FileAccessCompressed *fac = memnew(FileAccessCompressed);
	fac->configure(HEIGHTMAP_MAGIC_V1);
	Error err = fac->_open(p_path, FileAccess::READ);
	if (err) {
		//print_line("Error loading heightmap data");
		if (r_error)
			*r_error = err;
		memdelete(fac);
		return Ref<Resource>();
	}

	Ref<HeightMapData> heightmap_data_ref(memnew(HeightMapData));

	err = heightmap_data_ref->_load(*fac);
	if (err != OK) {
		if (r_error)
			*r_error = err;
		memdelete(fac);
		return Ref<Resource>();
	}

	fac->close();

	// TODO I didn't see examples doing this after close()... how is this freed?
	//memdelete(fac);

	if (r_error)
		*r_error = OK;
	return heightmap_data_ref;
}

void HeightMapDataLoader::get_recognized_extensions(List<String> *p_extensions) const {
	p_extensions->push_back(HEIGHTMAP_EXTENSION);
}

bool HeightMapDataLoader::handles_type(const String &p_type) const {
	return p_type == "HeightMapData";
}

String HeightMapDataLoader::get_resource_type(const String &p_path) const {
	String el = p_path.get_extension().to_lower();
	if (el == HEIGHTMAP_EXTENSION)
		return "HeightMapData";
	return "";
}
#endif

