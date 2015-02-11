#ifndef PNGIO_H
#define PNGIO_H

#include <string>
#include "image.h"

namespace pngio {
    // for png comments
    void free_text(void);
    void init_text(int argc, char **argv);
    void push_text(const char *key, const char *text);
    void pop_text(int n = 1);
    // load and store
    int load(FILE *file, image::RGBA &rgba);
    int load(const std::string &memory, image::RGBA &rgba);
    // output in 16-bit per channel
    int store16(FILE *file, const image::RGBA &rgba);
    int store16(std::string &memory, const image::RGBA &rgba);
    // output in 8-bit per channel
    int store8(FILE *file, const image::RGBA &rgba);
    int store8(std::string &memory, const image::RGBA &rgba);

} // namespace pngio

#endif // PNGIO_H
