"""Verify published packages using the same installer code as the application."""
import argparse
import hashlib
import json
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--base", type=Path, required=True)
parser.add_argument("--manifest", type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
manifest = json.loads(args.manifest.read_text())
package_dir = args.manifest.resolve().parents[2]
installer = root / "Build/MyAI Office.app/Contents/Helpers/myai-office-updater"


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def inventory(folder):
    return {p.relative_to(folder).as_posix(): (digest(p), stat.S_IMODE(p.stat().st_mode))
            for p in folder.rglob("*") if p.is_file()}


def extract(package, destination):
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None, package
    subprocess.run(["ditto", "-x", "-k", str(package), str(destination)], check=True)


def stage(package, base, destination, succeeds=True, version=None):
    result = subprocess.run([str(installer), "--prepare-only", "--app", str(base),
        "--package", str(package), "--staged", str(destination),
        "--target-version", version or manifest["latestVersion"]], capture_output=True, text=True)
    assert (result.returncode == 0) == succeeds, result.stdout + result.stderr
    if not succeeds:
        assert not destination.exists(), "Failed preparation left an incomplete staging bundle"


for asset in [manifest["full"], manifest["dmg"], *manifest["deltas"]]:
    path = package_dir / asset["url"].rsplit("/", 1)[1]
    assert digest(path) == asset["sha256"], f"checksum: {path.name}"
    assert path.stat().st_size == asset["size"], f"size: {path.name}"

with tempfile.TemporaryDirectory(prefix="myai-office-update-check-") as temporary:
    folder = Path(temporary)
    full = package_dir / manifest["full"]["url"].rsplit("/", 1)[1]
    extract(args.base, folder / "base")
    extract(full, folder / "full")
    base = folder / "base/MyAI Office.app"
    expected = folder / "full/MyAI Office.app"
    baseline = inventory(base)
    target = inventory(expected)
    complete_metadata = json.loads((folder / "full/metadata.json").read_text())
    assert complete_metadata["kind"] == "full" and complete_metadata["targetVersion"] == manifest["latestVersion"]
    stage(full, base, folder / "full-rebuilt.app")
    assert inventory(folder / "full-rebuilt.app") == target

    for index, asset in enumerate(manifest["deltas"]):
        delta = package_dir / asset["url"].rsplit("/", 1)[1]
        staged = folder / f"delta-{index}.app"
        stage(delta, base, staged)
        assert inventory(staged) == target, f"Reconstructed files/modes differ: {delta.name}"
        print(f"PASS: {asset['format']}, all target hashes/modes, signatures and exact reconstruction", flush=True)
        if asset["format"] == "file-delta-v1":
            # Reproduce the installed 0.6.x helper's file-copy algorithm as well.
            extract(delta, folder / "legacy")
            metadata = json.loads((folder / "legacy/metadata.json").read_text())
            assert metadata["format"] == 1 and metadata["kind"] == "delta"
            compatibility = folder / "legacy-compatible.app"
            shutil.copytree(base, compatibility)
            for source in (folder / "legacy/payload").rglob("*"):
                if source.is_file():
                    destination = compatibility / source.relative_to(folder / "legacy/payload")
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, destination)
            for deleted in (folder / "legacy/deleted.txt").read_text().splitlines():
                (compatibility / deleted).unlink(missing_ok=True)
            assert inventory(compatibility) == target
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(compatibility)], check=True)
            print("PASS: 0.6.x legacy helper compatibility", flush=True)
        else:
            with zipfile.ZipFile(delta) as archive:
                entries = {name: archive.read(name) for name in archive.namelist()}

            def invalid_package(name, modify):
                altered = dict(entries)
                metadata = json.loads(altered["metadata.json"])
                modify(metadata)
                altered["metadata.json"] = json.dumps(metadata).encode()
                path = folder / f"{name}.zip"
                with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
                    for key, value in altered.items():
                        archive.writestr(key, value)
                return path

            traversal = invalid_package("traversal", lambda m: m["deleted"].append("../outside.txt"))
            stage(traversal, base, folder / "unsafe.app", succeeds=False)
            assert not (folder / "outside.txt").exists()
            bad_hash = invalid_package("bad-target-hash", lambda m: m["files"][0].update(sha256="0" * 64))
            stage(bad_hash, base, folder / "bad-hash.app", succeeds=False)
            stage(delta, base, folder / "wrong-version.app", succeeds=False, version="99.99.99")

            corrupt = folder / "modified-base.app"
            shutil.copytree(base, corrupt)
            icon = corrupt / "Contents/Resources/MyAIOffice.png"
            with icon.open("r+b") as output:
                output.write(b"BAD!")
            stage(delta, corrupt, folder / "modified-output.app", succeeds=False)
            print("PASS: reject unsafe paths, corrupt output, wrong version and modified base; installed app untouched", flush=True)

    assert inventory(base) == baseline
print("PASS: all asset SHA-256/sizes, complete ZIP, delta formats, original base preservation", flush=True)
