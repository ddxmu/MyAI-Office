#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP="$ROOT/Build/MyAI Office.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/Info.plist")"
OUT="$(CDPATH= cd -- "$ROOT/.." && pwd)/MyAI-Office-${VERSION}-arm64.dmg"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/myai-office-dmg.XXXXXX")"
STAGE="$WORK_DIR/MyAI Office"
RW_DMG="$WORK_DIR/MyAI Office-rw.dmg"
MOUNT_POINT=""

cleanup() {
    if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
        hdiutil detach "$MOUNT_POINT" -quiet || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [ ! -d "$APP" ]; then
    echo "找不到 $APP，请先运行 build-suite.sh。" >&2
    exit 1
fi

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/MyAI Office.app"
ln -s /Applications "$STAGE/Applications"

# Create a writable image first so Finder can save the conventional drag-to-install layout.
hdiutil create -volname "MyAI Office" -srcfolder "$STAGE" -ov -format UDRW "$RW_DMG" >/dev/null
ATTACH_OUTPUT="$(hdiutil attach "$RW_DMG" -nobrowse -noverify)"
MOUNT_POINT="$(printf '%s\n' "$ATTACH_OUTPUT" | awk 'index($0, "/Volumes/") { print substr($0, index($0, "/Volumes/")); exit }')"
if [ -z "$MOUNT_POINT" ]; then
    echo "无法找到 DMG 挂载点。" >&2
    exit 1
fi
VOLUME_NAME="$(basename "$MOUNT_POINT")"

osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 1
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {120, 120, 920, 650}
        set iconViewOptions to icon view options of container window
        set arrangement of iconViewOptions to not arranged
        set icon size of iconViewOptions to 128
        set text size of iconViewOptions to 14
        set position of item "MyAI Office.app" to {230, 270}
        set position of item "Applications" to {610, 270}
        close
        open
        update without registering applications
    end tell
end tell
APPLESCRIPT

hdiutil detach "$MOUNT_POINT" -quiet
MOUNT_POINT=""
rm -f "$OUT"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
echo "DMG 已生成：$OUT"
du -h "$OUT"
