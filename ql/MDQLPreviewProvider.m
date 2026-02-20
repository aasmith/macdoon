#import "MDQLPreviewProvider.h"
#import "MDRenderer.h"
#import <cmark-gfm.h>
#import <cmark-gfm-core-extensions.h>

// Forward declarations for AST walking
static void renderNode(cmark_node *node, NSMutableAttributedString *result,
                       NSMutableDictionary *attrs, int listIndex);

static NSFont *bodyFont(void) {
    return [NSFont systemFontOfSize:13 weight:NSFontWeightRegular];
}

static NSFont *boldFont(void) {
    return [NSFont systemFontOfSize:13 weight:NSFontWeightBold];
}

static NSFont *italicFont(void) {
    return [[NSFontManager sharedFontManager] convertFont:bodyFont()
                                              toHaveTrait:NSItalicFontMask];
}

static NSFont *boldItalicFont(void) {
    return [[NSFontManager sharedFontManager] convertFont:boldFont()
                                              toHaveTrait:NSItalicFontMask];
}

static NSFont *monoFont(void) {
    NSFont *f = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    return f ?: [NSFont fontWithName:@"Menlo" size:12];
}

static NSFont *headingFont(int level) {
    CGFloat sizes[] = { 28, 22, 18, 16, 14, 13 };
    CGFloat size = (level >= 1 && level <= 6) ? sizes[level - 1] : 13;
    return [NSFont systemFontOfSize:size weight:NSFontWeightBold];
}

static NSColor *codeBackground(void) {
    return [NSColor colorWithCalibratedRed:0.94 green:0.95 blue:0.96 alpha:1.0];
}

static NSColor *linkColor(void) {
    return [NSColor linkColor];
}

static NSColor *quoteColor(void) {
    return [NSColor secondaryLabelColor];
}

static void appendString(NSMutableAttributedString *result, NSString *str,
                         NSDictionary *attributes) {
    NSAttributedString *as = [[NSAttributedString alloc] initWithString:str
                                                            attributes:attributes];
    [result appendAttributedString:as];
}

static void ensureNewline(NSMutableAttributedString *result) {
    if (result.length > 0) {
        unichar last = [[result string] characterAtIndex:result.length - 1];
        if (last != '\n') {
            appendString(result, @"\n", @{NSFontAttributeName: bodyFont()});
        }
    }
}

static void renderChildren(cmark_node *node, NSMutableAttributedString *result,
                           NSMutableDictionary *attrs, int listIndex) {
    cmark_node *child = cmark_node_first_child(node);
    int idx = listIndex;
    while (child) {
        renderNode(child, result, attrs, idx);
        if (cmark_node_get_type(child) == CMARK_NODE_ITEM) idx++;
        child = cmark_node_next(child);
    }
}

static void renderNode(cmark_node *node, NSMutableAttributedString *result,
                       NSMutableDictionary *attrs, int listIndex) {
    cmark_node_type type = cmark_node_get_type(node);

    switch (type) {
        case CMARK_NODE_DOCUMENT:
            renderChildren(node, result, attrs, 0);
            break;

        case CMARK_NODE_PARAGRAPH:
            renderChildren(node, result, attrs, 0);
            appendString(result, @"\n\n", @{NSFontAttributeName: bodyFont()});
            break;

        case CMARK_NODE_HEADING: {
            int level = cmark_node_get_heading_level(node);
            NSFont *prevFont = attrs[NSFontAttributeName];
            attrs[NSFontAttributeName] = headingFont(level);
            renderChildren(node, result, attrs, 0);
            appendString(result, @"\n\n", @{NSFontAttributeName: bodyFont()});
            if (prevFont) attrs[NSFontAttributeName] = prevFont;
            else [attrs removeObjectForKey:NSFontAttributeName];
            break;
        }

        case CMARK_NODE_TEXT: {
            const char *literal = cmark_node_get_literal(node);
            if (literal) {
                NSMutableDictionary *a = [attrs mutableCopy];
                if (!a[NSFontAttributeName]) a[NSFontAttributeName] = bodyFont();
                appendString(result, [NSString stringWithUTF8String:literal], a);
            }
            break;
        }

        case CMARK_NODE_SOFTBREAK:
            appendString(result, @" ", @{NSFontAttributeName: bodyFont()});
            break;

        case CMARK_NODE_LINEBREAK:
            appendString(result, @"\n", @{NSFontAttributeName: bodyFont()});
            break;

        case CMARK_NODE_CODE: {
            const char *literal = cmark_node_get_literal(node);
            if (literal) {
                NSMutableDictionary *a = [attrs mutableCopy];
                a[NSFontAttributeName] = monoFont();
                a[NSBackgroundColorAttributeName] = codeBackground();
                appendString(result, [NSString stringWithUTF8String:literal], a);
            }
            break;
        }

        case CMARK_NODE_CODE_BLOCK: {
            const char *literal = cmark_node_get_literal(node);
            if (literal) {
                NSMutableDictionary *a = [NSMutableDictionary dictionary];
                a[NSFontAttributeName] = monoFont();
                a[NSBackgroundColorAttributeName] = codeBackground();
                NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
                style.headIndent = 16;
                style.firstLineHeadIndent = 16;
                style.tailIndent = -16;
                a[NSParagraphStyleAttributeName] = style;
                appendString(result, [NSString stringWithUTF8String:literal], a);
                ensureNewline(result);
                appendString(result, @"\n", @{NSFontAttributeName: bodyFont()});
            }
            break;
        }

        case CMARK_NODE_EMPH: {
            NSFont *prevFont = attrs[NSFontAttributeName];
            BOOL wasBold = prevFont && ([prevFont.fontDescriptor symbolicTraits] & NSFontBoldTrait);
            attrs[NSFontAttributeName] = wasBold ? boldItalicFont() : italicFont();
            renderChildren(node, result, attrs, 0);
            if (prevFont) attrs[NSFontAttributeName] = prevFont;
            else [attrs removeObjectForKey:NSFontAttributeName];
            break;
        }

        case CMARK_NODE_STRONG: {
            NSFont *prevFont = attrs[NSFontAttributeName];
            BOOL wasItalic = prevFont && ([prevFont.fontDescriptor symbolicTraits] & NSFontItalicTrait);
            attrs[NSFontAttributeName] = wasItalic ? boldItalicFont() : boldFont();
            renderChildren(node, result, attrs, 0);
            if (prevFont) attrs[NSFontAttributeName] = prevFont;
            else [attrs removeObjectForKey:NSFontAttributeName];
            break;
        }

        case CMARK_NODE_LINK: {
            const char *url = cmark_node_get_url(node);
            NSColor *prevColor = attrs[NSForegroundColorAttributeName];
            if (url) {
                attrs[NSLinkAttributeName] = [NSString stringWithUTF8String:url];
                attrs[NSForegroundColorAttributeName] = linkColor();
            }
            renderChildren(node, result, attrs, 0);
            [attrs removeObjectForKey:NSLinkAttributeName];
            if (prevColor) attrs[NSForegroundColorAttributeName] = prevColor;
            else [attrs removeObjectForKey:NSForegroundColorAttributeName];
            break;
        }

        case CMARK_NODE_IMAGE: {
            // Just show alt text
            const char *alt = cmark_node_get_title(node);
            if (!alt) alt = cmark_node_get_url(node);
            if (alt) {
                NSMutableDictionary *a = [attrs mutableCopy];
                if (!a[NSFontAttributeName]) a[NSFontAttributeName] = bodyFont();
                a[NSForegroundColorAttributeName] = [NSColor secondaryLabelColor];
                appendString(result, [NSString stringWithFormat:@"[image: %s]",alt], a);
            }
            break;
        }

        case CMARK_NODE_BLOCK_QUOTE: {
            NSColor *prevColor = attrs[NSForegroundColorAttributeName];
            attrs[NSForegroundColorAttributeName] = quoteColor();
            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
            style.headIndent = 20;
            style.firstLineHeadIndent = 20;
            attrs[NSParagraphStyleAttributeName] = style;
            renderChildren(node, result, attrs, 0);
            [attrs removeObjectForKey:NSParagraphStyleAttributeName];
            if (prevColor) attrs[NSForegroundColorAttributeName] = prevColor;
            else [attrs removeObjectForKey:NSForegroundColorAttributeName];
            break;
        }

        case CMARK_NODE_LIST: {
            int start = cmark_node_get_list_start(node);
            renderChildren(node, result, attrs, start);
            break;
        }

        case CMARK_NODE_ITEM: {
            cmark_node *parent = cmark_node_parent(node);
            cmark_list_type lt = cmark_node_get_list_type(parent);
            NSString *bullet;
            if (lt == CMARK_ORDERED_LIST) {
                bullet = [NSString stringWithFormat:@"  %d. ", listIndex];
            } else {
                bullet = @"  \u2022 ";
            }
            appendString(result, bullet, @{NSFontAttributeName: bodyFont()});
            renderChildren(node, result, attrs, 0);
            break;
        }

        case CMARK_NODE_THEMATIC_BREAK: {
            appendString(result, @"\n\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n\n",
                @{NSFontAttributeName: bodyFont(),
                  NSForegroundColorAttributeName: [NSColor separatorColor]});
            break;
        }

        case CMARK_NODE_HTML_BLOCK:
        case CMARK_NODE_HTML_INLINE: {
            // Render raw HTML as-is (fallback)
            const char *literal = cmark_node_get_literal(node);
            if (literal) {
                NSMutableDictionary *a = [attrs mutableCopy];
                if (!a[NSFontAttributeName]) a[NSFontAttributeName] = bodyFont();
                appendString(result, [NSString stringWithUTF8String:literal], a);
            }
            break;
        }

        default:
            // For any extension nodes (tables, strikethrough, tasklist), fall through
            renderChildren(node, result, attrs, 0);
            break;
    }
}

@implementation MDQLPreviewProvider

- (void)loadView {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSTextView *textView = [[NSTextView alloc] initWithFrame:scrollView.bounds];
    textView.editable = NO;
    textView.selectable = YES;
    textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    textView.textContainerInset = NSMakeSize(20, 20);
    textView.textContainer.widthTracksTextView = YES;
    textView.drawsBackground = YES;

    scrollView.documentView = textView;
    self.view = scrollView;
}

- (void)preparePreviewOfFileAtURL:(NSURL *)url
                completionHandler:(void (^)(NSError * _Nullable))handler {

    NSError *error = nil;
    NSString *markdown = [NSString stringWithContentsOfURL:url
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (!markdown) {
        handler(error);
        return;
    }

    // Parse with cmark-gfm
    static int registered = 0;
    if (!registered) {
        cmark_gfm_core_extensions_ensure_registered();
        registered = 1;
    }

    int options = CMARK_OPT_SMART;
    cmark_parser *parser = cmark_parser_new(options);

    const char *extNames[] = {"table", "autolink", "strikethrough", "tagfilter", "tasklist"};
    for (int i = 0; i < 5; i++) {
        cmark_syntax_extension *ext = cmark_find_syntax_extension(extNames[i]);
        if (ext) cmark_parser_attach_syntax_extension(parser, ext);
    }

    const char *utf8 = [markdown UTF8String];
    cmark_parser_feed(parser, utf8, strlen(utf8));
    cmark_node *doc = cmark_parser_finish(parser);

    // Walk AST → NSAttributedString
    NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] init];
    NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
    renderNode(doc, attrStr, attrs, 0);

    cmark_parser_free(parser);
    cmark_node_free(doc);

    // Display
    NSScrollView *scrollView = (NSScrollView *)self.view;
    NSTextView *textView = scrollView.documentView;
    [[textView textStorage] setAttributedString:attrStr];

    handler(nil);
}

@end
