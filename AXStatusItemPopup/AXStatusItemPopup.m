//
//  StatusItemPopup.m
//  StatusItemPopup
//
//  Created by Alexander Schuch on 06/03/13.
//  Copyright (c) 2013 Alexander Schuch. All rights reserved.
//

#import "AXStatusItemPopup.h"

#define kMinViewWidth 22

BOOL shouldBecomeKeyWindow;
NSWindow* windowToOverride;

//
// Private properties
//
@interface AXStatusItemPopup ()

@property NSViewController *viewController;
@property NSImageView *imageView;
@property NSStatusItem *statusItem;
@property NSPopover *popover;
@property(assign, nonatomic, getter=isActive) BOOL active;

@property NSWindow* oldKeyWindow;
@property NSMutableArray* hiddenWindows;
@property BOOL appWasActive;
@property BOOL isUpdatingWindows;
@property BOOL isActiveWithDelay;

@property (nonatomic)  NSRunningApplication* previousRunningApp;

@end

///////////////////////////////////
#pragma mark - Implementation AXStatusItemPopup
///////////////////////////////////

@implementation AXStatusItemPopup

//
#pragma mark - Allocators
//

+ (id)statusItemPopupWithViewController:(NSViewController *)controller {
    return [[self alloc] initWithViewController:controller];
}

+ (id)statusItemPopupWithViewController:(NSViewController *)controller image:(NSImage *)image {
    return [[self alloc] initWithViewController:controller image:image];
}

+ (id)statusItemPopupWithViewController:(NSViewController *)controller image:(NSImage *)image alternateImage:(NSImage *)alternateImage {
    return [[self alloc] initWithViewController:controller image:image alternateImage:alternateImage];
}

//
#pragma mark - Initialization & Dealloc
//

- (id)initWithViewController:(NSViewController *)controller {
    return [self initWithViewController:controller image:nil];
}

- (id)initWithViewController:(NSViewController *)controller image:(NSImage *)image {
    return [self initWithViewController:controller image:image alternateImage:nil];
}

- (id)initWithViewController:(NSViewController *)controller image:(NSImage *)image alternateImage:(NSImage *)alternateImage {
    CGFloat height = [NSStatusBar systemStatusBar].thickness;
    
    self = [super initWithFrame:NSMakeRect(0, 0, kMinViewWidth, height)];
    if (self) {
        _active = NO;
        _animated = YES;
        _appWasActive = NO;
        _isUpdatingWindows = NO;
        _isActiveWithDelay = NO;
        _oldKeyWindow = nil;
        _hiddenWindows = [NSMutableArray new];
        _viewController = controller;
        _previousRunningApp = nil;
        
        self.image = image;
        self.alternateImage = alternateImage;
        
        _imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, kMinViewWidth, height)];
        [self addSubview:_imageView];
        
        self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
        self.statusItem.view = self;
        self.statusItem.target = self;
        self.statusItem.action = @selector(togglePopover:);
        
        self.popover = [[NSPopover alloc] init];
        self.popover.contentViewController = self.viewController;
        self.popover.animates = self.animated;
        self.popover.delegate = self;
        
        windowToOverride = self.window;
        
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(applicationDidResignActive:) name:NSApplicationDidResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(windowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:nil];
        [[[NSWorkspace sharedWorkspace]notificationCenter]addObserver:self selector:@selector(activeSpaceHasChanged:) name:NSWorkspaceActiveSpaceDidChangeNotification object:nil];
    }
    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter]removeObserver:self];
}

- (void)activeSpaceHasChanged: (NSNotification*)note {
    self.appWasActive = NO;
    [self hidePopover];
}

//
#pragma mark - Drawing
//

- (void)drawRect:(NSRect)dirtyRect {
    // set view background color
    if (self.isActive) {
        [[NSColor selectedMenuItemColor] setFill];
    } else {
        [[NSColor clearColor] setFill];
    }
    NSRectFill(dirtyRect);
    
    // set image
    NSImage *image = (self.isActive ? self.alternateImage : self.image);
    _imageView.image = image;
}

//
#pragma mark - Mouse Events
//

- (void)mouseDown:(NSEvent *)theEvent {
    [self togglePopover];
}

//
#pragma mark - Setter
//

- (void)setPreviousRunningApp:(NSRunningApplication*)previousRunningApp {
    if (![previousRunningApp.executableURL isEqual:[NSRunningApplication currentApplication]]) {
        _previousRunningApp = previousRunningApp;
    }
}

- (void)setActive:(BOOL)active {
    _active = active;
    shouldBecomeKeyWindow = active;
    if (active) {
        self.previousRunningApp = nil;
        self.isActiveWithDelay = YES;
        if ([NSApp isActive]) {
            self.appWasActive = YES;
            self.oldKeyWindow = [NSApp keyWindow];
        } else {
            self.previousRunningApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
            self.appWasActive = NO;
            //remind open windows of app and hide then (they shouldn't popup into foreground when only activating Popover)
            [NSApp activateIgnoringOtherApps:YES];
            for (NSWindow* window in [NSApp windows]) {
                if (window.isVisible && window != self.window) {
                    /* Activate this statement to prevent visible but not active windows from hiding. Problem is that they geht activated then*/
                    if (/*true || */!(window.occlusionState & NSWindowOcclusionStateVisible)) {
                        window.isVisible = NO;
                        self.isUpdatingWindows = YES;
                        [self.hiddenWindows addObject:window];
                        self.isUpdatingWindows = NO;
                    }
        
                }
            }
        }
    } else {
        if (self.appWasActive) {
            [self.oldKeyWindow makeKeyAndOrderFront:self];
            self.isActiveWithDelay = NO;
        } else {
            [self hideWithDelay];
        }
        self.appWasActive = NO;
        self.oldKeyWindow = nil;
    }
    [self setNeedsDisplay:YES];
}

- (void)setImage:(NSImage *)image {
    _image = image;
    [self updateViewFrame];
}

- (void)setAlternateImage:(NSImage *)image {
    _alternateImage = image;
    if (!image && _image) {
        _alternateImage = _image;
    }
    [self updateViewFrame];
}

//
#pragma mark - Notification Handler
//

- (void) windowDidBecomeKey:(NSNotification *)notification {
    NSWindow* window = (NSWindow*)notification.object;
    if (window != self.window && !self.isUpdatingWindows) {
        window.isVisible = YES;
        if (self.isActiveWithDelay) {
            [self.hiddenWindows removeObject:window];
        }
        [[NSRunningApplication currentApplication] activateWithOptions:(NSApplicationActivateIgnoringOtherApps)];
    }
    if (window != self.window && self.isUpdatingWindows) {
        [self.window makeKeyWindow];
    }
}

- (void)applicationDidResignActive:(NSNotification*)note {
    [self hidePopover];
}

//
#pragma mark - Popover Delegate
//

    //This is safer then caring for the sended events. Sometimes the popup doesn't close, in these
    //cases popover and status item became out of sync
- (void) popoverWillShow: (NSNotification*) note {
    self.active = YES;
}

- (void) popoverWillClose: (NSNotification*) note {
    self.active = NO;
}

//
#pragma mark - Show / Hide Popover
//

- (void) togglePopover {
    [self togglePopoverAnimated:self.isAnimated];
}

- (void) togglePopoverAnimated:(BOOL)animated {
    if (self.isActive) {
        [self hidePopover];
    } else {
        [self showPopoverAnimated:animated];
    }
}

- (void)showPopover {
    [self showPopoverAnimated:self.isAnimated];
}

- (void)showPopoverAnimated:(BOOL)animated {
    BOOL willAnswer = [self.delegate respondsToSelector:@selector(shouldPopupOpen)];
    if (!willAnswer || (willAnswer && [self.delegate shouldPopupOpen])) {
        if (!self.popover.isShown) {
            _popover.animates = animated;
            if ([self.delegate respondsToSelector:@selector(popupWillOpen)]) {
                [self.delegate popupWillOpen];
            }
            [_popover showRelativeToRect:self.frame ofView:self preferredEdge:NSMinYEdge];
        }
        [self.window makeKeyWindow];
        if ([self.delegate respondsToSelector:@selector(popupDidOpen)]) {
            [self.delegate popupDidOpen];
        }
    }
}

- (void)hidePopover {
    BOOL willAnswer = [self.delegate respondsToSelector:@selector(shouldPopupClose)];
    if (!willAnswer || (willAnswer && [self.delegate shouldPopupClose])) {
        if (_popover && _popover.isShown) {
            if ([self.delegate respondsToSelector:@selector(popupWillClose)]) {
                [self.delegate popupWillClose];
            }
            [_popover close];
        }
        if ([self.delegate respondsToSelector:@selector(popupDidClose)]) {
            [self.delegate popupDidClose];
        }
    }
}

//
#pragma mark - Helper
//

- (void)updateViewFrame {
    CGFloat width = MAX(MAX(kMinViewWidth, self.alternateImage.size.width), self.image.size.width);
    CGFloat height = [NSStatusBar systemStatusBar].thickness;
    
    NSRect frame = NSMakeRect(0, 0, width, height);
    self.frame = frame;
    self.imageView.frame = frame;
    
    [self setNeedsDisplay:YES];
}

- (void)hideWithDelay {
    if (self.previousRunningApp) {
        [[NSWorkspace sharedWorkspace]launchApplication:self.previousRunningApp.executableURL.path];
        self.previousRunningApp = nil;
    }
    self.isUpdatingWindows = YES;
    for (NSWindow* window in self.hiddenWindows) {
        window.isVisible = YES;
    }
    self.isUpdatingWindows = NO;
    self.isActiveWithDelay = NO;
    [self.hiddenWindows removeAllObjects];
}

@end

///////////////////////////////////
#pragma mark - Implementation NSWindow+canBecomeKeyWindow
///////////////////////////////////

#import <objc/objc-class.h>

@implementation NSWindow (canBecomeKeyWindow)

    //This is to fix a bug with 10.7 where an NSPopover with a text field
    //cannot be edited if its parent window won't become key
- (BOOL)swizzledPopoverCanBecomeKeyWindow {
    if (self == windowToOverride) {
        return shouldBecomeKeyWindow;
    } else {
        return [self swizzledPopoverCanBecomeKeyWindow];
    }
}

+ (void)load {
    method_exchangeImplementations(
                                   class_getInstanceMethod(self, @selector(canBecomeKeyWindow)),
                                   class_getInstanceMethod(self, @selector(swizzledPopoverCanBecomeKeyWindow)));
}

@end

