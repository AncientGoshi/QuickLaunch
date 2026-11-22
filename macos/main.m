#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

extern char *ql_targets(const unsigned char *data, size_t len, bool launch, size_t *count);
extern void ql_free_error(char *message);

static NSString *const TargetsKey = @"LaunchTargets";
static NSString *const StartupKey = @"OpenOnStartup";
static const EventHotKeyID ShortcutID = {0x516c6e63, 1}; // Qlnc

static NSString *CallCore(NSData *data, bool launch, size_t *count) {
    char *message = ql_targets(data.bytes, data.length, launch, count);
    if (!message) return nil;
    NSString *result = [NSString stringWithUTF8String:message] ?: @"An unknown error occurred.";
    ql_free_error(message);
    return result;
}

static void Activate(void) {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 140000
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
        return;
    }
#endif
    [NSApp activateIgnoringOtherApps:YES];
}

static OSStatus RegisterShortcut(EventHotKeyRef *shortcut) {
    return RegisterEventHotKey(kVK_F12, cmdKey, ShortcutID, GetApplicationEventTarget(),
                              kEventHotKeyExclusive, shortcut);
}

@interface QuickLaunch : NSObject <NSApplicationDelegate>
@property(strong) NSStatusItem *statusItem;
@property(strong) NSMenuItem *shortcutStatus;
@property(strong) NSWindow *settings;
@property(strong) NSTextView *editor;
@property(strong) NSTextField *feedback;
@property(strong) NSButton *startup;
@property(assign) EventHotKeyRef shortcut;
@property(assign) EventHandlerRef handler;
@property(assign) BOOL opening;
- (void)openTargets:(id)sender;
@end

static OSStatus HandleShortcut(EventHandlerCallRef next, EventRef event, void *context) {
    (void)next;
    EventHotKeyID received = {0};
    OSStatus status = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID,
                                       NULL, sizeof received, NULL, &received);
    if (status != noErr || received.signature != ShortcutID.signature || received.id != ShortcutID.id) {
        return eventNotHandledErr;
    }
    [(__bridge QuickLaunch *)context openTargets:nil];
    return noErr;
}

@implementation QuickLaunch
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"⌘F12";
    self.statusItem.button.toolTip = @"QuickLaunch";
    self.statusItem.button.accessibilityLabel = @"QuickLaunch";

    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *run = [menu addItemWithTitle:@"Open Saved Targets" action:@selector(openTargets:) keyEquivalent:@""];
    run.target = self;
    NSMenuItem *edit = [menu addItemWithTitle:@"Edit Targets…" action:@selector(editTargets:) keyEquivalent:@""];
    edit.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    self.shortcutStatus = [menu addItemWithTitle:@"⌘F12 is active" action:nil keyEquivalent:@""];
    [menu addItemWithTitle:@"Quit QuickLaunch" action:@selector(terminate:) keyEquivalent:@"q"].target = NSApp;
    self.statusItem.menu = menu;

    const EventTypeSpec event = {kEventClassKeyboard, kEventHotKeyPressed};
    OSStatus status = InstallApplicationEventHandler(HandleShortcut, 1, &event,
                                                   (__bridge void *)self, &_handler);
    if (status == noErr) status = RegisterShortcut(&_shortcut);
    if (status != noErr) {
        self.shortcutStatus.title = status == eventHotKeyExistsErr
            ? @"⌘F12 is already in use" : [NSString stringWithFormat:@"Shortcut unavailable (%d)", (int)status];
        self.statusItem.button.toolTip = self.shortcutStatus.title;
    }

    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (![defaults stringForKey:TargetsKey]) {
        [self editTargets:nil];
    } else if ([defaults boolForKey:StartupKey]) {
        [self openTargets:nil];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    if (self.shortcut) UnregisterEventHotKey(self.shortcut);
    if (self.handler) RemoveEventHandler(self.handler);
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {
    (void)app;
    (void)visible;
    [self editTargets:nil];
    return YES;
}

- (void)editTargets:(id)sender {
    (void)sender;
    if (!self.settings) {
        self.settings = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 364)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:NO];
        self.settings.title = @"QuickLaunch — Targets";
        self.settings.releasedWhenClosed = NO;
        [self.settings center];
        NSView *content = self.settings.contentView;
        NSTextField *instructions = [NSTextField wrappingLabelWithString:
            @"Enter one target per line. Use a full path, app:Application Name, or an https:// website. Press ⌘F12 to open the saved list."];
        instructions.frame = NSMakeRect(20, 303, 580, 42);
        [content addSubview:instructions];

        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 105, 580, 193)];
        scroll.borderType = NSBezelBorder;
        scroll.hasVerticalScroller = YES;
        self.editor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, scroll.contentSize.width, scroll.contentSize.height)];
        self.editor.richText = NO;
        self.editor.importsGraphics = NO;
        self.editor.automaticQuoteSubstitutionEnabled = NO;
        self.editor.automaticDashSubstitutionEnabled = NO;
        self.editor.automaticTextReplacementEnabled = NO;
        self.editor.automaticSpellingCorrectionEnabled = NO;
        self.editor.font = [NSFont monospacedSystemFontOfSize:13 weight:NSFontWeightRegular];
        self.editor.textContainerInset = NSMakeSize(7, 7);
        self.editor.verticallyResizable = YES;
        self.editor.autoresizingMask = NSViewWidthSizable;
        self.editor.textContainer.widthTracksTextView = YES;
        self.editor.accessibilityLabel = @"Launch targets, one per line";
        scroll.documentView = self.editor;
        [content addSubview:scroll];

        self.startup = [NSButton checkboxWithTitle:@"Also open targets when QuickLaunch starts" target:nil action:nil];
        self.startup.frame = NSMakeRect(20, 75, 580, 20);
        [content addSubview:self.startup];
        self.feedback = [NSTextField wrappingLabelWithString:@""];
        self.feedback.frame = NSMakeRect(20, 15, 440, 52);
        [content addSubview:self.feedback];
        NSButton *save = [NSButton buttonWithTitle:@"Save" target:self action:@selector(saveTargets:)];
        save.frame = NSMakeRect(506, 18, 94, 32);
        [content addSubview:save];
    }
    if (!self.settings.visible) {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        self.editor.string = [defaults stringForKey:TargetsKey] ?: @"# Examples (remove # to use one):\n# ~/Documents\n# app:Calculator\n# https://example.com/\n";
        self.startup.state = [defaults boolForKey:StartupKey] ? NSControlStateValueOn : NSControlStateValueOff;
        self.feedback.stringValue = @"";
    }
    Activate();
    [self.settings makeKeyAndOrderFront:nil];
    [self.settings makeFirstResponder:self.editor];
}

- (void)saveTargets:(id)sender {
    (void)sender;
    size_t count = 0;
    NSString *text = self.editor.string;
    NSString *problem = CallCore([text dataUsingEncoding:NSUTF8StringEncoding], false, &count);
    if (problem) {
        self.feedback.textColor = NSColor.systemRedColor;
        self.feedback.stringValue = problem;
        return;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:text forKey:TargetsKey];
    [defaults setBool:(count > 0 && self.startup.state == NSControlStateValueOn) forKey:StartupKey];
    [self.settings orderOut:nil];
}

- (void)openTargets:(id)sender {
    (void)sender;
    if (self.opening) return;
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:TargetsKey];
    NSData *data = [saved dataUsingEncoding:NSUTF8StringEncoding];
    size_t count = 0;
    NSString *badConfig = CallCore(data, false, &count);
    if (badConfig || count == 0) {
        [self editTargets:nil];
        self.feedback.stringValue = badConfig ?: @"Save at least one target first.";
        self.feedback.textColor = badConfig ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
        return;
    }
    self.opening = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        size_t unused = 0;
        NSString *problem = CallCore(data, true, &unused);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.opening = NO;
            if (problem) {
                [self editTargets:nil];
                self.feedback.textColor = NSColor.systemRedColor;
                self.feedback.stringValue = problem;
                self.feedback.toolTip = problem;
            }
        });
    });
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--validate") == 0) {
            NSData *data = [NSFileHandle.fileHandleWithStandardInput readDataToEndOfFile];
            size_t count = 0;
            NSString *problem = CallCore(data, false, &count);
            if (problem) {
                fprintf(stderr, "%s\n", problem.UTF8String);
                return 1;
            }
            printf("%zu targets\n", count);
            return 0;
        }
        if (argc == 2 && strcmp(argv[1], "--check-hotkey") == 0) {
            [NSApplication sharedApplication];
            EventHotKeyRef shortcut = NULL;
            OSStatus status = RegisterShortcut(&shortcut);
            if (status == noErr) {
                UnregisterEventHotKey(shortcut);
                puts("macOS accepted ⌘F12 registration");
                return 0;
            }
            fprintf(stderr, "macOS rejected ⌘F12 registration (status %d)\n", (int)status);
            return 1;
        }
        [NSApplication sharedApplication];
        __attribute__((objc_precise_lifetime)) QuickLaunch *delegate = [[QuickLaunch alloc] init];
        NSApp.delegate = delegate;
        [NSApp run];
        return 0;
    }
}
