# UARTPro

Windows 串列埠終端機:人透過 GUI、agent 透過 CLI/IPC,共同觀察與操作同一條 UART 連線。

## Language

### Agent 整合

**實例 (Instance)**:
一個執行中的 UARTPro process,GUI 或 headless 模式皆算;以 PID 識別,各自持有至多一條串列埠連線。
_Avoid_: session、視窗

**Attach**:
Agent 連上某個執行中實例的命令介面、共用其連線的行為;實例不在跑就快速失敗,不會代為啟動。
_Avoid_: remote control、接管

**對等仲裁 (Peer arbitration)**:
人與 agent 對連線有相同權限,誰後下命令誰生效,不互鎖;安全性由可視化(system 行、toast、AGENT 徽章)承擔,不由授權機制承擔。
_Avoid_: 授權模式、鎖定

**動詞 (Verb)**:
`--attach` 後的第一個位置參數,對應 wire protocol 的一個 `cmd`(list/status/connect/disconnect/send/tail/subscribe/expect)。

### 資料層

**Entry**:
終端機資料的最小單位——一行,含 timestamp、type(rx/tx/system/error)、原始 bytes 與全域遞增的 entry index。
_Avoid_: line(與畫面折行混淆)、message

**Entry index (idx)**:
實例內全域遞增的 entry 序號,CLEAR 後歸零;attach 串流與增量讀取的游標。
_Avoid_: seq(保留給記錄檔內的序號)
