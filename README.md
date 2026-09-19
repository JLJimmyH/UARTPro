# UARTPro

無邊框的串列埠終端機,Windows 與 macOS 都能跑。Qt 6 + QML。

## 下載

到 [Releases](https://github.com/JLJimmyH/UARTPro/releases) 拿。macOS 版是 universal binary,Apple Silicon 和 Intel 共用一個檔。

macOS 第一次開會被 Gatekeeper 擋(只有 ad-hoc 簽名),右鍵 → 開啟,或:

```bash
xattr -dr com.apple.quarantine /Applications/UARTPro.app
```

## 功能

- 關鍵字高亮、過濾、搜尋
- 跨行拖曳選取與複製
- 記錄成 text 或 jsonl
- 斷線自動重連、裝置熱插拔偵測
- CLI 與 headless 模式,可被腳本或 agent 驅動

## 建構

需要 Qt 6.2 以上,含 Qt Serial Port 模組。

macOS:

```bash
./build.sh                            # 增量建構
./build.sh clean universal deploy     # 可發佈的 universal .app
```

Qt 路徑取 `$QT_ROOT`,沒設就自動找 `~/Qt/6.*/macos`。

Windows:

```
build.bat && deploy.bat
```

產出在 `bin\`。

## 自動化

`--list-ports`、`--headless`、`--attach` 等 CLI 用法、exit code 與 JSONL schema 見 [AGENT_INTEGRATION.md](AGENT_INTEGRATION.md)。

## 授權

GPLv3,見 [LICENSE](LICENSE)。

```
Copyright (C) 2026 JLJimmyH

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.
```

本程式連結 Qt,Qt 以 LGPLv3 授權(見 [qt.io/licensing](https://www.qt.io/licensing))。散布二進位檔時請保留此聲明,並讓使用者有辦法替換掉 Qt 函式庫。
