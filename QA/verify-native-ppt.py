"""macOS acceptance test using the current Simplified Pinyin input method and real OS keystrokes.

Run from the project root after compiling QA/launch-module.swift to Build/launch-module.
Only the newly created test process is addressed; the user's documents are not touched.
"""
import json
import re
import socket
import subprocess
import time
from pathlib import Path

root = Path.cwd()
output = root / "Build/QA"
output.mkdir(parents=True, exist_ok=True)
launched = subprocess.run(
    ["Build/launch-module", "Build/MyAI Office.app/Contents/Helpers/MyAI Power Point.app", "--control", "17994"],
    text=True, capture_output=True, check=True,
)
pid = int(re.search(r"PID=(\d+)", launched.stdout)[1])
deadline = time.monotonic() + 15
while True:
    try:
        connection = socket.create_connection(("127.0.0.1", 17994), timeout=10)
        break
    except ConnectionRefusedError:
        if time.monotonic() >= deadline:
            raise
        time.sleep(0.1)
with connection:
    stream = connection.makefile("rw", encoding="utf-8")

    def request(method, params=None):
        stream.write(json.dumps({"id": 1, "method": method, "params": params or {}}, ensure_ascii=False) + "\n")
        stream.flush()
        response = json.loads(stream.readline())
        assert response.get("ok"), response
        return response.get("result")

    try:
        request("engine.execute", {"command": "file.new"})
        time.sleep(0.3)
        x, y, w, h = request("ui.inspect")["slideRect"]
        request("ui.click", {"x": x + w * 0.5, "y": y + h * 0.30})
        time.sleep(0.3)
        subprocess.run([
            "osascript", "-e",
            f'tell application "System Events" to tell (first application process whose unix id is {pid})\n'
            'keystroke "zhongwen"\ndelay 0.4\nkey code 49\nend tell',
        ], check=True)
        time.sleep(0.5)
        title = request("document.inspect")["slides"][0]["title"]
        request("ui.screenshot", {"path": str(output / "ppt-native-keyboard.png")})
        request("app.save", {"path": str(output / "系统键盘验证.pptx")})
        assert title == "中文", f"Expected committed Chinese with Simplified Pinyin, got {title!r}"
        print("PASS: macOS keystrokes and current Pinyin IME produced committed Chinese in the packaged editor")
    finally:
        request("app.quit")
