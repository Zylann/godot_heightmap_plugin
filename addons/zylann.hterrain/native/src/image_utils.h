#ifndef IMAGE_UTILS_H
#define IMAGE_UTILS_H

#include <core/Godot.hpp>
#include <gen/Image.hpp>
#include <gen/Reference.hpp>
#include <vector>

namespace godot {

class ImageUtils : public Reference {
    GODOT_CLASS(ImageUtils, Reference)
public:
    static void _register_methods();

    ImageUtils();
    ~ImageUtils();

    void _init();

    Vector2 get_red_range(Ref<Image> image_ref, Rect2 rect) const;
    float get_red_sum(Ref<Image> image_ref, Rect2 rect) const;
    float get_red_sum_weighted(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor) const;
    void add_red_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor) const;
    void lerp_channel_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor, float target_value, int channel) const;
    void lerp_color_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor, Color target_value) const;
    float generate_gaussian_brush(Ref<Image> image_ref) const;
    void blur_red_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor);
    //void erode_red_brush(Ref<Image> image_ref, Ref<Image> brush_ref, Vector2 p_pos, float factor);

private:
    std::vector<float> _blur_buffer;
};

} // namespace godot

#endif // IMAGE_UTILS_H
