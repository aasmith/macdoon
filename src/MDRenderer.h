#ifndef MD_RENDERER_H
#define MD_RENDERER_H

#include <stddef.h>

// Returns a malloc'd HTML string. Caller must free().
char *md_render_to_html(const char *markdown_text, size_t length);

#endif
