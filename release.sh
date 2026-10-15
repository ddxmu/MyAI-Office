#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$ROOT/.." && pwd)"
INFO="$ROOT/Info.plist"
APP="$ROOT/Build/MyAI Office.app"
REPO="ddxmu/MyAI-Office"
RELEASE_OK=0
PUBLISH=0
PREVIOUS_APP=""
NOTES="自动升级能力、增量更新包支持，以及升级失败时的安全回退处理。"

usage() {
    cat <<'EOF'
用法：./release.sh patch|minor|major|X.Y.Z [--previous-app PATH] [--notes TEXT] [--publish]

patch 适用于小修复，minor 适用于新增大功能，major 适用于不兼容变更。
--publish 会把代码推送到 GitHub，并把 DMG、完整自动更新包和增量包上传为 Release 资产。
EOF
}

[ "$#" -ge 1 ] || { usage >&2; exit 2; }
case "$1" in
    -h|--help) usage; exit 0 ;;
esac
BUMP="$1"
shift
while [ "$#" -gt 0 ]; do
    case "$1" in
        --previous-app)
            [ "$#" -ge 2 ] || { echo "--previous-app 缺少路径。" >&2; exit 2; }
            PREVIOUS_APP="$2"
            shift 2
            ;;
        --notes)
            [ "$#" -ge 2 ] || { echo "--notes 缺少内容。" >&2; exit 2; }
            NOTES="$2"
            shift 2
            ;;
        --publish)
            PUBLISH=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "未知参数：$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

CURRENT_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO")"
OLD_MAJOR="$(printf '%s' "$CURRENT_VERSION" | awk -F. '{print $1}')"
OLD_MINOR="$(printf '%s' "$CURRENT_VERSION" | awk -F. '{print $2}')"
OLD_PATCH="$(printf '%s' "$CURRENT_VERSION" | awk -F. '{print $3}')"
case "$BUMP" in
    patch) TARGET_VERSION="$OLD_MAJOR.$OLD_MINOR.$((OLD_PATCH + 1))" ;;
    minor) TARGET_VERSION="$OLD_MAJOR.$((OLD_MINOR + 1)).0" ;;
    major) TARGET_VERSION="$((OLD_MAJOR + 1)).0.0" ;;
    *) TARGET_VERSION="$BUMP" ;;
esac
case "$TARGET_VERSION" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "目标版本不是 X.Y.Z：$TARGET_VERSION" >&2; exit 2 ;;
esac

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/myai-office-release.XXXXXX")"
BEFORE_INFO="$WORK_DIR/Info.plist.before"
cp "$INFO" "$BEFORE_INFO"

cleanup() {
    if [ "$RELEASE_OK" -ne 1 ]; then
        cp "$BEFORE_INFO" "$INFO" 2>/dev/null || true
    fi
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [ -n "$PREVIOUS_APP" ]; then
    [ -d "$PREVIOUS_APP" ] || { echo "找不到 previous app：$PREVIOUS_APP" >&2; exit 1; }
    PREVIOUS_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$PREVIOUS_APP/Contents/Info.plist")"
    [ "$PREVIOUS_VERSION" != "$TARGET_VERSION" ] || { echo "增量包基线不能与目标版本相同：$TARGET_VERSION" >&2; exit 1; }
    cp -R "$PREVIOUS_APP" "$WORK_DIR/previous.app"
elif [ -d "$APP" ]; then
    EXISTING_BUILD_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist" 2>/dev/null || true)"
    if [ -n "$EXISTING_BUILD_VERSION" ] && [ "$EXISTING_BUILD_VERSION" != "$TARGET_VERSION" ]; then
        cp -R "$APP" "$WORK_DIR/previous.app"
    fi
fi

BUILD_NUMBER="$(printf '%s' "$TARGET_VERSION" | awk -F. '{ printf "%d", ($1 * 10000) + ($2 * 100) + $3 }')"
plutil -replace CFBundleShortVersionString -string "$TARGET_VERSION" "$INFO"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$INFO"

echo "构建 MyAI Office ${TARGET_VERSION}…"
"$ROOT/build-suite.sh"
"$ROOT/package-dmg.sh"

FULL_ZIP="$PROJECT_ROOT/MyAI-Office-${TARGET_VERSION}-arm64.zip"
DMG="$PROJECT_ROOT/MyAI-Office-${TARGET_VERSION}-arm64.dmg"
rm -f "$FULL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$FULL_ZIP"
# Older installed updaters require metadata even for a complete application ZIP.
FULL_METADATA="$WORK_DIR/full-metadata"
mkdir -p "$FULL_METADATA"
printf '%s\n' "{\"format\":1,\"kind\":\"full\",\"baseVersion\":null,\"targetVersion\":\"$TARGET_VERSION\"}" > "$FULL_METADATA/metadata.json"
(cd "$FULL_METADATA" && /usr/bin/zip -q "$FULL_ZIP" metadata.json)

DELTA_ZIP=""
BASE_VERSION=""
if [ -d "$WORK_DIR/previous.app" ]; then
    BASE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$WORK_DIR/previous.app/Contents/Info.plist")"
    DELTA_STAGE="$WORK_DIR/delta"
    mkdir -p "$DELTA_STAGE/payload"
    : > "$DELTA_STAGE/deleted.txt"

    (
        cd "$APP"
        find . \( -type f -o -type l \) -print
    ) | while IFS= read -r relative; do
        current_file="$APP/$relative"
        old_file="$WORK_DIR/previous.app/$relative"
        if [ ! -e "$old_file" ] || ! cmp -s "$current_file" "$old_file"; then
            mkdir -p "$DELTA_STAGE/payload/$(dirname "$relative")"
            cp -p "$current_file" "$DELTA_STAGE/payload/$relative"
        fi
    done

    (
        cd "$WORK_DIR/previous.app"
        find . \( -type f -o -type l \) -print
    ) | while IFS= read -r relative; do
        if [ ! -e "$APP/$relative" ]; then
            printf '%s\n' "${relative#./}" >> "$DELTA_STAGE/deleted.txt"
        fi
    done

    printf '%s\n' "{\"format\":1,\"kind\":\"delta\",\"baseVersion\":\"$BASE_VERSION\",\"targetVersion\":\"$TARGET_VERSION\"}" > "$DELTA_STAGE/metadata.json"
    DELTA_ZIP="$PROJECT_ROOT/MyAI-Office-${BASE_VERSION}-to-${TARGET_VERSION}-arm64.delta.zip"
    rm -f "$DELTA_ZIP"
    ditto -c -k --sequesterRsrc "$DELTA_STAGE" "$DELTA_ZIP"
fi

sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
FULL_SHA256="$(sha256 "$FULL_ZIP")"
DMG_SHA256="$(sha256 "$DMG")"
RELEASE_BASE="https://github.com/$REPO/releases/download/v$TARGET_VERSION"
DELTA_JSON='[]'
if [ -n "$DELTA_ZIP" ]; then
    DELTA_SHA256="$(sha256 "$DELTA_ZIP")"
    DELTA_OBJECT="$(jq -cn \
        --arg base "$BASE_VERSION" \
        --arg url "$RELEASE_BASE/$(basename "$DELTA_ZIP")" \
        --arg sha "$DELTA_SHA256" \
        '{baseVersion:$base,url:$url,sha256:$sha}')"
    DELTA_JSON="[$DELTA_OBJECT]"
fi

mkdir -p "$ROOT/updates/releases"
jq -n \
    --arg app "MyAI Office" \
    --arg version "$TARGET_VERSION" \
    --arg notes "$NOTES" \
    --arg fullUrl "$RELEASE_BASE/$(basename "$FULL_ZIP")" \
    --arg fullSha "$FULL_SHA256" \
    --arg dmgUrl "$RELEASE_BASE/$(basename "$DMG")" \
    --arg dmgSha "$DMG_SHA256" \
    --argjson deltas "$DELTA_JSON" \
    '{app:$app,latestVersion:$version,releaseNotes:$notes,full:{url:$fullUrl,sha256:$fullSha,baseVersion:null},dmg:{url:$dmgUrl,sha256:$dmgSha},deltas:$deltas}' \
    > "$ROOT/updates/latest.json"
cp "$ROOT/updates/latest.json" "$ROOT/updates/releases/$TARGET_VERSION.json"

echo "完整自动更新包：$FULL_ZIP"
if [ -n "$DELTA_ZIP" ]; then
    echo "增量更新包：$DELTA_ZIP"
else
    echo "未生成增量包：没有找到上一版本应用，请使用 --previous-app PATH。"
fi
echo "升级清单：$ROOT/updates/latest.json"

if [ "$PUBLISH" -eq 1 ]; then
    [ -d "$ROOT/.git" ] || { echo "当前工程还没有独立 Git 仓库，未执行发布。" >&2; exit 1; }
    gh repo view "$REPO" >/dev/null 2>&1 || {
        echo "GitHub 仓库 $REPO 不存在；为避免擅自公开代码，未创建仓库。" >&2
        exit 1
    }
    PRIVATE="$(gh repo view "$REPO" --json isPrivate --jq '.isPrivate')"
    [ "$PRIVATE" = "false" ] || {
        echo "$REPO 是私有仓库，应用无法免登录读取升级清单；请改为公开仓库或提供专用更新服务。" >&2
        exit 1
    }
    git add .gitignore Info.plist MyAIOffice-icon.png README.md Sources THIRD-PARTY-NOTICES.md Assets QA SourceLock.json VendorPatches prepare-sources.sh build-suite.sh package-dmg.sh release.sh
    git commit -m "Release MyAI Office $TARGET_VERSION"
    git push origin main
    SOURCE_REVISION="$(git rev-parse HEAD)"
    if [ -n "$DELTA_ZIP" ]; then
        gh release create "v$TARGET_VERSION" "$DMG" "$FULL_ZIP" "$DELTA_ZIP" \
            --draft --target "$SOURCE_REVISION" --title "MyAI Office $TARGET_VERSION" --notes "$NOTES"
    else
        gh release create "v$TARGET_VERSION" "$DMG" "$FULL_ZIP" \
            --draft --target "$SOURCE_REVISION" --title "MyAI Office $TARGET_VERSION" --notes "$NOTES"
    fi
    gh release edit "v$TARGET_VERSION" --draft=false --latest
    # Publish the update feed only after every downloadable asset is available.
    git add updates
    git commit -m "Publish update manifest for $TARGET_VERSION"
    git push origin main
fi

RELEASE_OK=1
