# Agent 透過 per-PID named pipe attach 到執行中實例,CLI 而非 MCP,人機對等仲裁

Windows COM port 獨占,agent 無法在人開著 GUI 時另行開 port 互動;原本「存 log 檔讓 agent 讀」是單向且需人工協調。決定:每個實例(GUI 與 headless)開 `\\.\pipe\UARTPro.<pid>` 命令介面,同一顆 exe 的 `--attach` 子命令作為 client,agent 擁有完全控制(含 connect/disconnect/換 port)。

## Considered Options

- **介面形式**:選 `--attach` CLI 子命令,不選 MCP server(內建或外部 wrapper)。CLI 用 agent 既有的 shell 能力即可、零設定、CI 可用、人也能手動 debug;MCP 是其上的人體工學層,能力上不增加任何東西,留待未來。
- **仲裁模型**:選「對等 + 全程可視化」(agent 動作插 system 行 + toast + `[AGENT]` 徽章),不選授權開關、不選 session 互斥。內部工具、斷線代價低(有自動重連),真正的風險是「人看不懂發生什麼事」,用能見度解決,不用鎖。
- **pipe 命名**:per-PID(`UARTPro.<pid>`)+ 枚舉發現,因為多實例同開是常態;定址語意 `--pid` > `--port` > 唯一實例,定不出來就 exit 7 快速失敗(不自動 fallback headless、不自動拉起 GUI——行為可預測優先)。

## Consequences

- pipe 協議(NDJSON 動詞)是對外介面,同事的 script 會依賴,改動需向後相容。
- headless 也開 pipe,因此 HeadlessRunner 需要 entry 儲存(TerminalModel)才能服務 `tail`。
