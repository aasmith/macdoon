#import <Cocoa/Cocoa.h>
#import <unistd.h>
#import "MDAppDelegate.h"

NSString *g_stdinContent = nil;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        // Read piped stdin BEFORE starting the run loop
        if (!isatty(fileno(stdin))) {
            NSFileHandle *input = [NSFileHandle fileHandleWithStandardInput];
            NSData *data = [input readDataToEndOfFile];
            if (data.length > 0) {
                g_stdinContent = [[NSString alloc] initWithData:data
                                                       encoding:NSUTF8StringEncoding];
            }
        }

        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        MDAppDelegate *delegate = [[MDAppDelegate alloc] init];
        [app setDelegate:delegate];

        [app run];
    }
    return 0;
}
