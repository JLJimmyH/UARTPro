# UARTPro 核心資料路徑重構 + Agent CLI + UI/UX 強化 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把終端機資料層下放到 C++（QAbstractListModel + 批次化），修正正確性/效能問題，加上 headless/JSONL/--expect 的 agent CLI 閉環與文件，以及三項 UI/UX 改善。

**Architecture:** 新增 C++ `TerminalModel`（單一資料儲存、native filter、批次 insert、O(1)-amortized 修剪），`SerialPortManager::dataReceived` 在 GUI 模式直接接到 TerminalModel；QML 移除 `terminalEntries` JS array 與 `ListModel`，改走 model API。CLI 模式（`--list-ports` / `--headless`）走 `QCoreApplication`，不載 QML。

**Tech Stack:** Qt 6.7 (Quick / SerialPort), MSVC 2022 + Ninja，建構用 `build.bat`（全清重建）。本專案無測試 target——每個 task 的驗證是「build.bat 成功 + 啟動驗證/CLI 輸出驗證」。

**驗證指令共用:**
- Build: `cmd /c build.bat`（在專案根目錄），確認結尾無 error 且 `build/UARTPro.exe` 更新。
- GUI 煙霧測試: 用 bash 啟動 `./build/UARTPro.exe` 數秒後 kill，stderr 不得出現 `qrc:/qt/qml/UARTPro/main.qml` 的 QML error。
- 每個 task 完成後 `git add -A && git commit`（zh-tw 標題 + Co-Authored-By footer）。

---

### Task 1: ConfigManager 正確性修正

**Files:**
- Modify: `ConfigManager.cpp`

- [ ] **Step 1.1:** `saveToFile()`（ConfigManager.cpp:229-235）改用 `QSaveFile`（原子寫入）：

```cpp
#include <QSaveFile>   // 檔頭 include 區
...
    QJsonDocument doc(root);
    QSaveFile file(m_configFilePath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(doc.toJson(QJsonDocument::Indented));
        file.commit();
    }
```

- [ ] **Step 1.2:** `loadInternal()`（ConfigManager.cpp:185-186）把 `m_loading = false;` 移到 `emit configLoaded();` 之後（configLoaded 是 direct connection，QML `loadConfigToUI()` 的回寫在 emit 期間同步執行，期間 `scheduleSave()` 被 m_loading 擋住 → 載入不再觸發整檔回寫）。

- [ ] **Step 1.3:** Build + 煙霧測試 + commit `修正 config 原子寫入與載入時的多餘回寫`。

---

### Task 2: SerialPortManager 接收路徑強化

**Files:**
- Modify: `SerialPortManager.h`, `SerialPortManager.cpp`

不改 `dataReceived` signal 簽名（QML 在 Task 4 前仍直接使用）。

- [ ] **Step 2.1:** header 加成員與常數：

```cpp
    static const int MAX_LINE_BYTES = 4096;
    QTimer *m_idleFlushTimer;      // 50ms 無新資料 → flush 殘留
    QTimer *m_rxNotifyTimer;       // 200ms 節流 rxBytesChanged
private:
    void processRxBuffer(bool flushAll);
    void scheduleRxBytesNotify();
```

- [ ] **Step 2.2:** 建構子初始化兩個 timer：`m_idleFlushTimer` singleshot 50ms → 若 `m_rxBuffer` 非空呼叫 `processRxBuffer(true)`；`m_rxNotifyTimer` singleshot 200ms → `emit rxBytesChanged()`。

- [ ] **Step 2.3:** `handleReadyRead()` 改為：累計 bytes → `scheduleRxBytesNotify()`（timer 未跑才 start）→ append buffer → `processRxBuffer(false)` → 殘留非空則 `m_idleFlushTimer->start()` 否則 stop。

- [ ] **Step 2.4:** 新函式 `processRxBuffer(bool flushAll)`：單趟掃描（游標前進、`mid()` 取行、最後一次 `remove(0,pos)`），規則：`\n`=切、`\r\n`=切跳2、`\r`非結尾=切、`\r`在結尾且 !flushAll=等下一個 chunk；掃完無換行且剩餘 ≥ `MAX_LINE_BYTES` → 以 4096 為界強制切行；`flushAll` 時把剩餘整段 emit。

```cpp
void SerialPortManager::processRxBuffer(bool flushAll)
{
    int pos = 0;
    const int size = m_rxBuffer.size();
    while (pos < size) {
        int splitPos = -1, skipLen = 0;
        for (int i = pos; i < size; ++i) {
            char c = m_rxBuffer.at(i);
            if (c == '\n') { splitPos = i; skipLen = 1; break; }
            if (c == '\r') {
                if (i + 1 < size) { splitPos = i; skipLen = (m_rxBuffer.at(i + 1) == '\n') ? 2 : 1; }
                else if (flushAll) { splitPos = i; skipLen = 1; }
                break;   // 結尾孤立 \r 且 !flushAll: 等下一個 chunk
            }
        }
        if (splitPos < 0) {
            if (size - pos >= MAX_LINE_BYTES) {
                emitLine(m_rxBuffer.mid(pos, MAX_LINE_BYTES));
                pos += MAX_LINE_BYTES;
                continue;
            }
            break;
        }
        emitLine(m_rxBuffer.mid(pos, splitPos - pos));
        pos = splitPos + skipLen;
    }
    if (pos > 0)
        m_rxBuffer.remove(0, pos);
    if (flushAll && !m_rxBuffer.isEmpty()) {
        emitLine(m_rxBuffer);
        m_rxBuffer.clear();
    }
}
```

- [ ] **Step 2.5:** `disconnectPort()` 的手動 flush（132-135 行）改成 `processRxBuffer(true)` + 兩個 timer stop；`connectToPort()` 成功時 stop idle timer。

- [ ] **Step 2.6:** Build + 煙霧測試（連線收資料正常）+ commit `接收路徑強化: 行長上限/idle flush/rxBytes 節流`。

---

### Task 3: TerminalModel C++ 類別（先建好，不接 QML）

**Files:**
- Create: `TerminalModel.h`, `TerminalModel.cpp`
- Modify: `CMakeLists.txt`（qt_add_executable 來源清單）, `main.cpp`（GUI 路徑生成 + context property + connect）

- [ ] **Step 3.1:** 依以下介面實作（roles 名稱必須與 QML delegate required properties 一致）：

```cpp
struct TerminalEntry { QString timestamp, msgText, hexData, type; int entryIndex; };

class TerminalModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)            // 過濾後可見列數
    Q_PROPERTY(int totalCount READ totalCount NOTIFY totalCountChanged)  // 全部 entry 數
    Q_PROPERTY(int maxLines READ maxLines WRITE setMaxLines NOTIFY maxLinesChanged)
    Q_PROPERTY(bool filterActive READ filterActive NOTIFY filterActiveChanged)
public:
    // roles: timestamp / msgText / hexData / type / entryIndex
    Q_INVOKABLE void appendEntry(const QString &timestamp, const QString &msgText,
                                 const QString &hexData, const QString &type); // 進 pending
    Q_INVOKABLE QVariantMap get(int row) const;            // 可見列 → map
    Q_INVOKABLE void clear();                              // 全清 + nextIndex=0
    Q_INVOKABLE void setFilters(const QVariantList &filters); // [{text,filterType,enabled}]
    Q_INVOKABLE QVariantList search(const QString &query, bool isRegex, bool hexMode) const; // 回可見 row indices
    Q_INVOKABLE QVariantList entriesForExport(bool filteredOnly) const;
    Q_INVOKABLE QVariantList allEntries() const;
    Q_INVOKABLE QVariantList entryIndicesInRange(int loRow, int hiRow) const;
public slots:
    void appendRxLine(const QString &timestamp, const QString &asciiData, const QString &hexData); // type=rx
signals:
    void entriesAppended(const QVariantList &entries); // 每批所有 entry(含被過濾的) → QML 寫 log/autoscroll
    void trimmed(int removedCount, int removedMaxEntryIndex);
    // + countChanged / totalCountChanged / maxLinesChanged / filterActiveChanged
private:
    // m_all(全部) / m_visible(int 索引,遞增) / m_pending / m_includes,m_excludes(已 lowercase)
    // m_flushTimer: singleshot 16ms; append* 時若未啟動則 start
};
```

實作要點：
- `flushPending()`：pending 逐筆給 `entryIndex = m_nextIndex++` 入 `m_all`；通過 `matchesFilter` 的收集成連續區塊 → 一次 `beginInsertRows(visStart..visEnd)`；之後 `trimIfNeeded()`；emit `totalCountChanged`/`countChanged`/`entriesAppended(批次 maps)`。
- `matchesFilter`：`type=="system"||"error"` 永遠通過；include 非空時 OR 命中、exclude AND NOT（lowercase contains）— 與 main.qml:3417-3455 行為一致。
- `trimIfNeeded`：`m_all.size() > m_maxLines` 時 `removeCount = qMax(m_maxLines/10, m_all.size()-m_maxLines)`，記 `removedMaxEntryIndex = m_all[removeCount-1].entryIndex`；m_visible 前段 `< removeCount` 的 k 列 `beginRemoveRows(0,k-1)` 移除、其餘索引 -= removeCount；`m_all` 去頭；emit `trimmed`。
- `setFilters`：重建 includes/excludes → `beginResetModel` + 重算 m_visible + `endResetModel` → emit countChanged/filterActiveChanged。
- `setMaxLines`：設定後直接 `trimIfNeeded()`。
- `search`：`QRegularExpression`（CaseInsensitive；非 regex 用 `QRegularExpression::escape`；`isValid()` 失敗回空），逐可見列比對（hexMode 且 hex 非空時比 hex 否則 msgText），回傳 row index list。
- `clear`：同時清 pending + stop timer。

- [ ] **Step 3.2:** CMakeLists.txt 來源加 `TerminalModel.h TerminalModel.cpp`。

- [ ] **Step 3.3:** main.cpp（GUI 路徑）：生成 `TerminalModel terminalModel;`、`connect(&serialManager, &SerialPortManager::dataReceived, &terminalModel, &TerminalModel::appendRxLine);`、context property `"terminalModel"`。此時 QML 內部 `ListModel { id: terminalModel }` 會 shadow context property，行為不變。

- [ ] **Step 3.4:** Build + 煙霧測試 + commit `新增 C++ TerminalModel(QAbstractListModel 環形緩衝+native filter)`。

---

### Task 4: QML 遷移到 C++ TerminalModel（本計畫最大改動）

**Files:**
- Modify: `main.qml`

- [ ] **Step 4.1:** 刪 `property var terminalEntries: []`（187）、`property int entryIndexOffset: 0`（158）、`ListModel { id: terminalModel }`（2224）。

- [ ] **Step 4.2:** `addTerminalEntry` 改為轉呼叫 `terminalModel.appendEntry(timestamp, data, hexData || "", type)`（刪掉 3356-3415 原本的 logging/trim/filter/append 全部邏輯）。

- [ ] **Step 4.3:** 刪 `Connections.onDataReceived`（3311-3313，C++ 已直連）。新增：

```qml
Connections {
    target: terminalModel
    function onEntriesAppended(entries) {
        if (fileLogger.logging) {
            var lines = []
            for (var j = 0; j < entries.length; j++)
                lines.push(formatEntryForLog(entries[j]))
            fileLogger.logLines(lines)        // Task 6 提供; Task 4 期間暫用迴圈 logLine
        }
        if (root.autoScroll)
            terminalView.positionViewAtEnd()
    }
    function onTrimmed(removedCount, removedMaxEntryIndex) {
        var newSel = {}
        var keys = Object.keys(root.selectedSet)
        for (var k = 0; k < keys.length; k++)
            if (parseInt(keys[k]) > removedMaxEntryIndex) newSel[keys[k]] = true
        root.selectedSet = newSel
        root.selectionVersion++
        if (root.searchMatches.length > 0) { root.searchMatches = []; root.searchCurrentIndex = -1 }
    }
}
```
（Task 4 階段 `fileLogger.logLines` 尚不存在 → 先用 `for ... fileLogger.logLine(...)`，Task 6 換批次。）

- [ ] **Step 4.4:** filter 同步改 debounce + C++：刪 `passesFilter`/`rebuildFilteredModel`/`syncFiltersToConfig`，新增：

```qml
function scheduleFilterSync() { Qt.callLater(syncFiltersNow) }
function syncFiltersNow() {
    var list = []
    for (var i = 0; i < filterModel.count; i++) {
        var item = filterModel.get(i)
        list.push({ text: item.text, filterType: item.filterType, enabled: item.enabled })
    }
    terminalModel.setFilters(list)
    configManager.setFilters(list)
    clearSelection()
    if (root.searchBarVisible && root.searchQuery !== "") performSearch()
    if (root.autoScroll) terminalView.positionViewAtEnd()
}
```
取代所有呼叫點（`rebuildFilteredModel()` 與 `syncFiltersToConfig()` 成對或單獨出現處全換成 `scheduleFilterSync()`）：227（filterModel.onCountChanged）、1438-1440、1473-1475、1512-1515、1533、1585-1587、1620-1622、1659-1662、1680、3921（addFilter）。

- [ ] **Step 4.5:** `performSearch` 中段迴圈（3494-3500）換成 `var matches = terminalModel.search(q, root.searchRegex, root.hexDisplayMode)`，並刪掉 try/catch regex 建構（C++ 處理）。`matches` 為 QVariantList → 後續 `matches.length`/`matches[0]` 照用。

- [ ] **Step 4.6:** 其餘 `terminalEntries` 引用改寫：
  - BUF 顯示（3026, 3030）→ `terminalModel.totalCount`
  - `logExistingEntriesToFile`（3349-3354）→ `var entries = terminalModel.allEntries()` 後同樣格式化（Task 6 換批次 API）
  - `copySelectedEntries`（3831-3841）→ 迭代 `terminalModel.allEntries()`
  - `collectExportEntries`（4001-4017）→ `return terminalModel.entriesForExport(root.exportMode === "filtered")`
  - `clearTerminal`（3709-3714）→ `terminalModel.clear(); clearSelection()`

- [ ] **Step 4.7:** 拖曳多行選取（2679-2686）換成一次跨界呼叫：

```qml
var idxList = terminalModel.entryIndicesInRange(lo, hi)
var s = {}
for (var i = 0; i < idxList.length; i++) s[idxList[i]] = true
root.selectedSet = s
root.selectionVersion++
```

- [ ] **Step 4.8:** maxLines 接線：`onMaxBufferLinesChanged`（184）追加 `terminalModel.maxLines = maxBufferLines`；`Component.onCompleted` 在 `loadConfigToUI()` 後加 `terminalModel.maxLines = root.maxBufferLines`。

- [ ] **Step 4.9:** Build + 完整煙霧測試（啟動訊息出現、連線收資料、filter chip 增刪、搜尋、Ctrl+A/複製、clear、logging 開關、buffer 修剪不炸）+ commit `終端機資料層下放 C++ TerminalModel`。

---

### Task 5: QML 效能修正（regex 快取 + searchMarkerBar Canvas）

**Files:**
- Modify: `main.qml`

- [ ] **Step 5.1:** keyword regex 快取：

```qml
property var _kwCache: ({ rev: -1, hl: [], line: [] })
function getKeywordCache() {
    if (_kwCache.rev === root.keywordRevision) return _kwCache
    var hl = [], line = []
    for (var i = 0; i < keywordModel.count; i++) {
        var kw = keywordModel.get(i)
        if (!kw.enabled) continue
        if (kw.mode === "line")
            line.push({ text: kw.text.toLowerCase(), color: kw.color })
        else
            hl.push({ re: new RegExp("(<[^>]+>)|(" + escapeRegex(escapeHtml(kw.text)) + ")", "gi"),
                      color: kw.color, mode: kw.mode })
    }
    _kwCache = { rev: root.keywordRevision, hl: hl, line: line }
    return _kwCache
}
readonly property var _numberRe: /(<[^>]+>)|(\b(?:0x[0-9a-fA-F]+|\d+\.?\d*)\b)/g
```
`highlightText` 改用 `getKeywordCache().hl`（replace 用 `entry.re`，色彩/模式取自 entry）；數字著色改用 `_numberRe`；`getLineHighlightColor` 改用 `getKeywordCache().line`。

- [ ] **Step 5.2:** searchMarkerBar（2852-2879）Repeater 換單一 Canvas：onPaint 以 `terminalModel.count` 為比例畫一般命中（rgba(255,170,0,0.6)）與當前命中（#ffaa00），`root.onSearchMatchesChanged` / `root.onSearchCurrentIndexChanged` / `terminalModel.onCountChanged`（visible 時）requestPaint。

- [ ] **Step 5.3:** Build + 煙霧測試（keyword 高亮/行高亮/搜尋標記照常）+ commit `QML 效能: keyword regex 快取與搜尋標記 Canvas 化`。

---

### Task 6: FileLogger 批次 + JSONL 格式

**Files:**
- Modify: `FileLogger.h`, `FileLogger.cpp`, `main.qml`（logging 分支）, `main.cpp`（cmdLineFormat context property，與 Task 7 合併亦可）

- [ ] **Step 6.1:** FileLogger 增加：

```cpp
Q_PROPERTY(QString format READ format NOTIFY formatChanged)   // "text" | "jsonl"
Q_INVOKABLE bool startLogging(const QString &filePath, const QString &format = QStringLiteral("text"));
Q_INVOKABLE void logLines(const QStringList &lines);          // 批次寫入(text)
Q_INVOKABLE void logStructured(const QString &type, const QString &ascii, const QString &hex);
// 內部: qint64 m_seq = 0; startLogging 時歸零
```
- `logStructured`：寫一行 compact JSON：`{"ts":"<ISO8601 含毫秒,QDateTime::currentDateTime().toString(Qt::ISODateWithMs)>","seq":N,"type":"rx","ascii":"...","hex":"..."}`（hex 空字串時省略欄位）。
- jsonl 模式時 session header/footer 改為 JSONL 事件列（保持檔案整體合法 JSONL）：`{"ts":"...","type":"session","event":"start","app":"UARTPro","version":"x.y.z"}` / `"event":"stop"`。

- [ ] **Step 6.2:** main.qml：`onEntriesAppended` 與 `logExistingEntriesToFile` 改為依 `fileLogger.format` 分支——jsonl 時逐筆 `fileLogger.logStructured(e.type, e.msgText, e.hexData)`，text 時 `fileLogger.logLines(lines 批次)`。`cmdLineTimer` 的 `fileLogger.startLogging(cmdLineRecord)` 改為 `fileLogger.startLogging(cmdLineRecord, cmdLineFormat)`（context property，Task 7 提供；先以 `typeof cmdLineFormat !== "undefined" ? cmdLineFormat : "text"` 防呆或於 Task 7 同步加上）。

- [ ] **Step 6.3:** Build + 測試（GUI 開 logging、確認 text log 正常）+ commit `FileLogger 批次寫入與 JSONL 格式`。

---

### Task 7: CLI — --list-ports / --headless / --expect / exit codes

**Files:**
- Create: `HeadlessRunner.h`, `HeadlessRunner.cpp`
- Modify: `main.cpp`, `CMakeLists.txt`

**Exit code 慣例:** 0=正常/expect 命中/手動結束、2=port 開啟失敗、3=record 檔開啟失敗、4=timeout、5=expect-fail 命中。GUI 模式維持原行為（不因連線失敗退出）。

- [ ] **Step 7.1:** main.cpp 開頭 pre-scan `argv` 是否含 `--list-ports` / `--headless`，是則走 `QCoreApplication` 分支；加 console 接管 helper（WIN32_EXECUTABLE=GUI subsystem）：

```cpp
#ifdef Q_OS_WIN
static void initConsoleIO() {
    HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h == nullptr || h == INVALID_HANDLE_VALUE) {
        if (AttachConsole(ATTACH_PARENT_PROCESS)) {
            FILE *f;
            freopen_s(&f, "CONOUT$", "w", stdout);
            freopen_s(&f, "CONOUT$", "w", stderr);
        }
    }
}
#endif
```

- [ ] **Step 7.2:** QCommandLineParser 新選項：`--headless`、`--list-ports`、`--stdout`（即時 JSONL 串流到 stdout）、`--format <text|jsonl>`（套用到 --record）、`--expect <regex>`、`--expect-fail <regex>`、`--timeout <seconds>`。

- [ ] **Step 7.3:** `--list-ports`：`QSerialPortInfo::availablePorts()` → JSON array（`port`/`description`/`manufacturer`）compact 印 stdout → return 0。

- [ ] **Step 7.4:** `HeadlessRunner`：持有 SerialPortManager + FileLogger。`start()`：connect 失敗 → stderr JSON + return 2；record 開檔失敗 → return 3；timeout 啟動 QTimer。`dataReceived` slot：record（text → `logEntry(iso,"rx",ascii,hex)`；jsonl → `logStructured`）、`--stdout` 印 JSONL 行 + `fflush(stdout)`、expect/expect-fail `QRegularExpression` 比對 → `finish(0|5)`。`connectionLost`/`reconnected` 寫 event 列。`finish(code)`：stopLogging → 印 `{"event":"exit","code":N,"reason":"..."}` → `QCoreApplication::exit(code)`。Ctrl+C：`SetConsoleCtrlHandler` → `QMetaObject::invokeMethod(qApp, "quit", Qt::QueuedConnection)`；`aboutToQuit` 接 stopLogging。

- [ ] **Step 7.5:** GUI 分支保持原樣 + context property `cmdLineFormat`。CMakeLists 加 HeadlessRunner 來源。

- [ ] **Step 7.6:** 驗證（bash）：
  - `./build/UARTPro.exe --list-ports` → 印出 JSON、exit 0
  - `./build/UARTPro.exe --headless --port COM_NOT_EXIST --baud 115200` → exit 2
  - `./build/UARTPro.exe --headless --port <實際無裝置時跳過> --timeout 2` → exit 4（無硬體時此條僅驗證 timeout 機制可跳過）
- [ ] **Step 7.7:** Commit `新增 headless CLI: list-ports/expect/timeout/JSONL 串流與 exit codes`。

---

### Task 8: UI/UX 三項

**Files:**
- Modify: `main.qml`

- [ ] **Step 8.1:** ENTRIES 顯示（1989-1995）：filter 生效時 `count + "/" + totalCount + " ENTRIES"`，前面加 `[FILTERED]`（#ffaa00, bold, visible: terminalModel.filterActive）。

- [ ] **Step 8.2:** chip ToolTip（全部 `ToolTip.delay: 600`，MouseArea 需 `hoverEnabled: true`）：
  - keyword chip 本體 MA（1288）：`"Click: enable/disable · Double-click: edit"`
  - 色塊 MA（1308）：`"Change color"`
  - BG/FG/LN MA（1328）：`"Highlight mode — BG: background / FG: text / LN: full line. Click to cycle"`
  - EyeIcon MA（1357）：`"Show / hide highlight"`
  - ✕ MA（1377）：`"Remove"`
  - include/exclude chip 本體 MA（1468、1615）：`"Click: enable/disable · Double-click: edit"`；眼睛：`"Enable / disable filter"`；✕：`"Remove"`

- [ ] **Step 8.3:** chip 雙擊編輯（recall 進輸入框）。root 加 `property string _pendingKwColor: ""`、`property string _pendingKwMode: ""`；`addKeyword` 開頭消費這兩個值（非空就用並清空，否則走原本 palette 輪轉）。
  - keyword chip 本體 MA `onDoubleClicked`：`filterTypeCombo.currentIndex = 0; root._pendingKwColor = model.color; root._pendingKwMode = model.mode; filterInput.text = model.text; keywordModel.remove(index); filterInput.forceActiveFocus(); filterInput.cursorPosition = filterInput.text.length`
  - include/exclude chip 本體 MA `onDoubleClicked`：`filterTypeCombo.currentIndex = 1; filterSubTypeCombo.currentIndex = (model.filterType === "include") ? 0 : 1; filterInput.text = model.text; filterModel.remove(index); filterInput.forceActiveFocus(); ...`

- [ ] **Step 8.4:** 快捷鍵（Space block 後新增）：F1 → `root.helpPopupVisible = true`；F3 / Shift+F3 → `if (root.searchMatches.length > 0) jumpToMatch(±1)`；End →（輸入框 focus 時 return）`root.autoScroll = true; terminalView.positionViewAtEnd()`；Ctrl+S → `toggleLogging()`。新函式 `toggleLogging()` 抽自 LOG TO FILE 按鈕（1793-1802），按鈕改呼叫之。

- [ ] **Step 8.5:** help 清單（3235-3249）加：`F1 = Show this help`、`F3 / Shift+F3 = Next / previous search match`、`End = Jump to latest`、`Ctrl+S = Start / stop logging`、`Ctrl+A = Select all`、`Double-click chip = Edit keyword / filter`。

- [ ] **Step 8.6:** Build + 煙霧測試 + commit `UI/UX: FILTERED 計數/chip 提示與編輯/快捷鍵補齊`。

---

### Task 9: 文件

**Files:**
- Create: `AGENT_INTEGRATION.md`
- Modify: `CLAUDE.md`

- [ ] **Step 9.1:** `AGENT_INTEGRATION.md`（zh-tw）內容：工具定位、CLI 參數總表（含既有四個 + 新增）、exit codes 表、JSONL schema（含 session 事件列）、使用範例（燒錄驗證閉環一行命令、長時間掛機錄製、`--stdout` pipe 即時讀、`--list-ports` 機器決策）、Windows GUI subsystem 等待行為注意（bash 直接可用；PowerShell 用 `Start-Process -Wait -PassThru`；cmd 用 `start /wait`）、未來規劃（QLocalServer IPC、MCP wrapper、keyword 觸發器——含設計草稿）。

- [ ] **Step 9.2:** CLAUDE.md 更新：CLI 參數段補新選項與 exit codes（指向 AGENT_INTEGRATION.md）、架構段補 TerminalModel / HeadlessRunner、QML 段移除 terminalEntries 雙儲存描述。

- [ ] **Step 9.3:** Commit `新增 agent 串接文件並更新 CLAUDE.md`。

---

### Task 10: 最終驗證

- [ ] `cmd /c build.bat` 全清重建成功 → `cmd /c copy.bat` 更新 bin/。
- [ ] `./bin/UARTPro.exe --list-ports` 輸出正常。
- [ ] GUI 啟動煙霧測試（無 QML error）。
- [ ] `git log --oneline` 確認各 task commit 齊全。

## Self-Review 記錄

- Spec 覆蓋：核心資料路徑（Task 3/4）✓、程式碼最佳化（Task 1/2/5 + Task 4 內含修剪/批次）✓、agent 串接批次 1+2 + 文件（Task 6/7/9）✓、UI/UX 三項 + F1 help（Task 8）✓。IPC/MCP/觸發器明確降為文件中的未來規劃（範圍決策，回報時說明）。
- 型別一致性：`terminalModel.search(q, bool, bool)` / `entriesForExport(bool)` / `allEntries()` / `entryIndicesInRange(lo,hi)` 等在 Task 3 定義與 Task 4 呼叫一致；`fileLogger.logLines(QStringList)`、`logStructured(type,ascii,hex)`、`format` 在 Task 6 定義與 Task 4/6 呼叫一致（Task 4 期間以 logLine 迴圈過渡）。
- 無 placeholder：各 task 含完整關鍵碼或精確改寫位置（行號以 2026-06-11 的 main.qml 為準）。
