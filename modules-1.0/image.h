#ifndef IMAGE_H
#define IMAGE_H

#include <vector>
#include <cassert>

namespace image {

class RGBA final {
public:
    RGBA(void): m_width(0), m_height(0) { }
    virtual ~RGBA() { }

    const std::vector<float> &red(void) const { return m_red; }
    const std::vector<float> &green(void) const { return m_green; }
    const std::vector<float> &blue(void) const { return m_blue; }
    const std::vector<float> &alpha(void) const { return m_alpha; }

    void resize(int width, int height);

    void get(int x, int y, float &r, float &g, float &b, float &a) const;
    void get(int x, int y, float &r, float &g, float &b) const;
    void set(int x, int y, float r, float g, float b, float a = 1.f);

    int width(void) const { return m_width; }
    int height(void) const { return m_height; }

    template <typename T, typename C> void load(int width, int height,
            const T *red, const T *green, const T *blue, const T *alpha,
            int pitch, int advance, const C &convert);

    template <typename T, typename C> void store(int width, int height,
            T *red, T *green, T *blue, T *alpha,
            int pitch, int advance, const C &convert) const;

    void load(int width, int height, const float *red,
            const float *green, const float *blue, const float *alpha,
            int pitch, int advance);

    void load(int width, int height, const unsigned short *red,
            const unsigned short *green, const unsigned short *blue,
            const unsigned short *alpha, int pitch, int advance);

    void load(int width, int height, const unsigned char *red,
            const unsigned char *green, const unsigned char *blue,
            const unsigned char *alpha, int pitch, int advance);

    void store(int width, int height, float *red,
            float *green, float *blue, float *alpha,
            int pitch, int advance) const;

    void store(int width, int height, unsigned short *red,
            unsigned short *green, unsigned short *blue,
            unsigned short *alpha, int pitch, int advance) const;

    void store(int width, int height, unsigned char *red,
            unsigned char *green, unsigned char *blue,
            unsigned char *alpha, int pitch, int advance) const;

private:
    int m_width, m_height;
    std::vector<float> m_red, m_green, m_blue, m_alpha;
};

inline
void RGBA::set(int x, int y, float r, float g, float b, float a) {
    int i = y*m_width+x;
    m_red[i] = r;
    m_green[i] = g;
    m_blue[i] = b;
    m_alpha[i] = a;
}

inline
void RGBA::get(int x, int y, float &r, float &g, float &b) const {
    int i = y*m_width+x;
    r = m_red[i];
    g = m_green[i];
    b = m_blue[i];
}

inline
void RGBA::get(int x, int y, float &r, float &g, float &b, float &a) const {
    int i = y*m_width+x;
    r = m_red[i];
    g = m_green[i];
    b = m_blue[i];
    a = m_alpha[i];
}

template <typename T, typename C>
void RGBA::load(int width, int height,
    const T *red, const T *green, const T *blue, const T *alpha,
    int pitch, int advance, const C &convert) {
    resize(width, height);
    if (red && green && blue && alpha) {
        for (int i = 0; i < height; i++) {
            int offset = 0;
            for (int j = 0; j < width; j++) {
                int index = i*width+j;
                m_red[index] = convert(red[offset]);
                m_green[index] = convert(green[offset]);
                m_blue[index] = convert(blue[offset]);
                m_alpha[index] = convert(alpha[offset]);
                offset += advance;
            }
            red += pitch;
            green += pitch;
            blue += pitch;
            alpha += pitch;
        }
    }
}

template <typename T, typename C>
void RGBA::store(int width, int height, T *red, T *green, T *blue,
    T *alpha, int pitch, int advance, const C &convert) const {
    assert(width == m_width && height == m_height);
    if (red && green && blue && alpha) {
        for (int i = 0; i < height; i++) {
            int offset = 0;
            for (int j = 0; j < width; j++) {
                int index = i*width+j;
                red[offset] = convert(m_red[index]);
                green[offset] = convert(m_green[index]);
                blue[offset] = convert(m_blue[index]);
                alpha[offset] = convert(m_alpha[index]);
                offset += advance;
            }
            red += pitch;
            green += pitch;
            blue += pitch;
            alpha += pitch;
        }
    }
}

} // namespace image

#endif // IMAGE_H
