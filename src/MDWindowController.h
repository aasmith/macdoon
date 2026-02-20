#import <Cocoa/Cocoa.h>

@interface MDWindowController : NSWindowController

- (instancetype)initWithFilePath:(NSString *)filePath;
- (instancetype)initWithString:(NSString *)markdown title:(NSString *)title;

@end
