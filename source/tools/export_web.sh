#!/usr/bin/env bash
# 匯出網頁版到 build/web/。
# Godot 4.7 在「路徑含中文」的專案匯出時會卡住，所以先把專案複製到英文暫存路徑再匯出。
# 需要先裝好 Web 匯出模板（%APPDATA%\Godot\export_templates\4.7.2.stable\web_*.zip）。
# 用法：bash tools/export_web.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
TMP="${TEMP:-/tmp}/beastcards_export"
rm -rf "$TMP"
mkdir -p "$TMP/proj" "$TMP/web"
cd "$ROOT"
python -X utf8 tools/make_font.py
cp -r project.godot export_presets.cfg scenes scripts assets "$TMP/proj/"
# 線上對戰設定（不進 git）；沒有的話網頁版不能線上對戰
[ -f config/online.cfg ] && mkdir -p "$TMP/proj/config" && cp config/online.cfg "$TMP/proj/config/" || echo "注意：沒有 config/online.cfg，網頁版不能線上對戰"
"$GODOT" --headless --path "$TMP/proj" --import > "$TMP/import.log" 2>&1
"$GODOT" --headless --path "$TMP/proj" --export-release "Web" "$TMP/web/index.html" > "$TMP/export.log" 2>&1
test -f "$TMP/web/index.wasm" || { echo "匯出失敗，看 $TMP/export.log"; exit 1; }
rm -rf build/web
mkdir -p build/web
cp "$TMP"/web/* build/web/
cp web/manifest.webmanifest build/web/
touch build/.gdignore
ls -la build/web
