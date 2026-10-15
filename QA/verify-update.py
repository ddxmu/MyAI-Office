"""Check release hashes and reconstruct the new app from the published base plus delta."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--base", type=Path, required=True)
parser.add_argument("--manifest", type=Path, required=True)
args = parser.parse_args()
manifest = json.loads(args.manifest.read_text())
package_dir = args.manifest.resolve().parents[2]


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def extract(package, destination):
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None, package
        archive.extractall(destination)
        for entry in archive.infolist():
            path = destination / entry.filename
            mode = entry.external_attr >> 16 & 0o777
            if mode and path.is_file():
                path.chmod(mode)


for asset in [manifest["full"], manifest["dmg"], *manifest["deltas"]]:
    path = package_dir / asset["url"].rsplit("/", 1)[1]
    assert digest(path) == asset["sha256"], f"checksum: {path.name}"
full = package_dir / manifest["full"]["url"].rsplit("/", 1)[1]
delta = package_dir / manifest["deltas"][0]["url"].rsplit("/", 1)[1]
with tempfile.TemporaryDirectory(prefix="myai-office-update-check-") as temporary:
    root = Path(temporary)
    extract(args.base, root / "base")
    extract(full, root / "full")
    extract(delta, root / "delta")
    complete_metadata = json.loads((root / "full/metadata.json").read_text())
    assert complete_metadata["kind"] == "full" and complete_metadata["targetVersion"] == manifest["latestVersion"]
    metadata = json.loads((root / "delta/metadata.json").read_text())
    assert metadata["kind"] == "delta" and metadata["targetVersion"] == manifest["latestVersion"]
    assert metadata["baseVersion"] == manifest["deltas"][0]["baseVersion"]
    staged = root / "staged/MyAI Office.app"
    shutil.copytree(root / "base/MyAI Office.app", staged)
    for source in (root / "delta/payload").rglob("*"):
        if source.is_file():
            target = staged / source.relative_to(root / "delta/payload")
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
    for deleted in (root / "delta/deleted.txt").read_text().splitlines():
        relative = Path(deleted)
        assert not relative.is_absolute() and ".." not in relative.parts
        target = staged / relative
        if target.is_file():
            target.unlink()
    expected = root / "full/MyAI Office.app"
    files = lambda folder: {str(p.relative_to(folder)): digest(p) for p in folder.rglob("*") if p.is_file()}
    assert files(staged) == files(expected), "delta output differs from complete application"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(staged)], check=True)
    print("PASS: release hashes, ZIP integrity, full-package metadata, delta reconstruction, nested app signatures")
