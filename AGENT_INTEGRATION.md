# UARTPro × AI Agent / 自動化整合指南

UARTPro 除了 GUI 串列埠終端機之外,內建可被 script / CI / AI agent(如 Claude Code)直接驅動的 CLI 能力。本文件描述 CLI 介面、exit code 慣例、JSONL 格式,以及典型自動化工作流。

## CLI 參數總表

| 參數 | 模式 | 說明 |
|------|------|------|
| `--config <path>` | GUI | 指定設定檔路徑(預設為執行檔旁的 `uartpro_config.json`) |
| `--port <COMx>` | GUI / headless | 啟動時自動連線的 port |
| `--baud <rate>` | GUI / headless | 連線 baud rate(headless 預設 115200) |
| `--record <filePath>` | GUI / headless | 啟動即開始記錄到指定檔案 |
| `--format <text\|jsonl>` | GUI / headless | `--record` 的格式,預設 `text` |
| `--list-ports` | CLI | 以 JSON 印出可用 port 清單後退出(不開 UI) |
| `--headless` | CLI | 無 UI 模式,需搭配 `--port` |
| `--stdout` | headless | 每收到一行即印一筆 JSONL 到 stdout(即時 flush,可 pipe) |
| `--expect <regex>` | headless | 收到符合 regex 的行 → exit 0 |
| `--expect-fail <regex>` | headless / attach | 收到符合 regex 的行 → exit 5(優先於 `--expect`) |
| `--timeout <seconds>` | headless / attach | 超過秒數未命中 → exit 4 |
| `--attach <動詞> [...]` | attach | 連上「執行中的 UARTPro 實例」下命令(共用其連線),詳見下方「Attach 模式」 |
| `--pid <N>` | attach | 定址:指定目標實例的 PID |

## Exit codes(`--headless` / `--list-ports` / `--attach`)

| Code | 意義 |
|------|------|
| 0 | 正常結束 / `--expect` 或 attach `expect` 命中 / Ctrl+C 手動中斷 |
| 2 | port 開啟失敗,或 `--headless` 缺 `--port`;attach 的 `connect`/`send` 失敗 |
| 3 | `--record` 檔案開啟失敗 |
| 4 | `--timeout` 逾時 |
| 5 | `--expect-fail` 命中 |
| 6 | 參數無效:`--baud`/`--timeout` 非正整數、regex 無效、attach 動詞未知(stderr 有 JSON 錯誤細節) |
| 7 | attach 無法定位目標實例(無實例在跑 / 多實例但未指定 / 指定條件無匹配) |

GUI 模式維持原行為:自動連線失敗只顯示在畫面上,程式不退出。

## JSONL 格式

`--format jsonl` 的記錄檔與 `--stdout` 串流,每行一個 JSON object:

```json
{"ts":"2026-06-11T14:03:22.123","seq":1234,"type":"rx","ascii":"Boot OK","hex":"42 6F 6F 74 20 4F 4B"}
```

| 欄位 | 說明 |
|------|------|
| `ts` | ISO8601 含毫秒(含日期——overnight log 可正確排序) |
| `seq` | 記錄檔內遞增序號(增量讀取用;`--stdout` 串流無此欄位) |
| `type` | `rx` / `tx` / `system` / `error`;另有 `session`(檔頭尾)、`event`、`exit`(headless 狀態) |
| `ascii` | 行內容(不可列印字元已替換為 `.`) |
| `hex` | 原始 bytes 的 hex 表示(空資料時省略) |

headless 模式的狀態列(stdout):

```json
{"ts":"...","type":"event","event":"start","detail":"COM3 @ 115200"}
{"ts":"...","type":"event","event":"connection-lost"}
{"ts":"...","type":"event","event":"reconnected"}
{"ts":"...","type":"exit","code":0,"reason":"expect matched","line":"Boot OK"}
```

注意:GUI 模式下 JSONL 的 `ts` 為寫入時間,因批次化可能與實際接收時間相差 ≤16ms;headless 模式為逐行即時寫入。

## 典型工作流

### 1. 燒錄 → 驗證開機 log → 回報(一行閉環)

```bash
flash_tool write firmware.bin && \
./bin/UARTPro.exe --headless --port COM3 --baud 115200 \
    --record boot.jsonl --format jsonl \
    --expect "Boot OK" --expect-fail "panic|assert|Boot fail" --timeout 15
echo "exit=$?"   # 0=開機成功, 5=開機失敗, 4=逾時
```

失敗時 `boot.jsonl` 可直接餵給 LLM 做 root cause 分析。

### 2. Agent 決策用 port 清單

```bash
./bin/UARTPro.exe --list-ports
# [{"port":"COM3","description":"USB Serial Port","manufacturer":"FTDI"}]
```

### 3. 即時 pipe 串流

```bash
./bin/UARTPro.exe --headless --port COM3 --baud 921600 --stdout | grep -m1 "ERROR"
```

### 4. 長時間掛機錄製(自動重連)

```bash
./bin/UARTPro.exe --headless --port COM3 --record overnight.jsonl --format jsonl
# 拔線自動重連(沿用 GUI 的 1.5s 重試機制), Ctrl+C 結束並寫 session footer
```

### 5. GUI 模式自動化啟動

```bash
./bin/UARTPro.exe --port COM3 --baud 921600 --record session.log
```

## Attach 模式(共用執行中實例的連線)

Windows 的 COM port 是獨占開啟:GUI 開著時,第二個 process(headless 或其他工具)開不了同一個 port。Attach 模式讓 agent 直接對「執行中的 UARTPro 實例」下命令——人看 UI、agent 透過 IPC 共用同一條連線。人與 agent **對等**(誰後下命令誰生效,不互鎖),代價由**可視化**支付:agent 的動作在 UI 以 system 行 + toast 呈現,terminal 標頭顯示 `[AGENT]` 徽章。

### IPC 介面

每個 UARTPro 實例(GUI 與 headless 都算)啟動時建立 named pipe `\\.\pipe\UARTPro.<pid>`(QLocalServer;協議為 NDJSON,一行一個 JSON object)。`--attach` 是同一顆 exe 內建的 client,一般情況不需要直接碰 pipe;非 Qt 工具也可以自行連 pipe 說同一套協議(見文末 wire protocol)。

### 定址(多實例)

同時開多個 UARTPro 是常態,`--attach` 依下列優先序挑目標實例:

1. `--pid <N>` — 指定 PID,最明確
2. `--port <COMx>` — 挑「目前採著 COMx」的實例
3. 都沒給 — 恰好一個實例在跑就用它;0 個或多個 → exit 7(stderr 有 JSON 錯誤細節)

`--attach list` 枚舉所有實例,agent 可先看再挑。

### 動詞

| 動詞 | 參數 | 說明 |
|------|------|------|
| `list` | — | 枚舉執行中實例(JSON array),不需定址 |
| `status` | — | 目標實例狀態(JSON object:pid/mode/port/baud/connected/reconnecting/rxBytes/txBytes/totalLines/version) |
| `connect` | `<COMx> [baud]` | 要求實例開啟連線(8N1;baud 預設 115200) |
| `disconnect` | — | 要求實例斷線 |
| `send` | `<data> [--hex] [--eol none\|cr\|lf\|crlf]` | 送出資料;預設附 `crlf`;`--hex` 時 `<data>` 為 hex 字串(如 `"01 A0 FF"`)且不附行尾 |
| `tail` | `[N]` | 最近 N 行(預設 50;取原始資料,不受 UI filter 影響),以 JSONL 印出 |
| `subscribe` | — | 即時串流之後的每一行(JSONL),Ctrl+C 結束 |
| `expect` | `<regex> [--expect-fail <regex>] [--timeout <sec>]` | 阻塞等待命中:`<regex>` 命中 exit 0、`--expect-fail` 命中 exit 5、逾時 exit 4 |

### JSONL 行格式(tail / subscribe / expect)

`{"ts":"yyyy-MM-dd HH:mm:ss.zzz","idx":N,"type":"rx|tx|system|error","ascii":"...","hex":"..."}`

`idx` 為實例內全域遞增的 entry index(CLEAR 後歸零),同一實例內可當增量讀取的游標。

### 範例

```bash
# agent 探索環境
./bin/UARTPro.exe --attach list
# [{"pid":1234,"mode":"gui","port":"COM4","baud":921600,"connected":true,...}]

# 人在看 COM4 的 UI,agent 直接下測試命令並等結果(閉環)
./bin/UARTPro.exe --attach --port COM4 send "reboot"
./bin/UARTPro.exe --attach --port COM4 expect "Boot OK" --expect-fail "panic|assert" --timeout 15

# 撈最近 200 行給 LLM 分析(不用先叫人存檔)
./bin/UARTPro.exe --attach --port COM4 tail 200 > snapshot.jsonl

# 完全控制:要求該實例換連到另一個 port
./bin/UARTPro.exe --attach --pid 1234 connect COM7 115200
```

### Wire protocol(自行實作 client 時)

request 一行一個 JSON object:

```json
{"cmd":"status"}
{"cmd":"connect","port":"COM4","baud":921600}
{"cmd":"disconnect"}
{"cmd":"send","data":"reboot","hex":false,"eol":"crlf"}
{"cmd":"tail","count":50}
{"cmd":"subscribe"}
{"cmd":"expect","pattern":"Boot OK","failPattern":"panic","timeoutSec":15}
```

response 為 `{"ok":true,...}` 或 `{"ok":false,"error":"..."}`;`tail` 的 ok 之後跟著 JSONL 行、最後一行 `{"done":true}`;`subscribe`/`expect` 的 ok 之後持續串流 JSONL;`expect` 結束時送 `{"result":"matched"|"failed"|"timeout","line":"..."}` 後斷線。一條連線進入 `subscribe`/`expect` 後即為串流專用,不再接受其他命令。

## Windows 等待行為注意

UARTPro.exe 是 GUI subsystem 執行檔:

- **bash(git-bash / Claude Code Bash tool)**:直接執行即會等待、可拿 `$?`、可 pipe——上述範例皆可直接使用。
- **PowerShell**:互動執行不等待。需要 exit code 時用
  `$p = Start-Process bin\UARTPro.exe -ArgumentList '--headless','--port','COM3','--timeout','10' -Wait -PassThru; $p.ExitCode`
- **cmd**:`start /wait bin\UARTPro.exe --headless ... & echo %errorlevel%`
- stdout 重導向(`> file` 或 pipe)在三種 shell 下都正常,因為 handle 由父行程繼承。

## 未來規劃(設計草稿,尚未實作)

1. **MCP server wrapper**:把 attach 動詞包成 MCP tools(`list_ports` / `connect` / `send` / `read_lines` / `wait_for_pattern`),在專案 `.mcp.json` 註冊後 Claude Code 以 tools 形式操作。CLI `--attach` 已涵蓋全部能力,此項純屬人體工學。
2. **Keyword 觸發器**:keyword schema 擴充 `action`(command / webhook),命中即執行,含 cooldown 防止 log 洗版時連續觸發。適合無人值守 overnight 測試(有了 attach `expect`,agent 自行監聽也可達成,優先度下降)。
