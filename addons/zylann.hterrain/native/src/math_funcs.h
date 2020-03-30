#ifndef MATH_FUNCS_H
#define MATH_FUNCS_H

namespace Math {

inline float lerp(float minv, float maxv, float t) {
    return minv + t * (maxv - minv);
}

template <typename T>
inline T clamp(T x, T minv, T maxv) {
    if (x < minv) {
        return minv;
    }
    if (x > maxv) {
        return maxv;
    }
    return x;
}

template <typename T>
inline T min(T a, T b) {
    return a < b ? a : b;
}

} // namespace Math

#endif // MATH_FUNCS_H
