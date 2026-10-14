#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OFFICE_ROOT="$(CDPATH= cd -- "$ROOT/.." && pwd)"
BUILD="$ROOT/Build"
APP="$BUILD/MyAI Office.app"
MACOS="$APP/Contents/MacOS"
HELPERS="$APP/Contents/Helpers"
RESOURCES="$APP/Contents/Resources"
ICON_SOURCE="$ROOT/MyAIOffice-icon.png"
ICONSET="$BUILD/MyAIOffice.iconset"

WORD="$OFFICE_ROOT/ThirdParty/wordcraft"
GRID="$OFFICE_ROOT/ThirdParty/gridcraft"
DECK="$OFFICE_ROOT/ThirdParty/deckcraft"
PDF="$OFFICE_ROOT/ThirdParty/pdfcraft"
FONTS="$OFFICE_ROOT/ThirdParty/craft-fonts"

require_executable() {
    path="$1"
    label="$2"
    if [ ! -x "$path" ]; then
        echo "缺少 $label: $path" >&2
        echo "请先在对应 ThirdParty 目录完成 cargo build --release。" >&2
        exit 1
    fi
}

install_helper() {
    source="$1"
    name="$2"
    label="$3"
    require_executable "$source" "$label"
    cp "$source" "$HELPERS/$name"
    chmod 755 "$HELPERS/$name"
}

echo "构建 MyAI Office 统一入口…"
rm -rf "$APP"
rm -rf "$ICONSET"
mkdir -p "$MACOS" "$HELPERS" "$RESOURCES/THIRD-PARTY"

swiftc -O -target arm64-apple-macos13.0 \
    -framework Cocoa \
    -framework CryptoKit \
    -framework UniformTypeIdentifiers \
    -o "$MACOS/MyAI Office" \
    "$ROOT/Sources/MyAIOffice.swift" \
    "$ROOT/Sources/MyAIOfficeUpdate.swift"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

if [ ! -f "$ICON_SOURCE" ]; then
    echo "缺少 MyAI Office 图标资源: $ICON_SOURCE" >&2
    exit 1
fi
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    double=$((size * 2))
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RESOURCES/MyAIOffice.icns"
rm -rf "$ICONSET"

swiftc -O -target arm64-apple-macos13.0 \
    -framework Cocoa \
    -o "$HELPERS/myai-office-updater" \
    "$ROOT/Sources/MyAIOfficeUpdater.swift"
chmod 755 "$HELPERS/myai-office-updater"

install_helper "$WORD/target/release/wordcraft" "myai-writer" "MyAI Word"
install_helper "$GRID/target/release/gridcraft" "myai-sheet" "MyAI Excel"
install_helper "$DECK/target/release/deckcraft" "myai-slides" "MyAI Power Point"
install_helper "$PDF/target/release/pdfcraft" "myai-pdf" "MyAI PDF"

# CLI companions are included when present for automation and batch conversion.
for item in \
    "$WORD/target/release/wordcraft-cli:myai-writer-cli" \
    "$GRID/target/release/gridcraft-cli:myai-sheet-cli" \
    "$DECK/target/release/deckcraft-cli:myai-slides-cli" \
    "$PDF/target/release/pdfcraft-cli:myai-pdf-cli"
do
    source=${item%%:*}
    name=${item##*:}
    if [ -x "$source" ]; then
        cp "$source" "$HELPERS/$name"
        chmod 755 "$HELPERS/$name"
    fi
done

for item in \
    "$WORD:wordcraft" \
    "$GRID:gridcraft" \
    "$DECK:deckcraft" \
    "$PDF:pdfcraft" \
    "$FONTS:craft-fonts"
do
    source=${item%%:*}
    name=${item##*:}
    for license in LICENSE-MIT LICENSE-APACHE NOTICE; do
        if [ -f "$source/$license" ]; then
            cp "$source/$license" "$RESOURCES/THIRD-PARTY/${name}-${license}"
        fi
    done
    for document in ATTRIBUTION.md fonts/manifest.txt; do
        if [ -f "$source/$document" ]; then
            safe_name=$(printf '%s' "$document" | tr '/' '-')
            cp "$source/$document" "$RESOURCES/THIRD-PARTY/${name}-${safe_name}"
        fi
    done
done

cp "$ROOT/THIRD-PARTY-NOTICES.md" "$RESOURCES/THIRD-PARTY/THIRD-PARTY-NOTICES.md"

if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$APP/Contents/Info.plist"
fi
if command -v codesign >/dev/null 2>&1; then
    codesign --deep --force --sign - "$APP" >/dev/null
fi

echo "MyAI Office.app 已生成：$APP"
du -sh "$APP"
