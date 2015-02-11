#include <cstddef>
#include "image.h"

namespace image {

void RGBA::resize(int width, int height) {
    size_t old_size = m_red.size();
    size_t size = size_t(width*height);
    assert(old_size == m_green.size() && old_size == m_blue.size() &&
        old_size == m_alpha.size());
    if (size > old_size || 2*size < old_size) {
        m_red.resize(size);
        m_green.resize(size);
        m_blue.resize(size);
        m_alpha.resize(size);
        m_width = width;
        m_height = height;
    }
}

void RGBA::load(int width, int height, const float *red,
        const float *green, const float *blue, const float *alpha,
        int pitch, int advance) {
    auto convert = [](float f) { return f; };
    return load(width, height, red, green, blue, alpha,
            pitch, advance, convert);
}

void RGBA::load(int width, int height, const unsigned short *red,
        const unsigned short *green, const unsigned short *blue,
        const unsigned short *alpha, int pitch, int advance) {
    auto convert = [](unsigned short s) {
        return (1.f/65535.f)*static_cast<float>(s); };
    return load(width, height, red, green, blue, alpha,
            pitch, advance, convert);
}

void RGBA::load(int width, int height, const unsigned char *red,
        const unsigned char *green, const unsigned char *blue,
        const unsigned char *alpha, int pitch, int advance) {
    auto convert = [](unsigned char c) {
        return (1.f/255.f)*static_cast<float>(c); };
    return load(width, height, red, green, blue, alpha,
            pitch, advance, convert);
}

void RGBA::store(int width, int height, float *red,
        float *green, float *blue, float *alpha,
        int pitch, int advance) const {
    auto convert = [](float f) { return f; };
    return store(width, height, red, green, blue, alpha,
            pitch, advance, convert);
}

void RGBA::store(int width, int height, unsigned short *red,
        unsigned short *green, unsigned short *blue,
        unsigned short *alpha, int pitch, int advance) const {
    auto convert = [](float f) {
        f = f > 1.f? 1.f: (f < 0.f? 0.f: f);
        return static_cast<unsigned short>(65535.f*f);
    };
    return store(width, height, red, green, blue, alpha,
            pitch, advance, convert);
}

void RGBA::store(int width, int height, unsigned char *red,
        unsigned char *green, unsigned char *blue,
        unsigned char *alpha, int pitch, int advance) const {
    auto convert = [](float f) {
        f = f > 1.f? 1.f: (f < 0.f? 0.f: f);
        return static_cast<unsigned char>(255.f*f);
    };
    return store(width, height, red, green, blue, alpha,
            pitch, advance, convert);
}

}  // namespace image
