#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <png.h>
#include <zlib.h>

#include "image.h"
#include "pngio.h"

static char *mystrdup(const char *str) {
    char *copy = (char *) malloc(strlen(str)+1);
    if (!copy) return NULL;
    return strcpy(copy, str);
}

static std::vector<png_text> g_text;

static void user_error_fn(png_structp png_ptr,
	png_const_charp error_msg) {
	(void) png_ptr;
	fprintf(stderr, "libpng error: %s\n", error_msg);
}

static void user_warning_fn(png_structp png_ptr,
	png_const_charp warning_msg) {
	(void) png_ptr;
	fprintf(stderr, "libpng warning: %s\n", warning_msg);
}

template <typename T> int to_bit_depth(void);
template <> int to_bit_depth<png_uint_16>(void) { return 16; }
template <> int to_bit_depth<png_byte>(void) { return 8; }

class FileReader {
public:
    FileReader(FILE *file): m_file(file) { }
    size_t operator()(char *out, size_t len) {
        return fread(out, 1, len, m_file);
    }
private:
    FILE *m_file;
};

class FileWriter {
public:
    FileWriter(FILE *file): m_file(file) { }
    size_t operator()(char *in, size_t len) {
        return fwrite(in, 1, len, m_file);
    }
private:
    FILE *m_file;
};

class StringWriter {
public:
    StringWriter(std::string &memory): m_memory(memory) { }
    size_t operator()(char *in, size_t len) {
        m_memory.insert(m_memory.end(), in, in+len);
        return len;
    }
private:
    std::string &m_memory;
};

class StringReader {
public:
    StringReader(const std::string &memory): m_memory(memory), m_done(0) { }
    size_t operator()(char *out, size_t len) {
        size_t end = m_done + len;
        end > m_memory.size()? m_memory.size(): end;
        len = end - m_done;
        memcpy(out, &m_memory[m_done], len);
        m_done += len;
        return len;
    }
private:
    const std::string &m_memory;
    size_t m_done;
};

template <typename IO>
void io_fn(png_structp png_ptr, png_bytep out, png_size_t len) {
    void *io_ptr = png_get_io_ptr(png_ptr);
    if (!io_ptr) {
        fprintf(stderr, "invalid pointer\n");
        longjmp(png_jmpbuf(png_ptr), 1);
    }
    IO& io = *reinterpret_cast<IO*>(io_ptr);
    size_t done = io(reinterpret_cast<char *>(out), static_cast<size_t>(len));
    if (done != len) {
        fprintf(stderr, "IO error\n");
        longjmp(png_jmpbuf(png_ptr), 1);
    }
}

namespace pngio {

    void free_text(void) {
        for (unsigned i = 0; i < g_text.size(); i++) {
            free(g_text[i].key);
            free(g_text[i].text);
        }
        g_text.resize(0);
    }

    void init_text(int argc, char **argv) {
        free_text();
        g_text.resize(argc);
        for (int i = 0; i < argc; i++) {
            char key[256];
            sprintf(key, "argv:%02d", i);
            g_text[i].compression = PNG_TEXT_COMPRESSION_NONE;
            g_text[i].key = mystrdup(key);
            g_text[i].text = mystrdup(argv[i]);
        }
    }

    void push_text(const char *key, const char *text) {
        png_text entry;
        entry.compression = PNG_TEXT_COMPRESSION_NONE;
        entry.key = mystrdup(key);
        entry.text = mystrdup(text);
        g_text.push_back(entry);
    }

    void pop_text(int n) {
        for (int i = 0; i < n; i++) {
            if (!g_text.empty()) {
                free(g_text.back().key);
                free(g_text.back().text);
                g_text.pop_back();
            }
        }
    }

    template <typename R> int load(R &reader, image::RGBA &rgba) {
        // temporary image storage
        png_uint_16 ** volatile row_pointers = NULL;
        png_uint_16 * volatile data = NULL;
        // libpng structures
        png_structp png_ptr = NULL;
        png_infop info_ptr = NULL;
        // check if it is a PNG file
        char signature[8];
        if (reader(signature, 8) < 8) {
            fprintf(stderr, "unable to read from file");
            return 0;
        }
        if (png_sig_cmp((unsigned char *)signature, 0, 8)) {
            fprintf(stderr, "not a PNG");
            return 0;
        }
        // allocate reading structures
        png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL,
            user_error_fn, user_warning_fn);
        if (png_ptr) {
            info_ptr = png_create_info_struct(png_ptr);
        }
        if (!png_ptr || !info_ptr) {
            png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
            fprintf(stderr, "unable to allocate structures");
            return 0;
        }
        // setup long jump for error return
        if (setjmp(png_jmpbuf(png_ptr))) {
            png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
            free(row_pointers);
            free(data);
            return 0;
        }
        png_set_read_fn(png_ptr, &reader, io_fn<R>);
        png_set_sig_bytes(png_ptr, 8); // already skept 8 bytes
        // do not premultiply alpha
        png_set_alpha_mode(png_ptr, PNG_ALPHA_PNG, PNG_DEFAULT_sRGB);
        // load image information
        png_read_info(png_ptr, info_ptr);
        // get dimensions
        int height = png_get_image_height(png_ptr, info_ptr);
        int width = png_get_image_width(png_ptr, info_ptr);
        // allocate temporary image buffer and row_pointers
        data = reinterpret_cast<png_uint_16 *>(
            malloc(height*width*4*sizeof(png_uint_16)));
        row_pointers = reinterpret_cast<png_uint_16 **>(
            malloc(height*sizeof(png_uint_16 *)));
        // try to allocate output image
        if (!data || !row_pointers) {
            // might as well use the same error handling as libpng...
            longjmp(png_jmpbuf(png_ptr), 1);
        }
        // set row pointers to flip image
        for (int i = 0; i < height; i++) {
            row_pointers[i] = &data[(height-1-i)*width*4];
        }
        // set all transformations required to read from any
        // format into RGBA16
        int color_type = png_get_color_type(png_ptr, info_ptr);
        int bit_depth = png_get_bit_depth(png_ptr, info_ptr);
        if (color_type == PNG_COLOR_TYPE_PALETTE) {
            png_set_palette_to_rgb(png_ptr);
        }

        if (color_type == PNG_COLOR_TYPE_GRAY ||
            color_type == PNG_COLOR_TYPE_GRAY_ALPHA) {
            png_set_gray_to_rgb(png_ptr);
        }

        if (color_type == PNG_COLOR_TYPE_RGB ||
            color_type == PNG_COLOR_TYPE_GRAY ||
            color_type == PNG_COLOR_TYPE_PALETTE) {
            png_set_add_alpha(png_ptr, 0xFFFF, PNG_FILLER_AFTER);
        }

        if (bit_depth < 16) {
            png_set_expand_16(png_ptr);
        }

        if (png_get_valid(png_ptr, info_ptr, PNG_INFO_tRNS)) {
            png_set_tRNS_to_alpha(png_ptr);
        }

        // should we flip endianness?
        long int a = 1;
        int swap = (*((unsigned char *) &a) == 1);
        if (swap) {
            png_set_swap(png_ptr);
        }
        // read image
        png_read_image(png_ptr, (png_bytepp) row_pointers);
        // save to image object
        rgba.load(width, height, data, data+1, data+2, data+3, 4*width, 4);
        // finish advancing file pointer to end of stream (useful?)
        png_read_end(png_ptr, NULL);
        // clean-up and we are done
        png_destroy_read_struct(&png_ptr, &info_ptr, NULL);
        free(data);
        free(row_pointers);
        return 1;
    }

    int load(FILE *file, image::RGBA &rgba) {
        FileReader reader(file);
        return load(reader, rgba);
    }

    int load(const std::string &memory, image::RGBA &rgba) {
        StringReader reader(memory);
        return load(reader, rgba);
    }

    template <typename T, typename W>
    int store(W &writer, const image::RGBA &rgba) {
        // temporary image storage
        T ** volatile row_pointers = NULL;
        T * volatile data = NULL;
        // libpng structures
        png_structp png_ptr = NULL;
        png_infop info_ptr = NULL;
        // allocate reading structures
        png_ptr = png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL,
            user_error_fn, user_warning_fn);
        if (png_ptr) {
            info_ptr = png_create_info_struct(png_ptr);
        }
        if (!png_ptr || !info_ptr) {
            png_destroy_write_struct(&png_ptr, &info_ptr);
            fprintf(stderr, "unable to allocate structures");
            return 0;
        }
        // setup long jump for error return
        if (setjmp(png_jmpbuf(png_ptr))) {
            png_destroy_write_struct(&png_ptr, &info_ptr);
            free(row_pointers);
            free(data);
            return 0;
        }
        png_set_write_fn(png_ptr, &writer, io_fn<W>, nullptr);
        int height = rgba.height();
        int width = rgba.width();
        int color_type = PNG_COLOR_TYPE_RGB_ALPHA;
        int bit_depth = to_bit_depth<T>();
        // allocate temporary image buffer and row_pointers
        data = reinterpret_cast<T *>(malloc(height*width*4*sizeof(T)));
        row_pointers = reinterpret_cast<T **>(malloc(height*sizeof(T *)));
        if (g_text.size() > 0)
            png_set_text(png_ptr, info_ptr, &g_text[0], (int) g_text.size());
        // try to allocate output image
        // might as well use the same error handling as libpng...
        if (!data || !row_pointers) 
            longjmp(png_jmpbuf(png_ptr), 1);
        // set row pointers to flip image
        for (int i = 0; i < height; i++) 
            row_pointers[i] = &data[(height-i-1)*width*4];
        // store from object into buffer
        rgba.store(width, height, data, data+1, data+2, data+3, 4*width, 4);
        // set basic image parameters
        png_set_IHDR(png_ptr, info_ptr, width, height, bit_depth,
            color_type, PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT,
            PNG_FILTER_TYPE_DEFAULT);
        png_set_sRGB_gAMA_and_cHRM(png_ptr, info_ptr,
            PNG_sRGB_INTENT_RELATIVE);
        // write image info
        png_write_info(png_ptr, info_ptr);
        // should we flip endianness?
        long int a = 1;
        int swap = (*((unsigned char *) &a) == 1);
        if (swap) {
            png_set_swap(png_ptr);
        }
        // write image data
        png_write_image(png_ptr, (png_bytepp) row_pointers);
        // finish advancing file pointer to end of stream (useful?)
        png_write_end(png_ptr, NULL);
        // clean-up and we are done
        png_destroy_write_struct(&png_ptr, &info_ptr);
        free(data);
        free(row_pointers);
        return 1;
    }

    int store16(FILE *file, const image::RGBA &rgba) {
        FileWriter writer(file);
        return store<png_uint_16>(writer, rgba);
    }

    int store16(std::string &memory, const image::RGBA &rgba) {
        StringWriter writer(memory);
        return store<png_uint_16>(writer, rgba);
    }

    int store8(FILE *file, const image::RGBA &rgba) {
        FileWriter writer(file);
        return store<png_byte>(writer, rgba);
    }

    int store8(std::string &memory, const image::RGBA &rgba) {
        StringWriter writer(memory);
        return store<png_byte>(writer, rgba);
    }

} // namespaces pngio
