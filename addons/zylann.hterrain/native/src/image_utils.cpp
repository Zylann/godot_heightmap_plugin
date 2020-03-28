#include "image_utils.h"
#include "int_range_2d.h"
#include "math_funcs.h"

namespace godot {

ImageUtils::ImageUtils() {
}

ImageUtils::~ImageUtils() {
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
    brush.lock();
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

void ImageUtils::lerp_red_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor, float target_value) const {
    ERR_FAIL_COND(image_ref.is_null());
    ERR_FAIL_COND(brush_ref.is_null());
    Image &image = **image_ref;
    Image &brush = **brush_ref;

    generic_brush_op(image, brush, p_pos, factor, [target_value](Image &image, int x, int y, float b) {
        float r = Math::lerp(image.get_pixel(x, y).r, target_value, b);
        image.set_pixel(x, y, Color(r, r, r));
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

void ImageUtils::_register_methods() {
    register_method("get_red_range", &ImageUtils::get_red_range);
    register_method("get_red_sum", &ImageUtils::get_red_sum);
    register_method("add_red_brush", &ImageUtils::add_red_brush);
    register_method("lerp_red_brush", &ImageUtils::lerp_red_brush);
    register_method("lerp_color_brush", &ImageUtils::lerp_color_brush);
}

} // namespace godot
