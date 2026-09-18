#ifndef MACWINDOW_H
#define MACWINDOW_H

class QWindow;

// macOS 的無邊框做法與 Windows 完全不同:
// Windows 是攔 WM_NCCALCSIZE 把整個視窗變 client area(見 main.cpp),
// macOS 若直接用 Qt::FramelessWindowHint 會連紅綠燈按鈕、原生 resize、
// 全螢幕與 Mission Control 一起失去,而 Qt 在 cocoa 平台又沒有實作
// QWindow::startSystemResize(),自訂的 resize handle 會完全沒反應。
//
// 所以 macOS 保留原生視窗,只把 titlebar 變透明、標題文字隱藏,
// 再讓 content view 延伸進 titlebar 區域,自訂 title bar 就畫得上去。
void applyMacTitleBarStyle(QWindow *window);

// 紅綠燈按鈕佔掉的左側寬度(邏輯像素),QML title bar 靠這個讓出空間
int macTrafficLightsWidth();

#endif // MACWINDOW_H
