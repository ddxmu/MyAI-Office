"""Build a verified BSDIFF40 update; bsdiff4 is a release-time dependency only."""
import argparse
import hashlib
import json
import plistlib
import stat
import zipfile
import zlib
from pathlib import Path

import bsdiff4


def digest(data):
    return hashlib.sha256(data).hexdigest()


def inventory(root):
    result = {}
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Symbolic links are not supported by this package format: {path}")
        if path.is_file():
            result[path.relative_to(root).as_posix()] = path
    return result


def build(base, target, output):
    old, new = inventory(base), inventory(target)
    version = lambda app: plistlib.loads((app / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"]
    metadata = {
        "format": 2, "kind": "bsdiff", "baseVersion": version(base),
        "targetVersion": version(target), "files": [], "operations": [],
        "deleted": sorted(old.keys() - new.keys()),
    }
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative, path in new.items():
            data = path.read_bytes()
            metadata["files"].append({"path": relative, "sha256": digest(data),
                                      "size": len(data), "mode": stat.S_IMODE(path.stat().st_mode)})
            previous = old[relative].read_bytes() if relative in old else None
            if previous == data:
                continue
            operation = {"path": relative, "kind": "replace",
                         "source": f"payload/{len(metadata['operations']):04d}"}
            payload = data
            if previous is not None:
                patch = bsdiff4.diff(previous, data)
                # A replacement wins for new resources or binaries that changed completely.
                if len(zlib.compress(patch, 9)) < len(zlib.compress(data, 9)):
                    operation.update(kind="patch", baseSHA256=digest(previous))
                    payload = patch
            archive.writestr(operation["source"], payload)
            metadata["operations"].append(operation)
        archive.writestr("metadata.json", json.dumps(metadata, ensure_ascii=False, separators=(",", ":")))
    print(f"{output.name}: {output.stat().st_size:,} bytes; "
          f"{sum(op['kind'] == 'patch' for op in metadata['operations'])} patches, "
          f"{sum(op['kind'] == 'replace' for op in metadata['operations'])} replacements")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--target", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    build(args.base, args.target, args.output)
