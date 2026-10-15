"""Exercise a private app copy over local HTTP, including real download/install/relaunch.

Requires the QA/office-ui.swift and QA/launch-module.swift executables and bsdiff4.
Never installs into /Applications or opens business documents.
"""
import hashlib
import http.server
import json
import os
import plistlib
import re
import shutil
import subprocess
import tempfile
import threading
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
UI = ROOT / "Build/QA/office-ui"
LAUNCH = ROOT / "Build/launch-module"
APP = ROOT / "Build/MyAI Office.app"


def command(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True).stdout


def wait_for(check, timeout=20):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.15)
    raise AssertionError("Timed out waiting for acceptance check")


def inspect(pid):
    return json.loads(command(UI, "inspect", pid))


def text(pid):
    return json.dumps(inspect(pid), ensure_ascii=False)


def press(pid, label):
    command(UI, "press", pid, label)
    time.sleep(0.2)


mode = "latest"
feed = {}
package = b""


class Server(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/latest.json":
            if mode == "offline":
                self.send_error(503)
                return
            manifest = dict(feed)
            if mode == "latest":
                manifest["latestVersion"] = "0.7.0"
            data = json.dumps(manifest).encode()
        elif self.path == "/update.zip":
            data = package
        else:
            self.send_error(404)
            return
        self.send_response(200)
        if self.path != "/update.zip":
            self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            for offset in range(0, len(data), 4096):
                self.wfile.write(data[offset:offset + 4096])
                self.wfile.flush()
                if self.path == "/update.zip":
                    time.sleep(0.12)
        except (BrokenPipeError, ConnectionResetError):
            pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Server)
threading.Thread(target=server.serve_forever, daemon=True).start()
url = f"http://127.0.0.1:{server.server_port}"
evidence = ROOT / "Build/QA/update-ui"
evidence.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="myai-office-update-ui-") as temporary:
    folder = Path(temporary)
    base = folder / "installed/MyAI Office.app"
    target = folder / "target/MyAI Office.app"
    pid = None
    new_pid = None
    try:
        for app, version in [(base, "0.7.0"), (target, "0.7.1")]:
            command("ditto", "--noextattr", "--norsrc", APP, app)
            info_path = app / "Contents/Info.plist"
            info = plistlib.loads(info_path.read_bytes())
            info.update(CFBundleIdentifier="com.myai.office.updater-qa", CFBundleShortVersionString=version,
                        CFBundleVersion=version.replace(".", ""), LSMultipleInstancesProhibited=False,
                        MyAIUpdateManifestURL=url + "/latest.json")
            info_path.write_bytes(plistlib.dumps(info))
            if app == target:
                # An incompressible new file keeps progress visible long enough to inspect.
                (app / "Contents/Resources/qa-download.bin").write_bytes(os.urandom(128 * 1024))
            command("codesign", "--deep", "--force", "--sign", "-", app)
        delta = folder / "delta.zip"
        command(os.sys.executable, ROOT / "Tools/make-delta.py", "--base", base, "--target", target, "--output", delta)
        package = delta.read_bytes()
        asset = {"url": url + "/update.zip", "sha256": hashlib.sha256(package).hexdigest(),
                 "baseVersion": "0.7.0", "format": "bsdiff-v2", "size": len(package)}
        feed = {"app": "MyAI Office", "latestVersion": "0.7.1", "releaseNotes": "独立测试副本，不是公开版本。",
                "full": {**asset, "baseVersion": None}, "deltas": [asset]}
        launch = command(LAUNCH, base)
        pid = int(re.search(r"PID=(\d+)", launch)[1])
        wait_for(lambda: "myai-check-update" in text(pid))
        command(UI, "capture", pid, evidence / "check-update.png")
        press(pid, "myai-check-update")
        wait_for(lambda: "当前已是最新版本" in text(pid))
        print("PASS: manual check and latest-version state", flush=True)

        mode = "offline"
        press(pid, "myai-check-update")
        wait_for(lambda: "检查更新失败" in text(pid))
        press(pid, "好")
        mode = "available"
        press(pid, "myai-check-update")
        wait_for(lambda: "发现新版本 MyAI Office 0.7.1" in text(pid))
        press(pid, "稍后")
        wait_for(lambda: "立即更新" in text(pid))
        command(UI, "capture", pid, evidence / "update-available.png")
        print("PASS: failed checks can be retried; new-version prompt and persistent update button", flush=True)

        press(pid, "myai-check-update")
        wait_for(lambda: any(re.search(r"(?:[1-9]|[1-9][0-9])% ·", str(row.get("AXValue", ""))) for row in inspect(pid)))
        command(UI, "capture", pid, evidence / "download-progress.png")
        (evidence / "download-accessibility.json").write_text(json.dumps(inspect(pid), ensure_ascii=False, indent=2))
        press(pid, "取消下载")
        wait_for(lambda: "立即更新" in text(pid))
        time.sleep(0.5)
        assert plistlib.loads((base / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"] == "0.7.0"
        print("PASS: numeric download progress, progress bar and cancellation leave the installed app unchanged", flush=True)

        press(pid, "myai-check-update")

        def relaunched():
            pids = json.loads(command(UI, "find", base))
            new = next((p for p in pids if p != pid), None)
            if not new and pid in pids:
                current = text(pid)
                if "增量更新无法应用" in current or "更新失败" in current or "请先保存文档" in current:
                    (evidence / "install-failure.json").write_text(current)
                    command(UI, "capture", pid, evidence / "install-failure.png")
                    raise AssertionError(current)
            return new

        new_pid = wait_for(relaunched, timeout=60)
        wait_for(lambda: "开始使用" in text(new_pid))
        assert plistlib.loads((base / "Contents/Info.plist").read_bytes())["CFBundleShortVersionString"] == "0.7.1"
        command("codesign", "--verify", "--deep", "--strict", base)
        command(UI, "capture", new_pid, evidence / "update-complete.png")
        wait_for(lambda: not list(base.parent.glob(".MyAI Office.backup-*")))
        assert not list(base.parent.glob(".MyAI Office.staged-*"))
        press(new_pid, "开始使用")
        print("PASS: real binary delta download, staging, replacement, new-process relaunch, completion receipt and backup cleanup", flush=True)
    finally:
        for owned_pid in [new_pid, pid]:
            if owned_pid:
                subprocess.run([str(UI), "quit", str(owned_pid)], capture_output=True)
        time.sleep(0.5)
        server.shutdown()
