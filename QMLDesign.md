# Qt QML 無邊框桌面應用設計藍圖

> 參考：**UARTPro** — Qt 6 QML + C++ 無邊框 Windows 桌面應用

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
