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
MODULE_BASE="${MYAI_OFFICE_PREVIOUS_APP:-$APP}"
MODULE_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/myai-office-modules.XXXXXX")"
trap 'rm -rf "$MODULE_CACHE"' EXIT
for label in "MyAI Word" "MyAI Excel" "MyAI Power Point" "MyAI PDF"; do
    if [ -d "$MODULE_BASE/Contents/Helpers/$label.app" ]; then
        ditto --noextattr --norsrc "$MODULE_BASE/Contents/Helpers/$label.app" "$MODULE_CACHE/$label.app"
    fi
done

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
    module_app="$HELPERS/$label.app"
    cached_app="$MODULE_CACHE/$label.app"
    cached_binary="$cached_app/Contents/MacOS/$name"
    if [ -f "$cached_binary" ]; then
        # A launcher-only release must not re-version/sign unchanged 100 MB editors.
        cp "$source" "$MODULE_CACHE/source-binary"
        cp "$cached_binary" "$MODULE_CACHE/cached-binary"
        codesign --remove-signature "$MODULE_CACHE/source-binary" 2>/dev/null || true
        codesign --remove-signature "$MODULE_CACHE/cached-binary" 2>/dev/null || true
        codesign --force --sign - --identifier com.myai.office.engine-comparison "$MODULE_CACHE/source-binary" 2>/dev/null
        codesign --force --sign - --identifier com.myai.office.engine-comparison "$MODULE_CACHE/cached-binary" 2>/dev/null
        if cmp -s "$MODULE_CACHE/source-binary" "$MODULE_CACHE/cached-binary" \
            && cmp -s "$RESOURCES/MyAIOffice.icns" "$cached_app/Contents/Resources/MyAIOffice.icns" \
            && codesign --verify --deep --strict "$cached_app" 2>/dev/null; then
            ditto --noextattr --norsrc "$cached_app" "$module_app"
            echo "复用未改动模块：$label"
            return
        fi
    fi
    mkdir -p "$module_app/Contents/MacOS" "$module_app/Contents/Resources"
    cp "$source" "$module_app/Contents/MacOS/$name"
    chmod 755 "$module_app/Contents/MacOS/$name"
    cp "$RESOURCES/MyAIOffice.icns" "$module_app/Contents/Resources/MyAIOffice.icns"
    module_info="$module_app/Contents/Info.plist"
    plutil -create xml1 "$module_info"
    plutil -insert CFBundleExecutable -string "$name" "$module_info"
    plutil -insert CFBundleIdentifier -string "com.myai.office.$name" "$module_info"
    plutil -insert CFBundleName -string "$label" "$module_info"
    plutil -insert CFBundleDisplayName -string "$label" "$module_info"
    plutil -insert CFBundlePackageType -string APPL "$module_info"
    plutil -insert CFBundleIconFile -string MyAIOffice "$module_info"
    plutil -insert CFBundleShortVersionString -string "$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT/Info.plist")" "$module_info"
    plutil -insert LSMinimumSystemVersion -string 13.0 "$module_info"
    plutil -insert NSHighResolutionCapable -bool true "$module_info"
    plutil -insert NSPrincipalClass -string NSApplication "$module_info"
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
    "$ROOT/Sources/MyAIOfficeUpdate.swift" \
    "$ROOT/Sources/MyAIUpdatePackage.swift" \
    "$ROOT/Sources/MyAIUpdateReceipt.swift"

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

(cd "$ROOT/Assets/Fonts" && shasum -a 256 -c SHA256SUMS)
mkdir -p "$RESOURCES/Fonts"
cp "$ROOT/Assets/Fonts/ZhuqueFangsong-Regular.ttf" "$RESOURCES/Fonts/"
cp "$ROOT/Assets/Fonts/OFL.txt" "$RESOURCES/THIRD-PARTY/ZhuqueFangsong-OFL.txt"

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
cp "$ICON_SOURCE" "$RESOURCES/MyAIOffice.png"
rm -rf "$ICONSET"

swiftc -O -target arm64-apple-macos13.0 \
    -framework Cocoa \
    -framework CryptoKit \
    -o "$HELPERS/myai-office-updater" \
    "$ROOT/Sources/MyAIOfficeUpdater.swift" \
    "$ROOT/Sources/MyAIUpdatePackage.swift" \
    "$ROOT/Sources/MyAIUpdateReceipt.swift"
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
