#import "MDWindowController.h"
#import "MDHTMLTemplate.h"
#import "MDRenderer.h"
#import <WebKit/WebKit.h>

@interface MDWindowController () <NSDraggingDestination>

@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSString *cssString;
@property (nonatomic, strong) dispatch_source_t watchSource;
@property (nonatomic, assign) BOOL initialLoadDone;

@end

@implementation MDWindowController

- (instancetype)initWithFilePath:(NSString *)filePath {
    self = [super initWithWindow:nil];
    if (self) {
        _filePath = [filePath copy];
        [self setupWindow];
        [self loadCSS];
        [self reloadContent];
        [self startWatchingFile];
    }
    return self;
}

- (instancetype)initWithString:(NSString *)markdown title:(NSString *)title {
    self = [super initWithWindow:nil];
    if (self) {
        [self setupWindow];
        [self.window setTitle:title];
        [self loadCSS];
        [self renderMarkdown:markdown baseURL:nil];
    }
    return self;
}

- (void)setupWindow {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 820, 900)
                  styleMask:(NSWindowStyleMaskTitled |
                             NSWindowStyleMaskClosable |
                             NSWindowStyleMaskMiniaturizable |
                             NSWindowStyleMaskResizable)
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setMinSize:NSMakeSize(400, 300)];
    [window center];

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    _webView = [[WKWebView alloc] initWithFrame:window.contentView.bounds
                                  configuration:config];
    _webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_webView setValue:@NO forKey:@"drawsBackground"];
    [window.contentView addSubview:_webView];

    [window registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    window.delegate = (id<NSWindowDelegate>)self;

    self.window = window;
}

- (void)loadCSS {
    // Try mainBundle first (works when launched via open / Finder)
    NSString *cssPath = [[NSBundle mainBundle] pathForResource:@"github-markdown"
                                                       ofType:@"css"];

    // Fallback: resolve from executable path (works when launched as bare binary / symlink)
    if (!cssPath) {
        NSString *execPath = [[NSProcessInfo processInfo] arguments][0];
        // Resolve symlinks: /usr/local/bin/macdoon -> .../Macdoon.app/Contents/MacOS/macdoon
        execPath = [[NSFileManager defaultManager]
                    destinationOfSymbolicLinkAtPath:execPath error:nil] ?: execPath;
        // Walk up: MacOS/ -> Contents/ -> Resources/
        NSString *contentsDir = [[execPath stringByDeletingLastPathComponent]
                                 stringByDeletingLastPathComponent];
        NSString *candidate = [[contentsDir stringByAppendingPathComponent:@"Resources"]
                               stringByAppendingPathComponent:@"github-markdown.css"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            cssPath = candidate;
        }
    }

    if (cssPath) {
        _cssString = [NSString stringWithContentsOfFile:cssPath
                                               encoding:NSUTF8StringEncoding
                                                  error:nil];
    }
    if (!_cssString) {
        _cssString = @"";
    }
}

#pragma mark - Rendering

- (void)renderMarkdown:(NSString *)markdown baseURL:(NSURL *)baseURL {
    const char *utf8 = [markdown UTF8String];
    char *html_body = md_render_to_html(utf8, strlen(utf8));
    NSString *body = [NSString stringWithUTF8String:html_body];
    free(html_body);

    if (baseURL) {
        body = [self embedLocalImages:body baseURL:baseURL];
    }

    if (_initialLoadDone) {
        // Update innerHTML to avoid white flash and preserve scroll
        NSString *escaped = [self jsonEscapeString:body];
        NSString *js = [NSString stringWithFormat:
            @"(function(){"
            @"var sy=window.scrollY;"
            @"document.querySelector('.markdown-body').innerHTML=%@;"
            @"window.scrollTo(0,sy);"
            @"})()", escaped];
        [_webView evaluateJavaScript:js completionHandler:nil];
    } else {
        NSString *fullHTML = [NSString stringWithFormat:MDHTMLTemplate,
                              _cssString, body];
        [_webView loadHTMLString:fullHTML baseURL:baseURL];
        _initialLoadDone = YES;
    }
}

- (NSString *)jsonEscapeString:(NSString *)string {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[string]
                                                  options:0
                                                    error:nil];
    NSString *json = [[NSString alloc] initWithData:data
                                           encoding:NSUTF8StringEncoding];
    // json is ["..."], extract the string value (with quotes)
    return [json substringWithRange:NSMakeRange(1, json.length - 2)];
}

- (NSString *)embedLocalImages:(NSString *)html baseURL:(NSURL *)baseURL {
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"<img\\s+src=\"([^\"]+)\""
                             options:0 error:nil];
    NSMutableString *result = [html mutableCopy];
    NSArray *matches = [regex matchesInString:result options:0
                                        range:NSMakeRange(0, result.length)];
    // Replace from end to start to preserve character offsets
    for (NSTextCheckingResult *match in [matches reverseObjectEnumerator]) {
        NSRange srcRange = [match rangeAtIndex:1];
        NSString *src = [result substringWithRange:srcRange];

        // Skip absolute URLs and data URIs
        if ([src hasPrefix:@"http://"] || [src hasPrefix:@"https://"] ||
            [src hasPrefix:@"data:"]) continue;

        NSURL *imageURL = [NSURL URLWithString:src relativeToURL:baseURL];
        if (!imageURL) imageURL = [baseURL URLByAppendingPathComponent:src];
        NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
        if (!imageData) continue;

        NSString *ext = [src pathExtension].lowercaseString;
        NSString *mime = @"image/png";
        if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
            mime = @"image/jpeg";
        else if ([ext isEqualToString:@"gif"])  mime = @"image/gif";
        else if ([ext isEqualToString:@"svg"])  mime = @"image/svg+xml";
        else if ([ext isEqualToString:@"webp"]) mime = @"image/webp";

        NSString *base64 = [imageData base64EncodedStringWithOptions:0];
        NSString *dataURI = [NSString stringWithFormat:@"data:%@;base64,%@",
                             mime, base64];
        [result replaceCharactersInRange:srcRange withString:dataURI];
    }
    return result;
}

- (void)reloadContent {
    if (!_filePath) return;

    NSError *error = nil;
    NSString *markdown = [NSString stringWithContentsOfFile:_filePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
    if (!markdown) {
        markdown = [NSString stringWithFormat:@"*Error reading file:* %@",
                    error.localizedDescription];
    }

    NSString *title = [_filePath lastPathComponent];
    [self.window setTitle:title];
    [self.window setRepresentedFilename:_filePath];

    NSURL *baseURL = [[NSURL fileURLWithPath:_filePath] URLByDeletingLastPathComponent];
    [self renderMarkdown:markdown baseURL:baseURL];
}

#pragma mark - File Watching

- (void)startWatchingFile {
    if (!_filePath) return;

    int fd = open([_filePath fileSystemRepresentation], O_EVTONLY);
    if (fd < 0) return;

    _watchSource = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_VNODE, fd,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME,
        dispatch_get_main_queue());

    __weak typeof(self) weakSelf = self;

    dispatch_source_set_event_handler(_watchSource, ^{
        unsigned long flags = dispatch_source_get_data(weakSelf.watchSource);
        if (flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) {
            // File was replaced (editor atomic save)
            [weakSelf stopWatching];
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                dispatch_get_main_queue(), ^{
                    [weakSelf reloadContent];
                    [weakSelf startWatchingFile];
                });
        } else {
            [weakSelf reloadContent];
        }
    });

    dispatch_source_set_cancel_handler(_watchSource, ^{
        close(fd);
    });

    dispatch_resume(_watchSource);
}

- (void)stopWatching {
    if (_watchSource) {
        dispatch_source_cancel(_watchSource);
        _watchSource = nil;
    }
}

#pragma mark - Drag and Drop

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = [sender draggingPasteboard];
    if ([pb canReadObjectForClasses:@[[NSURL class]]
                            options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}]) {
        return NSDragOperationCopy;
    }
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSPasteboard *pb = [sender draggingPasteboard];
    NSArray<NSURL *> *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                               options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count == 0) return NO;

    // Post notification so app delegate can open the files
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"MDOpenFilesNotification"
                      object:nil
                    userInfo:@{@"urls": urls}];
    return YES;
}

#pragma mark - Cleanup

- (void)dealloc {
    [self stopWatching];
}

@end
