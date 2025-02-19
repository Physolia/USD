//
// Copyright 2016 Pixar
//
// Licensed under the terms set forth in the LICENSE.txt file available at
// https://openusd.org/license.
//

#include "pxr/pxr.h"
#include "pxr/imaging/garch/glDebugWindow.h"
#include "pxr/imaging/garch/glPlatformDebugWindowDarwin.h"

#if defined(ARCH_OS_OSX)
#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#endif

PXR_NAMESPACE_USING_DIRECTIVE

#if defined(ARCH_OS_OSX)

static int
Garch_GetModifierKeys(NSUInteger flags)
{
    int keys = 0;

    // The 10.12 SDK has new symbols.
#if MAC_OS_X_VERSION_MAX_ALLOWED < 101200
  #define NSEventModifierFlagShift NSShiftKeyMask
  #define NSEventModifierFlagControl NSControlKeyMask
  #define NSEventModifierFlagOption NSAlternateKeyMask
  #define NSEventModifierFlagCommand NSCommandKeyMask
#endif
    if (flags & NSEventModifierFlagShift)   keys |= GarchGLDebugWindow::Shift;
    if (flags & NSEventModifierFlagControl) keys |= GarchGLDebugWindow::Ctrl;
    if (flags & NSEventModifierFlagOption)  keys |= GarchGLDebugWindow::Alt;
    if (flags & NSEventModifierFlagCommand) keys |= GarchGLDebugWindow::Alt;

    return keys;
}

@class Garch_GLPlatformView;

@interface Garch_GLPlatformView : NSOpenGLView <NSWindowDelegate>
{
    GarchGLDebugWindow *_callback;
    NSOpenGLContext *_ctx;
}

@end

@implementation Garch_GLPlatformView

-(id)initGL:(NSRect)frame callback:(GarchGLDebugWindow*)cb
{
    _callback = cb;

    int attribs[] = {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        NSOpenGLPFAColorSize, 32,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        0
    };

    NSOpenGLPixelFormat *pf
        = [[NSOpenGLPixelFormat alloc]
           initWithAttributes:(NSOpenGLPixelFormatAttribute*)attribs];
    self = [self initWithFrame:frame pixelFormat:pf];

    _ctx = [[NSOpenGLContext alloc] initWithFormat:pf shareContext:nil];

    [self setOpenGLContext:_ctx];

    [_ctx makeCurrentContext];

    _callback->OnInitializeGL();

    [pf release];

    return self;
}

-(BOOL)acceptsFirstResponder
{
    return YES;
}

-(void)drawRect:(NSRect)theRect
{
    [_ctx makeCurrentContext];

    _callback->OnPaintGL();

    [[self openGLContext] flushBuffer];
}

-(void)windowWillClose:(NSNotification*)notification
{
    [[NSApplication sharedApplication] terminate:self];
}

-(void)windowDidResize:(NSNotification *)notification
{
    NSRect r = [self frame];
    _callback->OnResize(r.size.width, r.size.height);
}

-(void)mouseDown:(NSEvent*)event
{
    NSPoint p = [event locationInWindow];
    NSRect r = [self frame];
    NSUInteger modflags = [event modifierFlags];
    _callback->OnMousePress(GarchGLDebugWindow::MyButton1,
                            p.x, r.size.height - 1 - p.y,
                            Garch_GetModifierKeys(modflags));

    [self setNeedsDisplay:YES];
}

-(void)mouseUp:(NSEvent*)event
{
    NSPoint p = [event locationInWindow];
    NSRect r = [self frame];
    NSUInteger modflags = [event modifierFlags];
    _callback->OnMouseRelease(GarchGLDebugWindow::MyButton1,
                              p.x, r.size.height - 1 - p.y,
                              Garch_GetModifierKeys(modflags));

    [self setNeedsDisplay:YES];
}

-(void)mouseDragged:(NSEvent*)event
{
    NSPoint p = [event locationInWindow];
    NSRect r = [self frame];
    NSUInteger modflags = [event modifierFlags];
    _callback->OnMouseMove(p.x, r.size.height - 1 - p.y,
                           Garch_GetModifierKeys(modflags));

    [self setNeedsDisplay:YES];
}

- (void)keyDown:(NSEvent *)event
{
    int keyCode = [event keyCode];
    int key = 0;

    // XXX shoud call UCKeyTranslate() for non-us keyboard
    const int keyMap[] = { 0x00, 'a', 0x0b, 'b', 0x08, 'c', 0x02, 'd',
                           0x0e, 'e', 0x03, 'f', 0x05, 'g', 0x04, 'h',
                           0x22, 'i', 0x26, 'j', 0x28, 'k', 0x25, 'l',
                           0x2e, 'm', 0x2d, 'n', 0x1f, 'o', 0x23, 'p',
                           0x0c, 'q', 0x0f, 'r', 0x01, 's', 0x11, 't',
                           0x20, 'u', 0x09, 'v', 0x0d, 'w', 0x07, 'x',
                           0x10, 'y', 0x06, 'z', 0x31, ' ', -1, -1};

    for (int i = 0; keyMap[i] >=0; i += 2) {
        if (keyMap[i] == keyCode) {
            key = keyMap[i+1];
            break;
        }
    }
    if (key) {
        _callback->OnKeyRelease(key);
    }

    [self setNeedsDisplay:YES];
}

@end

// ---------------------------------------------------------------------------

PXR_NAMESPACE_OPEN_SCOPE

Garch_GLPlatformDebugWindow::Garch_GLPlatformDebugWindow(GarchGLDebugWindow *w)
    : _callback(w)
{
}

void
Garch_GLPlatformDebugWindow::Init(const char *title,
                                  int width, int height, int nSamples)
{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    id applicationName = [[NSProcessInfo processInfo] processName];

    NSRect frame = NSMakeRect(0, 0, width, height);
    NSRect viewBounds = NSMakeRect(0, 0, width, height);

    Garch_GLPlatformView *view =
        [[Garch_GLPlatformView alloc] initGL:viewBounds callback:_callback];

    NSWindow *window = [[NSWindow alloc]
                        initWithContentRect:frame
                        styleMask:NSTitledWindowMask
                                 |NSClosableWindowMask
                                 |NSMiniaturizableWindowMask
                                 |NSResizableWindowMask
                        backing:NSBackingStoreBuffered
                        defer:NO];
    [window cascadeTopLeftFromPoint:NSMakePoint(20,20)];
    [window setTitle: applicationName];
    [window makeKeyAndOrderFront:nil];

    [NSApp activateIgnoringOtherApps:YES];

    [window setContentView:view];
    [window setDelegate:view];
}

void
Garch_GLPlatformDebugWindow::Run()
{
    [NSApp run];
}

void
Garch_GLPlatformDebugWindow::ExitApp()
{
    [NSApp stop:nil];
}

PXR_NAMESPACE_CLOSE_SCOPE

#else // IPHONE Derivatives

PXR_NAMESPACE_OPEN_SCOPE

Garch_GLPlatformDebugWindow::Garch_GLPlatformDebugWindow(GarchGLDebugWindow *w)
{
}

void Garch_GLPlatformDebugWindow::Init(const char *title, int width, int height, int nSamples)
{
}

void
Garch_GLPlatformDebugWindow::Run()
{
}

void
Garch_GLPlatformDebugWindow::ExitApp()
{
}

PXR_NAMESPACE_CLOSE_SCOPE

#endif
