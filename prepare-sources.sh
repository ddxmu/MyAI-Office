#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_ROOT="$ROOT/../ThirdParty"
mkdir -p "$SOURCE_ROOT"
for name in wordcraft gridcraft deckcraft pdfcraft craft-fonts; do
    source_dir="$SOURCE_ROOT/$name"
    revision="$(jq -r --arg name "$name" '.[$name].revision' "$ROOT/SourceLock.json")"
    repo_url="$(jq -r --arg name "$name" '.[$name].url' "$ROOT/SourceLock.json")"
    if [ ! -d "$source_dir/.git" ]; then
        if [ -e "$source_dir" ]; then
            echo "已有非 Git 目录，未覆盖：$source_dir" >&2
            exit 1
        fi
        git clone --filter=blob:none --no-checkout "$repo_url" "$source_dir"
        git -C "$source_dir" checkout --detach "$revision"
    fi
    if [ "$(git -C "$source_dir" rev-parse HEAD)" != "$revision" ]; then
        echo "源码版本与 SourceLock.json 不一致，未修改：$source_dir" >&2
        exit 1
    fi
    patch_file="$ROOT/VendorPatches/$name.patch"
    if [ -f "$patch_file" ]; then
        if git -C "$source_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
            echo "${name}：MyAI Office 修改已存在"
        elif git -C "$source_dir" apply --check "$patch_file"; then
            git -C "$source_dir" apply "$patch_file"
        else
            echo "补丁与当前本地修改冲突，未覆盖：$source_dir" >&2
            exit 1
        fi
    fi
done
