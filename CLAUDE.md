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

## Terminal 跨行拖曳選取機制

這是 main.qml 中最複雜的互動邏輯,改動前必須理解以下架構:

### 兩層選取系統

1. **單行字元選取** — `activeEditRow` 指向某行時,該行的 `editText`（TextEdit）變 visible,用 `editText.select(start, end)` 做原生反白。`_selStart` 記錄起點。
2. **跨行拖曳選取** — `_dragStartModelRow/CharPos` + `_dragEndModelRow/CharPos` 記錄首尾行及字元位置。中間行透過 `selectedSet` 整行標記。視覺高亮由 delegate 內的 `partialSelRect`（Rectangle + clip + 反色文字）實現。

### 關鍵陷阱

- **MouseArea 是全域的**:所有左鍵互動由 `terminalMouseOverlay`（z=2,覆蓋整個 terminal Item）處理,delegate 內**沒有** MouseArea。座標轉換必須用 `mapToItem(terminalView.contentItem, ...)` 和 `mapToItem(editText, ...)`。
- **charPos 座標系**:`charPosInRow` 返回的位置是相對於 `displayText` 的,displayText 包含 prefix（`RX> ` 等）但**不包含** timestamp 和行號。改 copy 邏輯時注意這個對齊。
- **字元寬度用 `monoCharMetrics.advanceWidth`**:不能用 `contentWidth / charCount`,因為 RichText 的 bold keyword highlight 會讓 contentWidth 偏大。
- **HTML entity**:`displayText` 是 RichText,`text` 屬性包含 `&gt;` `&lt;` `&amp;` 等 entity。算純文字長度時必須用 `stripHtmlToPlain()` 先解碼。
- **`_selStart` 延遲計算**:`onPressed` 時 editText 剛變 visible,佈局未完成,`positionAt` 不可靠。改為存 `_dragPressMouseX/Y`,在第一次 `onPositionChanged` 時才用 `positionAt` 算精確值。
- **editText 狀態殘留**:delegate 回收時 editText 可能保留舊選取。已加 `onVisibleChanged: if (visible) deselect()` 清除。

### copy 行為（`copyCrossLineSelection`）

- **首尾行**:用 `getDisplayPlainText(entry)` 取 prefix+data 純文字,再依 charPos 做 `substring`。charPos 自然決定是否包含 prefix。Timestamp 不在 displayText 中,永遠不包含。
- **中間行**:只複製原始資料（`msgText` 或 `hexData`）,不加 timestamp、不加 prefix。
- **視覺一致**:`partialSelRect` 的 "full" 類型從 `displayText.x` 開始,不覆蓋 timestamp 區域。

### getDragSelectionInfo 返回值

| type | 含義 | charStart | charEnd |
|------|------|-----------|---------|
| none | 不在選取範圍 | - | - |
| full | 中間行,整行資料選取 | - | - |
| head | 首行,從 charStart 到行尾 | ✓ | - |
| tail | 尾行,從行首到 charEnd | - | ✓ |

## 版本資訊

`version.h` 定義 `APP_NAME` / `APP_VERSION_STR`,透過 context property 傳給 QML。
