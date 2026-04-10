# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

UARTPro — Qt 6 (6.2+) QML + C++ 無邊框 Windows 串列埠終端機。使用 `QSerialPort` 進行通訊、QML 做 UI、C++ 做資料層與 Win32 整合。目前開發 Qt 版本為 `D:/Qt/6.7.3/msvc2022_64`,建構工具為 MSVC 2022 + Ninja。

## Build / Deploy 指令

建構腳本全部放在專案根目錄,設計為不需開啟 IDE 即可操作:

- `build.bat` — 呼叫 `vswhere` 找 VS → `vcvars64.bat` → 清 `build/` → `cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="D:/Qt/6.7.3/msvc2022_64"` → `cmake --build`。建完後用 `robocopy` 把 `bin/` 下舊的 runtime DLL 同步回 `build/`(排除 exe 與 json),讓 `build/UARTPro.exe` 可以直接跑。
- `deploy.bat` — 從 `CMakeCache.txt` 自動解析 Qt 路徑與 MSVC Redist 路徑 → 清空 `bin/` → 複製 exe → `windeployqt6.exe --qmldir .` → 複製 `vcruntime140*.dll` / `msvcp140*.dll` / `concrt140.dll`。最終的可發佈產出在 `bin/`。
- `copy.bat` — 只把 `build/UARTPro.exe` 複製到 `bin/`,用於改完 code 後快速更新。

典型流程:

```
首次 / 加 Qt module:  build.bat && deploy.bat
改 C++/QML 後快速迭代: build.bat && copy.bat
執行:                  bin\UARTPro.exe
```

注意 `build.bat` 會 `rd /s /q build`,每次都是乾淨重建;若要增量建構請直接用 Qt Creator 或手動 `cmake --build build`。

本專案無測試 target、無 lint 設定。

## CLI 參數

`main.cpp` 使用 `QCommandLineParser`,支援:

- `--config <path>` — 指定設定檔路徑(預設見 `ConfigManager::defaultConfigPath()`)
- `--port <COMx>` — 啟動時自動連線
- `--baud <rate>` — 搭配 `--port` 使用
- `--record <filePath>` — 啟動時自動開始記錄

## 架構

專案是單一 Qt 執行檔,C++ 端注入三個 context property 到 QML:`serialManager`、`fileLogger`、`configManager`,加上 `appName` / `appVersion` / `cmdLinePort` / `cmdLineBaud` / `cmdLineRecord`。QML 只透過這些物件的 signal/slot/property 互動,不直接碰硬體或檔案系統。

### C++ 層 (資料 + OS 整合)

- [SerialPortManager.h](SerialPortManager.h) / [.cpp](SerialPortManager.cpp) — 包裝 `QSerialPort`。負責列舉可用 port、開關連線、收發資料、斷線偵測 + `m_reconnectTimer` 自動重連。收到資料後 buffer 到換行再以 `dataReceived(timestamp, ascii, hex)` signal 丟給 QML。`reconnected()` / `connectionLost()` 是 UI 顯示狀態用的。
- [FileLogger.h](FileLogger.h) / [.cpp](FileLogger.cpp) — 單一 log 檔的寫入器,含 `QTimer` 批次 flush、檔案大小追蹤,並提供 CH-09 的 `exportPlainText` / `exportCsv`(把 QML buffer 中的 entry 匯出成 txt / csv)。
- [ConfigManager.h](ConfigManager.h) / [.cpp](ConfigManager.cpp) — JSON 設定持久化。所有 UI 偏好(uiScale、fontSize、currentTheme、showPrefix、hexDisplayMode、showTimestamp、showLineNumbers、colorNumbers、maxBufferLines)、`keywords`、`filters` 都經此存取。`scheduleSave()` 是 debounced save(QTimer single-shot),避免每個屬性變更就寫硬碟;載入中用 `m_loading` 旗標阻擋回寫。
- [main.cpp](main.cpp) — 建立 QGuiApplication、解析 CLI、生成三個 manager 並注入 QML、載入 `qrc:/qt/qml/UARTPro/main.qml`。

### Win32 無邊框視窗處理

這是本專案的架構關鍵,想改視窗行為必須同時動兩層:

- **C++ 層**([main.cpp](main.cpp)):
  1. `WindowsFramelessEventFilter` 攔截 `WM_NCCALCSIZE` 並回傳 0 → 整個視窗都變成 client area(消掉標題列非客戶區)。
  2. `enableSnapForFramelessWindow()` 在保留 `WS_THICKFRAME | WS_MAXIMIZEBOX | WS_MINIMIZEBOX | WS_SYSMENU` 的同時清掉 `WS_CAPTION`,這樣才能保留 Windows 原生的 Snap / resize / 最大最小化。
- **QML 層**([main.qml](main.qml)): Window flag 設 `Qt.FramelessWindowHint`,自訂標題列用 `startSystemMove()` 啟動原生拖曳(含 Snap),四邊 + 四角 MouseArea 用 `startSystemResize(Qt.LeftEdge|...)` 啟動原生 resize。最大化/還原自行切換 `showMaximized()` / `showNormal()`。

詳細設計理由與範例程式見 [QMLDesign.md](QMLDesign.md)。

### QML 層 (UI)

[main.qml](main.qml) 約 3600 行,包含整個應用的 UI、資料處理、過濾/關鍵字高亮、buffer 管理,以及自訂標題列和 resize handle。共用 UI 元件另外抽成:

- [CyberButton.qml](CyberButton.qml) / [CyberComboBox.qml](CyberComboBox.qml) / [CyberCheckBox.qml](CyberCheckBox.qml) / [CyberTextField.qml](CyberTextField.qml) — 配合主題的控件樣式
- [EyeIcon.qml](EyeIcon.qml) / [BroomIcon.qml](BroomIcon.qml) — 內嵌 SVG-like icon

QML 檔案必須同時註冊到 [CMakeLists.txt](CMakeLists.txt) 的 `qt_add_qml_module` 的 `QML_FILES` 區塊才會被打包進 qrc,新增 QML 元件時不要忘記這一步。

## 版本資訊

`version.h` 定義 `APP_NAME` / `APP_VERSION_STR`,透過 context property 傳給 QML。
