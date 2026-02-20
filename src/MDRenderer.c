#include "MDRenderer.h"
#include <cmark-gfm.h>
#include <cmark-gfm-core-extensions.h>

static void attach_extension(cmark_parser *parser, const char *name) {
    cmark_syntax_extension *ext = cmark_find_syntax_extension(name);
    if (ext)
        cmark_parser_attach_syntax_extension(parser, ext);
}

char *md_render_to_html(const char *markdown_text, size_t length) {
    static int registered = 0;
    if (!registered) {
        cmark_gfm_core_extensions_ensure_registered();
        registered = 1;
    }

    int options = CMARK_OPT_SMART | CMARK_OPT_GITHUB_PRE_LANG | CMARK_OPT_UNSAFE;

    cmark_parser *parser = cmark_parser_new(options);
    attach_extension(parser, "table");
    attach_extension(parser, "autolink");
    attach_extension(parser, "strikethrough");
    attach_extension(parser, "tagfilter");
    attach_extension(parser, "tasklist");

    cmark_parser_feed(parser, markdown_text, length);
    cmark_node *doc = cmark_parser_finish(parser);

    cmark_llist *extensions = cmark_parser_get_syntax_extensions(parser);
    char *html = cmark_render_html(doc, options, extensions);

    cmark_parser_free(parser);
    cmark_node_free(doc);

    return html;
}
