#import "MDQLPreviewProvider.h"
#import "MDRenderer.h"
#import <cmark-gfm.h>
#import <cmark-gfm-core-extensions.h>

// Simplified HTML template for NSAttributedString (which has limited CSS support).
// Uses inline-friendly styles instead of the complex GitHub CSS.
static NSString *const QLHTMLTemplate =
    @"<!DOCTYPE html>\n"
    @"<html>\n"
    @"<head>\n"
    @"<meta charset=\"utf-8\">\n"
    @"<style>\n"
    @"body {\n"
    @"  font-family: -apple-system, 'Helvetica Neue', Helvetica, Arial, sans-serif;\n"
    @"  font-size: 15px;\n"
    @"  line-height: 1.6;\n"
    @"  color: #1f2328;\n"
    @"  background-color: #ffffff;\n"
    @"}\n"
    @"h1 { font-size: 28px; font-weight: bold; margin-top: 32px; margin-bottom: 16px; }\n"
    @"h2 { font-size: 22px; font-weight: bold; margin-top: 32px; margin-bottom: 16px; }\n"
    @"h3 { font-size: 18px; font-weight: bold; margin-top: 24px; margin-bottom: 12px; }\n"
    @"h4 { font-size: 15px; font-weight: bold; margin-top: 24px; margin-bottom: 12px; }\n"
    @"p  { margin-top: 0; margin-bottom: 16px; }\n"
    @"ul, ol { margin-top: 0; margin-bottom: 16px; }\n"
    @"li { margin-bottom: 4px; }\n"
    @"blockquote { color: #656d76; margin-left: 0; margin-right: 0; margin-bottom: 16px; padding-left: 16px; }\n"
    @"pre { font-family: Menlo, Consolas, monospace; font-size: 13px;\n"
    @"       background-color: #f6f8fa; padding: 16px; margin-top: 0; margin-bottom: 24px; }\n"
    @"code { font-family: Menlo, Consolas, monospace; font-size: 13px;\n"
    @"        background-color: #eff1f3; }\n"
    @"pre code { background-color: transparent; }\n"
    @"table { border-collapse: collapse; margin-bottom: 16px; }\n"
    @"th, td { border: 1px solid #d1d9e0; padding: 8px 16px; }\n"
    @"th { background-color: #f6f8fa; font-weight: bold; }\n"
    @"a { color: #0969da; }\n"
    @"img { max-width: 600px; }\n"
    @"del { color: #656d76; }\n"
    @"</style>\n"
    @"</head>\n"
    @"<body>\n%@\n</body>\n"
    @"</html>";

@implementation MDQLPreviewProvider

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
}

- (void)preparePreviewOfFileAtURL:(NSURL *)url
                completionHandler:(void (^)(NSError * _Nullable))handler {

    BOOL accessGranted = [url startAccessingSecurityScopedResource];

    NSError *error = nil;
    NSString *markdown = [NSString stringWithContentsOfURL:url
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (!markdown) {
        if (accessGranted) [url stopAccessingSecurityScopedResource];
        handler(error);
        return;
    }

    // Render markdown to HTML
    const char *utf8 = [markdown UTF8String];
    char *html_body = md_render_to_html(utf8, strlen(utf8));
    NSString *body = [NSString stringWithUTF8String:html_body];
    free(html_body);

    // NSAttributedString has limited CSS support, so fix up the HTML directly:
    // 1. Add spacing after code blocks (ignores margin on <pre>)
    body = [body stringByReplacingOccurrencesOfString:@"</pre>"
                                           withString:@"</pre><p>&nbsp;</p>"];
    // 2. Replace heading underlines and <hr> with markers (rendered as
    //    NSTextAttachment line images after HTML parsing)
    body = [body stringByReplacingOccurrencesOfString:@"</h1>"
                                           withString:@"</h1>MDRULE_MARKER\n"];
    body = [body stringByReplacingOccurrencesOfString:@"</h2>"
                                           withString:@"</h2>MDRULE_MARKER\n"];
    body = [body stringByReplacingOccurrencesOfString:@"<hr />"
                                           withString:@"MDRULE_MARKER\n"];

    // Extract local images and replace <img> tags with markers
    NSURL *baseURL = [url URLByDeletingLastPathComponent];
    NSMutableArray<NSImage *> *collectedImages = [NSMutableArray new];
    body = [self extractImages:body baseURL:baseURL into:collectedImages];

    if (accessGranted) [url stopAccessingSecurityScopedResource];

    // Build HTML with QL-specific simplified styles
    NSString *fullHTML = [NSString stringWithFormat:QLHTMLTemplate, body];

    // Parse HTML into NSAttributedString
    NSData *htmlData = [fullHTML dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *opts = @{
        NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType,
        NSCharacterEncodingDocumentAttribute: @(NSUTF8StringEncoding)
    };
    NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc]
        initWithHTML:htmlData options:opts documentAttributes:nil];

    if (!attrStr) {
        attrStr = [[NSMutableAttributedString alloc] initWithString:markdown];
    }

    // Increase line spacing (NSAttributedString ignores CSS line-height)
    [attrStr enumerateAttribute:NSParagraphStyleAttributeName
                        inRange:NSMakeRange(0, attrStr.length)
                        options:0
                     usingBlock:^(NSParagraphStyle *style, NSRange range, BOOL *stop) {
        NSMutableParagraphStyle *newStyle = style
            ? [style mutableCopy]
            : [[NSMutableParagraphStyle alloc] init];
        newStyle.lineSpacing = 4.0;
        newStyle.paragraphSpacing = 8.0;
        [attrStr addAttribute:NSParagraphStyleAttributeName
                        value:newStyle
                        range:range];
    }];

    // Replace rule markers with a thin line image attachment
    {
        NSImage *lineImg = [[NSImage alloc] initWithSize:NSMakeSize(4, 16)];
        [lineImg lockFocus];
        [[NSColor colorWithRed:0.82 green:0.84 blue:0.87 alpha:1.0] set];
        NSRectFill(NSMakeRect(0, 7, 4, 2));
        [lineImg unlockFocus];

        while (YES) {
            NSRange r = [attrStr.string rangeOfString:@"MDRULE_MARKER"];
            if (r.location == NSNotFound) break;

            NSTextAttachment *att = [[NSTextAttachment alloc] init];
            att.image = lineImg;
            att.bounds = CGRectMake(0, 0, 10000, 16);

            NSAttributedString *lineStr =
                [NSAttributedString attributedStringWithAttachment:att];
            [attrStr replaceCharactersInRange:r withAttributedString:lineStr];
        }
    }

    // Replace text markers with NSTextAttachment images
    for (NSInteger i = (NSInteger)collectedImages.count - 1; i >= 0; i--) {
        NSString *marker = [NSString stringWithFormat:@"MDIMG_%ld_MARKER", (long)i];
        NSRange range = [attrStr.string rangeOfString:marker];
        if (range.location == NSNotFound) continue;

        NSImage *image = collectedImages[i];
        NSSize size = image.size;
        CGFloat maxWidth = 600.0;
        if (size.width > maxWidth) {
            CGFloat scale = maxWidth / size.width;
            size = NSMakeSize(size.width * scale, size.height * scale);
        }

        NSTextAttachment *att = [[NSTextAttachment alloc] init];
        att.image = image;
        att.bounds = CGRectMake(0, 0, size.width, size.height);

        NSAttributedString *imgStr =
            [NSAttributedString attributedStringWithAttachment:att];
        [attrStr replaceCharactersInRange:range withAttributedString:imgStr];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        NSScrollView *scrollView = [[NSScrollView alloc]
            initWithFrame:self.view.bounds];
        scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scrollView.hasVerticalScroller = YES;
        scrollView.hasHorizontalScroller = NO;
        scrollView.drawsBackground = YES;
        scrollView.backgroundColor = [NSColor whiteColor];

        NSTextView *textView = [[NSTextView alloc]
            initWithFrame:scrollView.contentView.bounds];
        textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        textView.editable = NO;
        textView.selectable = YES;
        textView.drawsBackground = YES;
        textView.backgroundColor = [NSColor whiteColor];
        textView.textContainerInset = NSMakeSize(48, 28);
        textView.textContainer.lineFragmentPadding = 0;
        [textView.textStorage setAttributedString:attrStr];

        scrollView.documentView = textView;
        [self.view addSubview:scrollView];

        handler(nil);
    });
}

#pragma mark - Image Extraction

- (NSString *)extractImages:(NSString *)html
                    baseURL:(NSURL *)baseURL
                       into:(NSMutableArray<NSImage *> *)images {
    if (!baseURL) return html;

    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<img[^>]+src=\"([^\"]+)\"[^>]*/>"
                             options:0 error:nil];
    NSMutableString *result = [html mutableCopy];
    NSArray *matches = [regex matchesInString:result options:0
                                        range:NSMakeRange(0, result.length)];

    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSRange fullRange = [match rangeAtIndex:0];
        NSRange srcRange  = [match rangeAtIndex:1];
        NSString *src = [result substringWithRange:srcRange];

        // Skip remote images
        if ([src hasPrefix:@"http://"] || [src hasPrefix:@"https://"] ||
            [src hasPrefix:@"data:"]) {
            [result replaceCharactersInRange:fullRange withString:@""];
            continue;
        }

        NSURL *imageURL = [NSURL URLWithString:src relativeToURL:baseURL];
        if (!imageURL) imageURL = [baseURL URLByAppendingPathComponent:src];
        NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
        NSImage *image = imageData ? [[NSImage alloc] initWithData:imageData] : nil;

        if (image) {
            [images insertObject:image atIndex:0];
            [result replaceCharactersInRange:fullRange withString:@"__MDIMG_PLACEHOLDER__"];
        } else {
            [result replaceCharactersInRange:fullRange withString:@""];
        }
    }

    // Renumber markers in document order
    NSUInteger idx = 0;
    while (YES) {
        NSRange r = [result rangeOfString:@"__MDIMG_PLACEHOLDER__"];
        if (r.location == NSNotFound) break;
        NSString *marker = [NSString stringWithFormat:@"MDIMG_%lu_MARKER",
                            (unsigned long)idx];
        [result replaceCharactersInRange:r withString:marker];
        idx++;
    }

    return result;
}

@end
