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
| `--expect-fail <regex>` | headless | 收到符合 regex 的行 → exit 5(優先於 `--expect`) |
| `--timeout <seconds>` | headless | 超過秒數未命中 → exit 4 |

## Exit codes(`--headless` / `--list-ports`)

| Code | 意義 |
|------|------|
| 0 | 正常結束 / `--expect` 命中 / Ctrl+C 手動中斷 |
| 2 | port 開啟失敗,或 `--headless` 缺 `--port` |
| 3 | `--record` 檔案開啟失敗 |
| 4 | `--timeout` 逾時 |
| 5 | `--expect-fail` 命中 |

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

## Windows 等待行為注意

UARTPro.exe 是 GUI subsystem 執行檔:

- **bash(git-bash / Claude Code Bash tool)**:直接執行即會等待、可拿 `$?`、可 pipe——上述範例皆可直接使用。
- **PowerShell**:互動執行不等待。需要 exit code 時用
  `$p = Start-Process bin\UARTPro.exe -ArgumentList '--headless','--port','COM3','--timeout','10' -Wait -PassThru; $p.ExitCode`
- **cmd**:`start /wait bin\UARTPro.exe --headless ... & echo %errorlevel%`
- stdout 重導向(`> file` 或 pipe)在三種 shell 下都正常,因為 handle 由父行程繼承。

## 未來規劃(設計草稿,尚未實作)

1. **QLocalServer IPC**(named pipe `\\.\pipe\UARTPro`):GUI 與 headless 模式都開一個本機命令介面(NDJSON request/response:`connect` / `send` / `tail N` / `subscribe` / `status`),解決 Windows COM port 獨占——人看 UI、agent 透過 IPC 共用同一條連線。
2. **MCP server wrapper**:獨立的 Python/Node thin wrapper,把 IPC 命令包成 MCP tools(`list_ports` / `connect` / `send` / `read_lines(since_seq)` / `wait_for_pattern(regex, timeout)`),在專案 `.mcp.json` 註冊後 Claude Code 即可直接操作串列埠。
3. **Keyword 觸發器**:keyword schema 擴充 `action`(command / webhook),命中即執行,含 cooldown 防止 log 洗版時連續觸發。適合無人值守 overnight 測試。
