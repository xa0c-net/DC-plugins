/* Verify link handling: a click on a relative link to another Markdown file
 * renders that file in the same view (optionally scrolled to #anchor), an
 * in-page #anchor scrolls without leaving the page, and Cmd+[ goes back.
 * Usage: link_verify build/MarkdownView.wlx */
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <dlfcn.h>
typedef void *HWND;
typedef HWND (*ListLoad_t)(HWND, char *, int);

static WKWebView *gWeb;
static int gFail = 0;

static void Spin(double sec) {
    NSDate *dl = [NSDate dateWithTimeIntervalSinceNow:sec];
    while ([dl timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
}
static NSString *JS(NSString *js) {
    __block id out = nil; __block BOOL done = NO;
    [gWeb evaluateJavaScript:js completionHandler:^(id r, NSError *e) { out = r; done = YES; }];
    NSDate *dl = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done && [dl timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    return out ? [out description] : @"";
}
static void Expect(NSString *what, BOOL ok, NSString *got) {
    printf("%s: %s (%s)\n", ok ? "ok  " : "FAIL", what.UTF8String, got.UTF8String);
    if (!ok) gFail++;
}

int main(int argc, char **argv) { @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    void *h = dlopen(argv[1], RTLD_NOW);
    ListLoad_t ListLoad = (ListLoad_t)dlsym(h, "ListLoad");

    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat:@"mdlink-%d", getpid()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSMutableString *filler = [NSMutableString string];
    for (int i = 0; i < 80; i++) [filler appendString:@"filler paragraph\n\n"];
    NSString *a = [NSString stringWithFormat:
        @"# Doc A\n\n[to b](b.md)\n\n[to b section](b.md#second-section)\n\n[to intro](#intro)\n\n"
        @"[ext](https://example.invalid/)\n\n%@## Intro\n\ntext\n", filler];
    NSString *b = [NSString stringWithFormat:@"# Doc B\n\n%@## Second Section\n\ntext\n", filler];
    [a writeToFile:[dir stringByAppendingPathComponent:@"a.md"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [b writeToFile:[dir stringByAppendingPathComponent:@"b.md"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];

    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,600,400)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSString *apath = [dir stringByAppendingPathComponent:@"a.md"];
    HWND pw = ListLoad((__bridge HWND)win.contentView, (char *)apath.UTF8String, 0);
    NSView *view = (__bridge NSView *)pw;
    for (NSView *v in view.subviews) if ([v isKindOfClass:[WKWebView class]]) gWeb = (WKWebView *)v;
    [win makeKeyAndOrderFront:nil];
    Spin(2.0);

    Expect(@"A rendered", [JS(@"document.querySelector('h1').textContent") isEqualToString:@"Doc A"], JS(@"document.querySelector('h1').textContent"));
    Expect(@"heading got id", [JS(@"document.getElementById('intro')?'y':'n'") isEqualToString:@"y"], @"#intro");

    // in-page anchor: scrolls, stays on A
    JS(@"document.querySelector('a[href=\"#intro\"]').click(); 0");
    Spin(0.5);
    Expect(@"in-page anchor scrolled", [JS(@"window.scrollY") integerValue] > 200, JS(@"window.scrollY"));
    Expect(@"still on A", [JS(@"document.querySelector('h1').textContent") isEqualToString:@"Doc A"], @"h1");

    // link to b.md#second-section: renders B, scrolled to the anchor
    JS(@"document.querySelector('a[href=\"b.md#second-section\"]').click(); 0");
    Spin(2.0);
    Expect(@"B rendered", [JS(@"document.querySelector('h1').textContent") isEqualToString:@"Doc B"], JS(@"document.querySelector('h1').textContent"));
    Expect(@"B scrolled to anchor", [JS(@"window.scrollY") integerValue] > 200, JS(@"window.scrollY"));

    // Cmd+[ goes back to A
    NSEvent *ev = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:win.windowNumber
        context:nil characters:@"[" charactersIgnoringModifiers:@"[" isARepeat:NO keyCode:33];
    [gWeb keyDown:ev];
    Spin(2.0);
    Expect(@"back on A", [JS(@"document.querySelector('h1').textContent") isEqualToString:@"Doc A"], JS(@"document.querySelector('h1').textContent"));
    Expect(@"A scroll restored", [JS(@"window.scrollY") integerValue] > 200, JS(@"window.scrollY"));

    printf(gFail ? "RESULT: FAIL\n" : "RESULT: PASS\n");
    return gFail ? 1 : 0;
}}
