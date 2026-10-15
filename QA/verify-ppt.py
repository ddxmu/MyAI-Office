"""Exercise the packaged editor's pointer and keyboard path, then save and reopen a PPTX."""
import argparse
import json
import socket
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--port", type=int, default=17990)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
deadline = time.monotonic() + 20
while True:
    try:
        connection = socket.create_connection(("127.0.0.1", args.port), timeout=20)
        break
    except ConnectionRefusedError:
        if time.monotonic() >= deadline:
            raise
        time.sleep(0.1)
stream = connection.makefile("rw", encoding="utf-8")


def request(method, params=None):
    stream.write(json.dumps({"id": 1, "method": method, "params": params or {}}, ensure_ascii=False) + "\n")
    stream.flush()
    response = json.loads(stream.readline())
    if not response.get("ok"):
        raise RuntimeError(response)
    return response.get("result")


def settle():
    time.sleep(0.25)


def command(name, params=None):
    return request("engine.execute", {"command": name, "params": params or {}})


command("file.new")
request("ui.set", {"zoom": None})
settle()
request("ui.screenshot", {"path": str(args.output / "ppt-placeholders.png")})
window = request("ui.inspect")
x, y, w, h = window["slideRect"]
request("ui.click", {"x": x + w * 0.5, "y": y + h * 0.30})
settle()
selection = request("document.inspect")["selection"]
assert selection["text"], "a mouse click must enter placeholder editing"
request("ui.text", {"text": "MyAI "})
settle()
request("ui.ime", {"preedit": "中文"})
settle()
request("ui.ime", {"commit": "中文编辑验证"})
settle()
doc = request("document.inspect")
assert doc["slides"][0]["title"] == "MyAI 中文编辑验证", doc["slides"]
request("ui.key", {"key": "End"})
settle()
request("ui.text", {"text": "!"})
settle()
request("ui.key", {"key": "Backspace"})
settle()
assert request("document.inspect")["slides"][0]["title"] == "MyAI 中文编辑验证"
request("ui.click", {"x": 325, "y": 83})
settle()
request("ui.click", {"x": 275, "y": 112})
settle()
request("ui.text", {"text": "后"})
settle()
assert request("document.inspect")["slides"][0]["title"] == "MyAI 中文编辑验证后", "typing must resume after selecting a font"
request("ui.key", {"key": "Backspace"})
settle()
request("ui.click", {"x": x + w * 0.5, "y": y + h * 0.64})
settle()
request("ui.ime", {"commit": "宋体、仿宋、黑体、微软雅黑"})
settle()
path = str(args.output / "中文编辑回归.pptx")
request("app.save", {"path": path})
request("ui.screenshot", {"path": str(args.output / "ppt-edited.png")})
command("file.new")
request("app.open", {"path": path})
settle()
doc = request("document.inspect")
assert doc["slides"][0]["title"] == "MyAI 中文编辑验证", "saved title must survive PPTX reopen"
request("ui.screenshot", {"path": str(args.output / "ppt-reopened.png")})
print("PASS: actual UI click, Text/IME events, Backspace, title/subtitle editing, PPTX save and reopen")
