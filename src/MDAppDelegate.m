#import "MDAppDelegate.h"
#import "MDWindowController.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

extern NSString *g_stdinContent;

@interface MDAppDelegate ()

@property (nonatomic, strong) NSMutableArray<MDWindowController *> *windowControllers;

@end

@implementation MDAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _windowControllers = [NSMutableArray new];

    [self buildMenuBar];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleOpenFiles:)
               name:@"MDOpenFilesNotification"
             object:nil];

    // Handle stdin content
    if (g_stdinContent) {
        [self openString:g_stdinContent title:@"stdin"];
        return;
    }

    // Handle command-line file arguments
    NSArray *args = [[NSProcessInfo processInfo] arguments];
    BOOL openedFile = NO;
    for (NSUInteger i = 1; i < args.count; i++) {
        NSString *arg = args[i];
        if ([arg hasPrefix:@"-"]) continue; // skip flags
        NSString *path = [arg stringByStandardizingPath];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            // Try resolving relative to cwd
            path = [[[NSFileManager defaultManager] currentDirectoryPath]
                    stringByAppendingPathComponent:arg];
            path = [path stringByStandardizingPath];
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [self openFilePath:path];
            openedFile = YES;
        }
    }

    // If no file was opened by any mechanism and no stdin, just wait.
    // application:openFile: may fire after this for double-click / Open With.
    (void)openedFile;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    return NO;
}

#pragma mark - File Opening

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    [self openFilePath:filename];
    return YES;
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
    for (NSString *filename in filenames) {
        [self openFilePath:filename];
    }
    [sender replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (void)openFilePath:(NSString *)path {
    MDWindowController *wc = [[MDWindowController alloc] initWithFilePath:path];
    [_windowControllers addObject:wc];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowWillClose:)
               name:NSWindowWillCloseNotification
             object:wc.window];

    [wc showWindow:nil];
}

- (void)openString:(NSString *)markdown title:(NSString *)title {
    MDWindowController *wc = [[MDWindowController alloc] initWithString:markdown
                                                                 title:title];
    [_windowControllers addObject:wc];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowWillClose:)
               name:NSWindowWillCloseNotification
             object:wc.window];

    [wc showWindow:nil];
}

- (void)handleOpenFiles:(NSNotification *)notification {
    NSArray<NSURL *> *urls = notification.userInfo[@"urls"];
    for (NSURL *url in urls) {
        if ([url isFileURL]) {
            [self openFilePath:url.path];
        }
    }
}

#pragma mark - Window Lifecycle

- (void)windowWillClose:(NSNotification *)notification {
    NSWindow *closedWindow = notification.object;
    NSMutableArray *toRemove = [NSMutableArray new];
    for (MDWindowController *wc in _windowControllers) {
        if (wc.window == closedWindow) {
            [toRemove addObject:wc];
        }
    }
    [_windowControllers removeObjectsInArray:toRemove];
}

#pragma mark - Menu Bar

- (void)buildMenuBar {
    NSMenu *menuBar = [[NSMenu alloc] init];

    // App menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About Macdoon"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Install Command Line Tool\u2026"
                       action:@selector(installCLI:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Macdoon"
                       action:@selector(terminate:)
                keyEquivalent:@"q"];
    [appMenuItem setSubmenu:appMenu];
    [menuBar addItem:appMenuItem];

    // File menu
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Open\u2026"
                        action:@selector(openDocument:)
                 keyEquivalent:@"o"];
    [fileMenu addItemWithTitle:@"Close Window"
                        action:@selector(performClose:)
                 keyEquivalent:@"w"];
    [fileMenuItem setSubmenu:fileMenu];
    [menuBar addItem:fileMenuItem];

    // Edit menu (for Cmd+C, etc.)
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Copy"
                        action:@selector(copy:)
                 keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Select All"
                        action:@selector(selectAll:)
                 keyEquivalent:@"a"];
    [editMenuItem setSubmenu:editMenu];
    [menuBar addItem:editMenuItem];

    // Window menu
    NSMenuItem *windowMenuItem = [[NSMenuItem alloc] init];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize"
                          action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom"
                          action:@selector(performZoom:)
                   keyEquivalent:@""];
    [windowMenuItem setSubmenu:windowMenu];
    [menuBar addItem:windowMenuItem];
    [NSApp setWindowsMenu:windowMenu];

    [NSApp setMainMenu:menuBar];
}

#pragma mark - Actions

- (void)openDocument:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = YES;
    panel.canChooseDirectories = NO;
    panel.allowedContentTypes = @[
        [UTType typeWithFilenameExtension:@"md"],
        [UTType typeWithFilenameExtension:@"markdown"],
        [UTType typeWithFilenameExtension:@"mdown"],
        [UTType typeWithFilenameExtension:@"mkdn"],
        [UTType typeWithFilenameExtension:@"mkd"],
        [UTType typeWithIdentifier:@"public.plain-text"],
    ];

    [panel beginWithCompletionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            for (NSURL *url in panel.URLs) {
                [self openFilePath:url.path];
            }
        }
    }];
}

#pragma mark - CLI Install

- (void)installCLI:(id)sender {
    NSString *binDir = @"/usr/local/bin";
    NSString *linkPath = [binDir stringByAppendingPathComponent:@"macdoon"];
    NSString *targetPath = [[NSBundle mainBundle] executablePath];

    // Check if already installed and pointing to us
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:linkPath error:nil];
    if (attrs && [attrs[NSFileType] isEqual:NSFileTypeSymbolicLink]) {
        NSString *dest = [fm destinationOfSymbolicLinkAtPath:linkPath error:nil];
        if ([dest isEqualToString:targetPath]) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Already Installed";
            alert.informativeText = [NSString stringWithFormat:
                @"The macdoon command line tool is already installed at %@.", linkPath];
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
            return;
        }
    }

    // Confirm
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Install Command Line Tool?";
    confirm.informativeText = [NSString stringWithFormat:
        @"This will create a symlink at %@ pointing to the current app binary.\n\n"
        @"You\u2019ll be able to run:\n"
        @"  macdoon README.md\n"
        @"  cat file.md | macdoon\n\n"
        @"Administrator privileges may be required.", linkPath];
    [confirm addButtonWithTitle:@"Install"];
    [confirm addButtonWithTitle:@"Cancel"];

    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    // Try direct symlink first (works if /usr/local/bin is writable)
    [fm createDirectoryAtPath:binDir withIntermediateDirectories:YES
                   attributes:nil error:nil];
    [fm removeItemAtPath:linkPath error:nil];

    NSError *error = nil;
    if ([fm createSymbolicLinkAtPath:linkPath withDestinationPath:targetPath error:&error]) {
        [self showCLIInstallSuccess:linkPath];
        return;
    }

    // Needs privilege escalation -- use osascript to run with admin
    NSString *script = [NSString stringWithFormat:
        @"do shell script "
        @"\"mkdir -p %@ && ln -sf '%@' '%@'\" "
        @"with administrator privileges",
        binDir, targetPath, linkPath];

    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:script];
    NSDictionary *errorDict = nil;
    [appleScript executeAndReturnError:&errorDict];

    if (errorDict) {
        // User cancelled the auth dialog or it failed
        if ([errorDict[@"NSAppleScriptErrorNumber"] integerValue] == -128) {
            return; // user cancelled
        }
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"Installation Failed";
        alert.informativeText = errorDict[@"NSAppleScriptErrorMessage"]
            ?: @"Could not create the symlink.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
        return;
    }

    [self showCLIInstallSuccess:linkPath];
}

- (void)showCLIInstallSuccess:(NSString *)linkPath {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Command Line Tool Installed";
    alert.informativeText = [NSString stringWithFormat:
        @"The macdoon command is now available at %@.\n\n"
        @"Usage:\n"
        @"  macdoon README.md\n"
        @"  cat file.md | macdoon", linkPath];
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

@end
