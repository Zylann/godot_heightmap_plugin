#ifndef MATH_FUNCS_H
#define MATH_FUNCS_H

namespace Math {

inline float lerp(float minv, float maxv, float t) {
    return minv + t * (maxv - minv);
}

inline int clamp(int x, int minv, int maxv) {
    if (x < minv) {
        return minv;
    }
    if (x > maxv) {
        return maxv;
    }
    return x;
}

} // namespace Math

#endif // MATH_FUNCS_H
