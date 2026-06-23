# UARTPro 優化任務清單

來源:33-agent 稽核(2026-06-23),25 findings 對抗式驗證通過。
兩大方向:**開啟速度優化** + **GUI 縮放比例 bug**。

工作模式:一階段一改 → `build.bat && copy.bat` → 通知使用者測試 → 使用者跑 `bin\UARTPro.exe` → 回報 ok → 下一階段。

狀態圖示:⬜ 未開始 / 🔧 進行中 / ✅ 完成已驗 / ⏸ 延後

---

## Stage 1 — 縮放 bug 核心修正(G2 + G1 + G4-combobox)✅ 使用者測試 ok
### 追加(測試發現 ComboBox 下拉 scale≠1.0 仍歪 = G4 overlay 未縮放)
- **G4-combobox** [CyberComboBox.qml]:popup reparent 到未縮放 overlay → 位置對(經 scaled parent 映射)但 body 尺寸不縮。修法:加 `property real uiScale`,popup width / delegate width/height/font/padding / ListView 高度上限全乘 uiScale。main.qml 6 個可見 CyberComboBox 加 `uiScale: root.uiScale`
- **note**:colorPicker(G2)位置已對、body 小 palette 視覺可接受(使用者認可);themePopup / terminalContextMenu(Menu)同 G4 latent body-not-scaled,位置 OK,暫留待 Stage 7 全域 px() token 一次處理
**檔案**:main.qml
**改動**:
- **G2** [main.qml:1401]:colorPickerPopup 定位映射目標 `root.contentItem` → `colorPickerPopup.parent`(實體/overlay 座標 → 邏輯座標,修彈窗錯位)
- **G1** [main.qml:40, 168, 170]:三個響應式門檻改比邏輯尺寸
  - L40 `root.width <= leftPanelAutoCollapseWidth` → `root.width / root.uiScale <= ...`
  - L168 `root.width <= ultraNarrowWidth` → `root.width / root.uiScale <= ...`
  - L170 `root.height <= titleOnlyHeightThreshold` → `root.height / root.uiScale <= ...`
- **G1 補完** [main.qml:177]:`onUiScaleChanged` 加呼 `adjustLeftPanelForWindowWidth()`(改 scale 不縮窗也要重評收合)

**測試動作**:
1. 開 app,UI scale 設 1.5(或 0.75)
2. 拖窗縮小到中等寬度 → 左面板應在「邏輯寬」到門檻時就收合(不是實體像素)
3. 點 keyword chip 的色塊(BG/FG/LN swatch)→ color picker popup 要彈在色塊正下方對齊(非偏移)
4. scale 設回 1.0 → 行為與原本一致

---

## Stage 2.5 — 啟動白框閃爍修正(S14,使用者回報)✅ 白框已不閃(殘留空白 window → Stage 8)
**根因**:[main.qml:12] `visible: true` → engine.load 時視窗以**原生樣式立刻顯示**(有原生標題列/邊框=白框),之後 [main.cpp:276+] 才套無邊框(去 WS_CAPTION + WM_NCCALCSIZE 攔截)→ 中間閃一瞬原生白框。client 區不白(color: colorBg 深色已設)。
**修法**:
- [main.qml:12]:`visible: true` → `visible: false`
- [main.cpp:274+]:hoist window ptr;在 #ifdef Q_OS_WIN frameless 設定**後**才 `window->setVisible(true)`(winId() 隱藏時也建 HWND,可先改樣式再 show)
**測試**:冷啟動不再先閃白框/原生標題列,直接出現無邊框完整介面。視窗仍可拖曳/縮放/最大最小化/Snap(無邊框功能未壞)。

## Stage 2 — 啟動加速安全批(S1 + S3 + S7)🔧 已 build+copy,待驗證
**檔案**:main.qml、ConfigManager.cpp、main.cpp
**改動**:
- **S1** [main.qml:4230]:刪冗餘 `serialManager.refreshPorts()`(ctor 已掃過,combo 已 bind,refresh 鈕可手動)。省一次同步 SetupAPI 掃描
- **S3** [ConfigManager.cpp:68]:first-run 的 inline `saveToFile()` → 改呼 `scheduleSave()`(debounced,移出 boot 路徑)
- **S7** [main.cpp:221 前]:加 `QGuiApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::PassThrough)`(明確化、不依賴版本預設)

**測試動作**:
1. 開 app → port 下拉清單仍正確列出 COM ports
2. 改設定(theme/scale)後關閉重開 → 設定有保存(scheduleSave 仍運作)
3. 視窗外觀正常、高 DPI 螢幕下不糊
4. (體感)冷啟動不變慢或略快

---

## Feature F2 — log 目錄記憶存 config(使用者選:存 config 兩者一致)🔧 已 build+copy,待驗證
**背景**:我先前在 toggleLogging 加 `currentFolder=Documents` 強制蓋掉原生對話框 MRU → LOG TO FILE 不再記住上次位置(回歸)。使用者要兩者(對話框+openLocation)都記住且一致。
**實作**:
- ConfigManager 新增持久化 `lastLogDir`(QString property + load/save/getter/setter,首個持久化 QString scalar)
- main.qml:toggleLogging 用 `currentLogDir()`(config 記住的 > 預設 Documents)設 currentFolder+selectedFile;onAccepted 成功後 `configManager.lastLogDir = pathDir(urlToLocalPath(selectedFile))`
- 新 helper:pathBase / urlToLocalPath / currentLogDir;openLogLocation 未記錄時改用 currentLogDir()
**測試**:見下方訊息

## Feature F1 — LOG TO FILE 旁加「開啟儲存位置」資料夾按鈕(使用者需求)✅ 使用者測試 ok
- 新增 [FolderIcon.qml](FolderIcon.qml)(Canvas 資料夾 icon,仿 BroomIcon/EyeIcon),註冊 CMakeLists QML_FILES
- [main.qml] LOG TO FILE 包成 RowLayout + 右側方形 icon button(高度綁 logToFileBtn.height)
- `openLogLocation()`:記錄中→logFilePath 父目錄;否則→generateDefaultPath()(Documents)父目錄;`Qt.openUrlExternally("file:///"+dir)` 開 Explorer
**測試**:LOG TO FILE 右邊出現資料夾 icon;hover 有框+tooltip「開啟儲存位置」;按下開啟 Explorer 到儲存資料夾(記錄中=實際檔案目錄,未記錄=Documents)

## Stage 3 — showDate 顯示/複製/log 一致性(順帶 feature bug)✅ 使用者測試 ok
### 實作備註
- text log(formatEntryForLog)**刻意**永遠寫完整日期(跨午夜燒機),**未動**
- copy(buildEntryText)依 showDate gating,對齊畫面 delegate(2540/2627)
- logStructured 加尾端 optional `ts`(向後相容,HeadlessRunner 不破);C++ 端把本地時戳轉 ISODateWithMs
**檔案**:main.qml、FileLogger.h、FileLogger.cpp
**改動**:
- **複製** [main.qml:3991 buildEntryText]:`line += entry.timestamp` → `line += (root.showDate ? entry.timestamp : root.tsTimeOnly(entry.timestamp))`(DATE 沒勾時複製不帶日期,對齊畫面)
- **JSONL** [main.qml:3570 / FileLogger.cpp:161]:`logStructured` 加 ts 參數,jsonl 用「擷取行時間」非 flush 時間(注意 entry.timestamp 本地格式 → 轉 ISODateWithMs)

**測試動作**:
1. DATE checkbox **不勾**,選取數行 Ctrl+C → 貼上應只有 `HH:mm:ss.zzz`(無日期)
2. DATE **勾**,複製 → 帶完整 `yyyy-MM-dd HH:mm:ss.zzz`
3. 開 jsonl 記錄,收幾行,看 log 檔 timestamp = 收到時間(非寫檔時間)

---

## Stage 4 — boot 重工消除(S5 + S9)⬜
**檔案**:main.qml
**改動**:
- **S5** [main.qml:117-126]:inline 色 token 預設值改成 theme idx 4(CLAY)的值(與 currentTheme 預設一致)→ boot 時 applyTheme 變 no-op,免 2 張 Canvas 多餘重繪 + regex 快取重建
- **S9** [main.qml:3376 help / 783 theme / 569 color]:隱藏 Popup body 包 `Loader { active: false }`(或 bind 可見旗標),首次 open 才建內容樹

**測試動作**:
1. 全新啟動(或刪 config)→ 預設主題正確顯示 CLAY、無色彩閃爍
2. F1 → help 視窗正常開
3. theme 選單、color picker 正常開、內容完整
4. 切換各主題正常

---

## Stage 5 — 部署清理(S2 + S10)⬜
**檔案**:deploy.bat、CMakeLists.txt
**改動**:
- **S2** [deploy.bat windeployqt 後]:刪 `bin\qml\QtQuick\Controls\` 下 Fusion/Imagine/Material/Universal/Windows(留 Basic + impl),刪 `bin\qml\QtQuick\NativeStyle\`(省 ~2.6MB)
- **S10** [CMakeLists.txt]:Release 加 `INTERPROCEDURAL_OPTIMIZATION TRUE`(LTO,先量再定)

**測試動作**(此階段需 `deploy.bat`,非 copy.bat):
1. 跑 deploy.bat → bin 體積變小
2. 跑 bin\UARTPro.exe → 正常啟動、所有 UI 控件樣式正常(Basic style 完好)

---

## Stage 8 — 啟動空白 window 消除(S15,使用者回報)✅ 使用者測試 ok(DWM cloak,空白消失)
**採用方案 C(DWM cloaking)** — 比 splash 乾淨,零假延遲:
- main.cpp #ifdef Q_OS_WIN:`#include <dwmapi.h>` + `#pragma comment(lib,"dwmapi.lib")`
- 套好 frameless 後 `DwmSetWindowAttribute(hwnd, DWMWA_CLOAK, TRUE)` → setVisible(true) 仍 render 但對合成器隱形
- `frameSwapped`(Qt::SingleShotConnection,render thread→main queued)首幀畫好 uncloak;1s QTimer fallback 防永久隱形
- 保留 Stage 2.5 的 visible:false(擋原生白框)+ cloak(擋空白 surface),互補
**測試**:見下方
---
原方案備註(未採用):A=splash 動畫(加假延遲);B=延後 setVisible(仍可能閃)
**現象**:白框已解(Stage 2.5),但 setVisible 後**第一幀 QML 內容尚未 render**,window surface 暫顯空白(白)約一瞬再轉主題深色。
**根因**:`window->setVisible(true)` 在 scene graph 首幀 composite 前,OS 顯示未初始化 surface。
**方案選項**(到此階段再定):
- A. 使用者要的:開啟時跑 ~0.2s loading 動畫 splash,後台處理完才關 splash 顯示主介面
- B. 較省事:延後 setVisible 到首幀 render 完(QQuickWindow afterRendering/frameSwapped 或 short QTimer)
- C. Windows DWM cloaking(DWMWA_CLOAK)隱藏到首幀再 uncloak — 最乾淨無閃但較複雜
**測試**:冷啟動直接出現完整主介面,無空白 window 階段。

## Stage 6 — Canvas overlay 改 GPU(S6)⏸ medium
**檔案**:main.qml
**改動**:三張全窗軟體 Canvas(grid L450 + 2 scanline L3276/3075)改 cached ShaderEffect / tiled Image,或首次 requestPaint defer 出首幀
**測試**:背景 grid + scanline 視覺不變,啟動更順

---

## Stage 7 — overlay 一致縮放 + qmltc(G4 + S4)⏸ large 架構級
**檔案**:main.qml、CMakeLists.txt
**改動**:
- **G4**:棄 `scale: uiScale` transform,改全域 `px(n)=n*uiScale` token 乘進各尺寸/字級 → overlay Popup/Menu 一致縮放(連帶解 G3)
- **S4**:`qt_add_qml_module(... ENABLE_TYPE_COMPILER)` + 清 qmllint 警告
**測試**:全程縮放比例一致、各彈窗大小字級對齊主介面

---

## Leave-as-is(無須動作)
- S8 config load 同步 I/O:工作量小,timing 不可免
- S11 RX 早連 model:無 bug,timer boot 期未觸發
- S12 engine.load 同步編譯:qmlcachegen 已處理大頭
- S13 Qt6Network.dll:QtQuick 硬相依,**勿刪**
