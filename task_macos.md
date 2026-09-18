# UARTPro macOS 移植進度

目標:同一份 code 出 Windows 與 macOS 版,macOS 需同時支援 Intel(x86_64)與 Apple Silicon(arm64)。

狀態圖示:⬜ 未開始 / 🔧 進行中 / ✅ 完成已驗 / ⏳ 待實機驗證 / ⏸ 延後

> 本檔只進 git(GitHub `JLJimmyH/UARTPro`),不進 SVN。

---

## 現況(2026-09-18)

✅ **CI 全綠,universal DMG 已可下載**

- commit 範圍:`fd66c22` → `5ba9842`(5 個 commit,已 push master)
- CI:[GitHub Actions macOS Build](https://github.com/JLJimmyH/UARTPro/actions) — 每次 push 自動跑
- 產出:`UARTPro-macOS-universal-0.2.6.dmg`(46.7 MB,artifact)

Qt 官方 macOS binary 本身是 universal,所以 `-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"`
在一台機器(或一個 CI runner)上就能同時出兩種架構,不需要兩台機器。

---

## Mac 上要做的步驟

```bash
xcode-select --install                  # 若還沒裝過
# 裝 Qt 6.7.3 macOS,務必勾 Qt Serial Port

git clone https://github.com/JLJimmyH/UARTPro.git
cd UARTPro
./build.sh deploy
open build/UARTPro.app
```

- 找不到 Qt:`QT_ROOT=~/Qt/6.7.3/macos ./build.sh deploy`
- 不想裝 Qt:直接去 Actions 頁下載 DMG
- CLI 模式走 bundle 內執行檔:`build/UARTPro.app/Contents/MacOS/UARTPro --list-ports`

---

## 已完成 ✅

| 項目 | 做法 |
|------|------|
| CMake 平台化 | `app.rc` 收進 `if(WIN32)`;加 `MACOSX_BUNDLE` 與 bundle metadata;版本號從 `version.h` regex 取得 |
| CI | `.github/workflows/macos.yml`,macos-14 runner。失敗時把編譯錯誤貼成 commit comment(job log 要 repo admin 權限才下載得到) |
| 無邊框視窗 | 新增 [MacWindow.mm](MacWindow.mm):NSWindow titlebar 透明化 + `FullSizeContentView`。**macOS 不能用 `FramelessWindowHint`** — 會失去紅綠燈/全螢幕,且 Qt 在 cocoa 沒實作 `startSystemResize()` |
| 設定檔路徑 | macOS 改 `AppConfigLocation`(bundle 內簽章後不可寫);Windows 維持 exe 同目錄的綠色版行為 |
| 熱插拔 | macOS 無 `WM_DEVICECHANGE`,改 2 秒輪詢;`refreshPorts()` 改為清單未變就不發 signal |
| CLI Ctrl+C | 非 Windows 走 SIGINT/SIGTERM + atomic 旗標 + timer 收尾(signal handler 內不能呼叫 Qt API) |
| attach IPC | 加 unix socket 分支;socket 檔不像 named pipe 會自動消失,逐一試連濾掉殘留 |
| 等寬字型 | macOS 用 Menlo(Consolas 在 mac 會 fallback 成非等寬,字元對齊全毀) |
| build.sh | `clean` / `universal` / `deploy` 可組合;`.gitattributes` 鎖 LF 防 CRLF 汙染 shebang |
| 文件 | CLAUDE.md、QMLDesign.md、AGENT_INTEGRATION.md 都補了 macOS 章節 |

Windows 端已驗證不受影響:建構通過、`--list-ports` 正常、`--attach list` 正常、GUI 截圖確認埠清單正常。

---

## 待實機驗證 ⏳

CI 只能證明「編得過、打得包」,跑起來對不對要在 Mac 上看:

- ⏳ titlebar 隱藏後自訂標題列的視覺效果,特別是讓給紅綠燈的 78px 對不對齊
- ⏳ Menlo 字型下終端機的跨行拖曳選取是否還準(字元寬度靠 `monoCharMetrics.advanceWidth` 算)
- ⏳ 最大化/還原、拖曳(`startSystemMove`)、原生 resize 行為
- ⏳ 實際接 USB 轉接器測熱插拔與 `/dev/cu.*` 通訊
- ⏳ 設定檔在 `~/Library/Preferences/` 下的讀寫
- ⏳ `--attach` 多實例定址(unix socket 路徑)

---

## 未做 ⬜

- ⬜ **`.app` 圖示**:目前用系統預設。`.icns` 在 Windows 只能生成、無法驗證 macOS 是否正確吃它。
  在 Mac 上用內建 `sips` + `iconutil` 從 `lu_pixel.ico`(256×256 RGBA)轉最穩。
- ⬜ **正式簽章 / 公證**:目前只有 ad-hoc 簽名,自己機器上開沒問題,
  給別人要右鍵開啟或 `xattr -dr com.apple.quarantine`。要免這步得買 Apple Developer($99/年)。
- ⏸ **Windows CI**:目前 CI 只跑 macOS,Windows 仍靠本機 `build.bat` 驗證。
