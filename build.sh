#!/usr/bin/env bash
#
# macOS 建構腳本,對應 Windows 的 build.bat + deploy.bat。
#
#   ./build.sh                  增量建構(native 架構,最快)
#   ./build.sh clean            全清重建
#   ./build.sh universal        產出 x86_64 + arm64 universal binary
#   ./build.sh deploy           建構後跑 macdeployqt + ad-hoc 簽名,產出可發佈的 .app
#   ./build.sh clean universal deploy    參數可自由組合
#
# Qt 路徑:$QT_ROOT 環境變數優先,否則自動找 ~/Qt/6.*/macos 的最新版。
# 產出:build/UARTPro.app
#
set -euo pipefail

cd "$(dirname "$0")"

BUILD_DIR=build
DO_CLEAN=0
DO_UNIVERSAL=0
DO_DEPLOY=0

for arg in "$@"; do
    case "$arg" in
        clean)     DO_CLEAN=1 ;;
        universal) DO_UNIVERSAL=1 ;;
        deploy)    DO_DEPLOY=1 ;;
        *) echo "未知參數: $arg" >&2; exit 1 ;;
    esac
done

# ── 找 Qt ────────────────────────────────────────────────────
if [[ -z "${QT_ROOT:-}" ]]; then
    for candidate in "$HOME"/Qt/6.*/macos /opt/homebrew/opt/qt6 /usr/local/opt/qt6; do
        [[ -d "$candidate/lib/cmake/Qt6" ]] && QT_ROOT="$candidate"
    done
fi

if [[ -z "${QT_ROOT:-}" || ! -d "$QT_ROOT/lib/cmake/Qt6" ]]; then
    echo "找不到 Qt 6。請安裝 Qt(含 Qt Serial Port 模組)或手動指定:" >&2
    echo "  QT_ROOT=~/Qt/6.7.3/macos ./build.sh" >&2
    exit 1
fi
echo "Qt: $QT_ROOT"

# ── configure ────────────────────────────────────────────────
if [[ $DO_CLEAN -eq 1 ]]; then
    rm -rf "$BUILD_DIR"
fi

if [[ ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
    # 不指定的話 CMake 會拿建構機的 macOS 版本當 deployment target,
    # 做出來的 .app 在舊系統直接開不起來。與 CI 一致固定 12.0,可用環境變數覆寫。
    CMAKE_ARGS=(
        -S . -B "$BUILD_DIR"
        -DCMAKE_BUILD_TYPE=Release
        -DCMAKE_PREFIX_PATH="$QT_ROOT"
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-12.0}"
    )
    # ninja 有就用,沒有就退回預設 generator,不強迫額外安裝
    command -v ninja >/dev/null 2>&1 && CMAKE_ARGS+=(-G Ninja)
    # Qt 官方 macOS binary 本身是 universal,所以單機就能出雙架構
    [[ $DO_UNIVERSAL -eq 1 ]] && CMAKE_ARGS+=(-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64")
    cmake "${CMAKE_ARGS[@]}"
fi

cmake --build "$BUILD_DIR" --parallel

APP="$BUILD_DIR/UARTPro.app"
[[ -d "$APP" ]] || { echo "建構未產出 $APP" >&2; exit 1; }

# ── deploy ───────────────────────────────────────────────────
if [[ $DO_DEPLOY -eq 1 ]]; then
    echo "macdeployqt..."
    "$QT_ROOT/bin/macdeployqt" "$APP" -qmldir="$PWD"
    # Apple Silicon 要求所有可執行碼至少有 ad-hoc 簽名才能啟動
    codesign --force --deep --sign - "$APP"
fi

echo
echo "完成: $APP"
[[ $DO_UNIVERSAL -eq 1 ]] && lipo -archs "$APP/Contents/MacOS/UARTPro"
echo "執行: open $APP     (CLI: $APP/Contents/MacOS/UARTPro --list-ports)"
