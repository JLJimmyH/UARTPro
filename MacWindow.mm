#include "MacWindow.h"

#include <QWindow>

#import <AppKit/AppKit.h>

void applyMacTitleBarStyle(QWindow *window)
{
    if (!window)
        return;

    // Qt cocoa 平台的 winId() 是 NSView*,取用前會強制建立 native window
    NSView *view = reinterpret_cast<NSView *>(window->winId());
    if (!view)
        return;

    NSWindow *nsWindow = [view window];
    if (!nsWindow)
        return;

    nsWindow.titlebarAppearsTransparent = YES;
    nsWindow.titleVisibility = NSWindowTitleVisibilityHidden;
    nsWindow.styleMask |= NSWindowStyleMaskFullSizeContentView;
    // 拖曳交給 QML title bar 的 startSystemMove(),避免整片背景都能拖
    nsWindow.movableByWindowBackground = NO;
}

int macTrafficLightsWidth()
{
    return 78;
}
