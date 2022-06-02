#include "image_utils.h"
#include "int_range_2d.h"
#include "math_funcs.h"

namespace godot {

template <typename F>
inline void generic_brush_op(Image &image, Image &brush, Vector2 p_pos, float factor, F op) {
	IntRange2D range = IntRange2D::from_min_max(p_pos, brush.get_size());
	int min_x_noclamp = range.min_x;
	int min_y_noclamp = range.min_y;
	range.clip(Vector2i(image.get_size()));

	image.lock();
	brush.lock();

	for (int y = range.min_y; y < range.max_y; ++y) {
		int by = y - min_y_noclamp;

		for (int x = range.min_x; x < range.max_x; ++x) {
			int bx = x - min_x_noclamp;

			float b = brush.get_pixel(bx, by).r * factor;
			op(image, x, y, b);
		}
	}

	image.unlock();
	brush.unlock();
}

ImageUtils::ImageUtils() {
#ifdef _DEBUG
	Godot::print("Constructing ImageUtils");
#endif
}

ImageUtils::~ImageUtils() {
#ifdef _DEBUG
	// TODO Cannot print shit here, see https://github.com/godotengine/godot/issues/37417
	// Means only the console will print this
	//Godot::print("Destructing ImageUtils");
	printf("Destructing ImageUtils\n");
#endif
}

void ImageUtils::_init() {
}

Vector2 ImageUtils::get_red_range(Ref<Image> image_ref, Rect2 rect) const {
	ERR_FAIL_COND_V(image_ref.is_null(), Vector2());
	Image &image = **image_ref;

	IntRange2D range(rect);
	range.clip(Vector2i(image.get_size()));

	image.lock();

	float min_value = image.get_pixel(range.min_x, range.min_y).r;
	float max_value = min_value;

	for (int y = range.min_y; y < range.max_y; ++y) {
		for (int x = range.min_x; x < range.max_x; ++x) {
			float v = image.get_pixel(x, y).r;

			if (v > max_value) {
				max_value = v;
			} else if (v < min_value) {
				min_value = v;
			}
		}
	}

	image.unlock();

	return Vector2(min_value, max_value);
}

float ImageUtils::get_red_sum(Ref<Image> image_ref, Rect2 rect) const {
	ERR_FAIL_COND_V(image_ref.is_null(), 0.f);
	Image &image = **image_ref;

	IntRange2D range(rect);
	range.clip(Vector2i(image.get_size()));

	image.lock();

	float sum = 0.f;

	for (int y = range.min_y; y < range.max_y; ++y) {
		for (int x = range.min_x; x < range.max_x; ++x) {
			sum += image.get_pixel(x, y).r;
		}
	}

	image.unlock();

	return sum;
}

float ImageUtils::get_red_sum_weighted(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor) const {
	ERR_FAIL_COND_V(image_ref.is_null(), 0.f);
	ERR_FAIL_COND_V(brush_ref.is_null(), 0.f);
	Image &image = **image_ref;
	Image &brush = **brush_ref;

	float sum = 0.f;
	generic_brush_op(image, brush, p_pos, factor, [&sum](Image &image, int x, int y, float b) {
		sum += image.get_pixel(x, y).r * b;
	});

	return sum;
}

void ImageUtils::add_red_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor) const {
	ERR_FAIL_COND(image_ref.is_null());
	ERR_FAIL_COND(brush_ref.is_null());
	Image &image = **image_ref;
	Image &brush = **brush_ref;

	generic_brush_op(image, brush, p_pos, factor, [](Image &image, int x, int y, float b) {
		float r = image.get_pixel(x, y).r + b;
		image.set_pixel(x, y, Color(r, r, r));
	});
}

void ImageUtils::lerp_channel_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor, float target_value, int channel) const {
	ERR_FAIL_COND(image_ref.is_null());
	ERR_FAIL_COND(brush_ref.is_null());
	Image &image = **image_ref;
	Image &brush = **brush_ref;

	generic_brush_op(image, brush, p_pos, factor, [target_value, channel](Image &image, int x, int y, float b) {
		Color c = image.get_pixel(x, y);
		c[channel] = Math::lerp(c[channel], target_value, b);
		image.set_pixel(x, y, c);
	});
}

void ImageUtils::lerp_color_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor, Color target_value) const {
	ERR_FAIL_COND(image_ref.is_null());
	ERR_FAIL_COND(brush_ref.is_null());
	Image &image = **image_ref;
	Image &brush = **brush_ref;

	generic_brush_op(image, brush, p_pos, factor, [target_value](Image &image, int x, int y, float b) {
		const Color c = image.get_pixel(x, y).linear_interpolate(target_value, b);
		image.set_pixel(x, y, c);
	});
}

// TODO Smooth (each pixel being box-filtered, contrary to the existing smooth)

float ImageUtils::generate_gaussian_brush(Ref<Image> image_ref) const {
	ERR_FAIL_COND_V(image_ref.is_null(), 0.f);
	Image &image = **image_ref;

	int w = static_cast<int>(image.get_width());
	int h = static_cast<int>(image.get_height());
	Vector2 center(w / 2, h / 2);
	float radius = Math::min(w, h) / 2;

	ERR_FAIL_COND_V(radius <= 0.1f, 0.f);

	float sum = 0.f;
	image.lock();

	for (int y = 0; y < h; ++y) {
		for (int x = 0; x < w; ++x) {
			float d = Vector2(x, y).distance_to(center) / radius;
			float v = Math::clamp(1.f - d * d * d, 0.f, 1.f);
			image.set_pixel(x, y, Color(v, v, v));
			sum += v;
		}
	}

	image.unlock();
	return sum;
}

void ImageUtils::blur_red_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor) {
	ERR_FAIL_COND(image_ref.is_null());
	ERR_FAIL_COND(brush_ref.is_null());
	Image &image = **image_ref;
	Image &brush = **brush_ref;

	factor = Math::clamp(factor, 0.f, 1.f);

	// Relative to the image
	IntRange2D buffer_range = IntRange2D::from_pos_size(p_pos, brush.get_size());
	buffer_range.pad(1);

	const int image_width = static_cast<int>(image.get_width());
	const int image_height = static_cast<int>(image.get_height());

	const int buffer_width = static_cast<int>(buffer_range.get_width());
	const int buffer_height = static_cast<int>(buffer_range.get_height());
	_blur_buffer.resize(buffer_width * buffer_height);

	image.lock();

	// Cache pixels, because they will be queried more than once and written to later
	int buffer_i = 0;
	for (int y = buffer_range.min_y; y < buffer_range.max_y; ++y) {
		for (int x = buffer_range.min_x; x < buffer_range.max_x; ++x) {
			const int ix = Math::clamp(x, 0, image_width - 1);
			const int iy = Math::clamp(y, 0, image_height - 1);
			_blur_buffer[buffer_i] = image.get_pixel(ix, iy).r;
			++buffer_i;
		}
	}

	IntRange2D range = IntRange2D::from_min_max(p_pos, brush.get_size());
	const int min_x_noclamp = range.min_x;
	const int min_y_noclamp = range.min_y;
	range.clip(Vector2i(image.get_size()));

	const int buffer_offset_left = -1;
	const int buffer_offset_right = 1;
	const int buffer_offset_top = -buffer_width;
	const int buffer_offset_bottom = buffer_width;

	brush.lock();

	// Apply blur
	for (int y = range.min_y; y < range.max_y; ++y) {
		const int brush_y = y - min_y_noclamp;

		for (int x = range.min_x; x < range.max_x; ++x) {
			const int brush_x = x - min_x_noclamp;

			const float brush_value = brush.get_pixel(brush_x, brush_y).r * factor;

			buffer_i = (brush_x + 1) + (brush_y + 1) * buffer_width;

			const float p10 = _blur_buffer[buffer_i + buffer_offset_top];
			const float p01 = _blur_buffer[buffer_i + buffer_offset_left];
			const float p11 = _blur_buffer[buffer_i];
			const float p21 = _blur_buffer[buffer_i + buffer_offset_right];
			const float p12 = _blur_buffer[buffer_i + buffer_offset_bottom];

			// Average
			float m = (p10 + p01 + p11 + p21 + p12) * 0.2f;
			float p = Math::lerp(p11, m, brush_value);

			image.set_pixel(x, y, Color(p, p, p));
		}
	}

	image.unlock();
	brush.unlock();
}

void ImageUtils::paint_indexed_splat(Ref<Image> index_map_ref, Ref<Image> weight_map_ref,
		Ref<Image> brush_ref, Vector2 p_pos, int texture_index, float factor) {

	ERR_FAIL_COND(index_map_ref.is_null());
	ERR_FAIL_COND(weight_map_ref.is_null());
	ERR_FAIL_COND(brush_ref.is_null());
	Image &index_map = **index_map_ref;
	Image &weight_map = **weight_map_ref;
	Image &brush = **brush_ref;

	ERR_FAIL_COND(index_map.get_size() != weight_map.get_size());

	factor = Math::clamp(factor, 0.f, 1.f);

	IntRange2D range = IntRange2D::from_min_max(p_pos, brush.get_size());
	const int min_x_noclamp = range.min_x;
	const int min_y_noclamp = range.min_y;
	range.clip(Vector2i(index_map.get_size()));

	const float texture_index_f = float(texture_index) / 255.f;
	const Color all_texture_index_f(texture_index_f, texture_index_f, texture_index_f);
	const int ci = texture_index % 3;
	Color cm(-1, -1, -1);
	cm[ci] = 1;

	brush.lock();
	index_map.lock();
	weight_map.lock();

	for (int y = range.min_y; y < range.max_y; ++y) {
		const int brush_y = y - min_y_noclamp;

		for (int x = range.min_x; x < range.max_x; ++x) {
			const int brush_x = x - min_x_noclamp;

			const float brush_value = brush.get_pixel(brush_x, brush_y).r * factor;

			if (brush_value == 0.f) {
				continue;
			}

			Color i = index_map.get_pixel(x, y);
			Color w = weight_map.get_pixel(x, y);

			// Decompress third weight to make computations easier
			w[2] = 1.f - w[0] - w[1];

			if (std::abs(i[ci] - texture_index_f) > 0.001f) {
				// Pixel does not have our texture index,
				// transfer its weight to other components first
				if (w[ci] > brush_value) {
					w[0] -= cm[0] * brush_value;
					w[1] -= cm[1] * brush_value;
					w[2] -= cm[2] * brush_value;

				} else if (w[ci] >= 0.f) {
					w[ci] = 0.f;
					i[ci] = texture_index_f;
				}

			} else {
				// Pixel has our texture index, increase its weight
				if (w[ci] + brush_value < 1.f) {
					w[0] += cm[0] * brush_value;
					w[1] += cm[1] * brush_value;
					w[2] += cm[2] * brush_value;

				} else {
					// Pixel weight is full, we can set all components to the same index.
					// Need to nullify other weights because they would otherwise never reach
					// zero due to normalization
					w = Color(0, 0, 0);
					w[ci] = 1.0;
					i = all_texture_index_f;
				}
			}

			// No `saturate` function in Color??
			w[0] = Math::clamp(w[0], 0.f, 1.f);
			w[1] = Math::clamp(w[1], 0.f, 1.f);
			w[2] = Math::clamp(w[2], 0.f, 1.f);

			// Renormalize
			const float sum = w[0] + w[1] + w[2];
			w[0] /= sum;
			w[1] /= sum;
			w[2] /= sum;

			index_map.set_pixel(x, y, i);
			weight_map.set_pixel(x, y, w);
		}
	}

	brush.lock();
	index_map.unlock();
	weight_map.unlock();
}

void ImageUtils::_register_methods() {
	register_method("get_red_range", &ImageUtils::get_red_range);
	register_method("get_red_sum", &ImageUtils::get_red_sum);
	register_method("get_red_sum_weighted", &ImageUtils::get_red_sum_weighted);
	register_method("add_red_brush", &ImageUtils::add_red_brush);
	register_method("lerp_channel_brush", &ImageUtils::lerp_channel_brush);
	register_method("lerp_color_brush", &ImageUtils::lerp_color_brush);
	register_method("generate_gaussian_brush", &ImageUtils::generate_gaussian_brush);
	register_method("blur_red_brush", &ImageUtils::blur_red_brush);
	register_method("paint_indexed_splat", &ImageUtils::paint_indexed_splat);
}

} // namespace godot
