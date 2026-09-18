# Qt QML 無邊框桌面應用設計藍圖

> 參考：**UARTPro** — Qt 6 QML + C++ 無邊框桌面應用（Windows + macOS）

## 1. 無邊框視窗 + Windows 原生拖曳

雙層設計：**C++ 原生層**攔截 `WM_NCCALCSIZE` + 設定 Style Bits；**QML 層**自訂標題列 + 8 個 Resize Handle。

### C++ 端 (main.cpp)

```cpp
#ifdef Q_OS_WIN
#include <windows.h>
// 攔截 WM_NCCALCSIZE：讓整個視窗都是 client area
class WindowsFramelessEventFilter : public QAbstractNativeEventFilter {
    HWND m_hwnd;
public:
    explicit WindowsFramelessEventFilter(HWND h) : m_hwnd(h) {}
    bool nativeEventFilter(const QByteArray &et, void *msg, qintptr *res) override {
        auto *m = static_cast<MSG*>(msg);
        if (m && m->hwnd == m_hwnd && m->message == WM_NCCALCSIZE && m->wParam == TRUE)
            { *res = 0; return true; }
        return false;
    }
};
// 保留 Snap / Resize / 最大最小化
static void enableSnap(HWND h) {
    auto s = GetWindowLongPtrW(h, GWL_STYLE);
    SetWindowLongPtrW(h, GWL_STYLE,
        (s | WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX | WS_SYSMENU) & ~LONG_PTR(WS_CAPTION));
    SetWindowPos(h,0,0,0,0,0, SWP_NOMOVE|SWP_NOSIZE|SWP_NOZORDER|SWP_NOACTIVATE|SWP_FRAMECHANGED);
}
#endif
// engine.load() 之後：
auto *w = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
HWND h = reinterpret_cast<HWND>(w->winId());
enableSnap(h);
auto f = std::make_unique<WindowsFramelessEventFilter>(h);
app.installNativeEventFilter(f.get());
```

### QML 端 (main.qml)

```qml
Window {
    flags: Qt.FramelessWindowHint | Qt.Window | Qt.WindowMinimizeButtonHint | Qt.WindowMaximizeButtonHint
    property bool isMaximized: false
    onVisibilityChanged: isMaximized = (visibility === Window.Maximized)
    function toggleMaximize() { isMaximized ? showNormal() : showMaximized() }

    // 標題列：拖曳 + 雙擊最大化
    Rectangle {
        id: titleBar; Layout.fillWidth: true; height: 52
        MouseArea {
            anchors.fill: parent
            onPressed: root.startSystemMove()          // 原生拖曳 + Snap
            onDoubleClicked: root.toggleMaximize()
        }
        Row { /* 最小化 / 最大化 / 關閉 按鈕 */ }
    }

    // Resize Handles — 四邊 (5px) + 四角 (8x8)
    MouseArea { z:200; visible:!isMaximized; width:5
        anchors { left:parent.left; top:parent.top; bottom:parent.bottom; topMargin:5; bottomMargin:5 }
        cursorShape: Qt.SizeHorCursor; onPressed: startSystemResize(Qt.LeftEdge) }
    // ... 右/上/下邊 + 四角同理，角落用 Qt.LeftEdge | Qt.TopEdge 組合
}
```

> `startSystemMove()` / `startSystemResize()` 是 Qt 6 API，直接委託 OS 處理，Windows Snap 自動支援。

---

## 1b. macOS：同一個需求，相反的做法

上面那套**不能**移植到 macOS，兩個原因都是死路：

1. `Qt.FramelessWindowHint` 會把紅綠燈按鈕、原生 resize、全螢幕與 Mission Control 一起拿掉。
2. **Qt 在 cocoa 平台沒有實作 `startSystemResize()`**，呼叫直接回 `false` —— 自己畫 handle 也救不回來。

所以 macOS 反過來做：**保留原生視窗，只把 titlebar 藏起來**，讓 QML 畫在原本 titlebar 的位置上。

### C++ 端 (MacWindow.mm，Objective-C++)

```objc
NSView *view = reinterpret_cast<NSView *>(window->winId());   // Qt cocoa 的 winId 是 NSView*
NSWindow *nsWindow = [view window];
nsWindow.titlebarAppearsTransparent = YES;
nsWindow.titleVisibility = NSWindowTitleVisibilityHidden;
nsWindow.styleMask |= NSWindowStyleMaskFullSizeContentView;   // content 延伸進 titlebar 區
nsWindow.movableByWindowBackground = NO;                      // 拖曳只由 QML title bar 負責
```

CMake 需要 `enable_language(OBJCXX)`（只能包在 `if(APPLE)` 裡，寫進 `project(LANGUAGES)` 會讓
Windows 的 configure 直接失敗）與 `-framework AppKit`。

> **坑**：`setVisible(true)` 時 Qt 會重設 `styleMask`，只在顯示前套一次會被蓋掉，
> 顯示後必須用 `QTimer::singleShot(0, ...)` 再套一次。

### QML 端

以 `readonly property bool isMac: Qt.platform.os === "osx"` 分流：

| 元素 | Windows | macOS |
|------|---------|-------|
| `flags` | `FramelessWindowHint` | 不帶，保留原生視窗 |
| 自訂 min/max/close 按鈕 | 顯示 | `visible: false`（用原生紅綠燈） |
| 8 個 resize handle | 啟用 | 全部停用（原生邊框接手） |
| title bar 左側 | 20px | 20px + 78px（讓開紅綠燈） |
| `startSystemMove()` | 可用 | 可用（cocoa 有實作） |

---

## 2. 建構腳本架構 (build.bat / deploy.bat / copy.bat)

讓 AI Agent 不需 IDE，命令列即可編譯、部署、更新。

### build.bat — 一鍵編譯

```batch
@echo off & setlocal enabledelayedexpansion & cd /d "%~dp0"
:: 自動偵測 VS
for /f "delims=" %%i in ('"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -property installationPath') do set "VS=%%i"
call "%VS%\VC\Auxiliary\Build\vcvars64.bat"
rd /s /q build 2>nul & mkdir build & cd build
cmake .. -G "Ninja" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="D:/Qt/6.7.3/msvc2022_64"
cmake --build . --config Release
robocopy "..\bin" "." /E /XF "MyApp.exe" "*.json" >nul
```

### deploy.bat — 一鍵打包到 bin/

```batch
@echo off & setlocal enabledelayedexpansion
set APP_NAME=MyApp.exe
:: 從 CMakeCache.txt 自動解析 Qt 路徑 & MSVC Runtime 路徑
:: Step 1: copy exe → bin/
:: Step 2: windeployqt6.exe --qmldir "." "bin\MyApp.exe"
:: Step 3: copy vcruntime140.dll 等 MSVC Runtime 到 bin/
```

### copy.bat — 快速同步 exe

```batch
copy /Y "build\MyApp.exe" "bin\"
```

### 使用流程

```
首次：  build.bat → deploy.bat → bin/ 可發佈
改 code：build.bat → copy.bat   → bin/ 已更新
加 Qt module：build.bat → deploy.bat（重新打包）
```

### AI Agent 常用指令

```bash
build.bat && deploy.bat          # 完整建置+部署
build.bat && copy.bat            # 快速重編
bin\MyApp.exe                    # 執行
```

### macOS：build.sh

```bash
./build.sh                       # 增量建構（native 架構）
./build.sh clean universal       # 全清 + x86_64/arm64 universal
./build.sh deploy                # macdeployqt + ad-hoc 簽名
open build/UARTPro.app
```

Qt 官方 macOS binary 本身是 universal，所以 `-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"`
在單一台機器（或單一 CI runner）上就能同時產出兩種架構，不需要兩台機器。
