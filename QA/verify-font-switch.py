"""Check Chinese font changes through private running editor windows and saved Office files."""
import argparse
import hashlib
import json
import socket
import time
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path

from PIL import Image, ImageChops

parser = argparse.ArgumentParser()
parser.add_argument("--word-port", type=int, default=17983)
parser.add_argument("--excel-port", type=int, default=17984)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--expect-bug", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
FAMILIES = ["宋体", "仿宋", "黑体", "微软雅黑", "楷体"]
STORED_NAMES = {
    "宋体": {"宋体", "SimSun"},
    "仿宋": {"仿宋", "FangSong"},
    "黑体": {"黑体", "SimHei"},
    "微软雅黑": {"微软雅黑", "Microsoft YaHei"},
    "楷体": {"楷体", "KaiTi"},
}
TEXT = "运维服务管理制度中文字体切换测试"


class Client:
    def __init__(self, port, word=False):
        self.word = word
        deadline = time.monotonic() + 20
        while True:
            try:
                self.socket = socket.create_connection(("127.0.0.1", port), timeout=60)
                break
            except ConnectionRefusedError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.1)
        self.stream = self.socket.makefile("rw", encoding="utf-8")
        self.key = None
        if word:
            key_path = Path.home() / f"Library/Application Support/WordCraft/control-key.local-{port}"
            if key_path.exists():
                self.key = key_path.read_text().strip()

    def request(self, method, params=None):
        if self.word and method in ["app.open", "app.save"]:
            return self.command("file.open" if method == "app.open" else "file.save", params)
        request = {"id": 1, "method": method, "params": params or {}}
        if self.key:
            request["key"] = self.key
        self.stream.write(json.dumps(request, ensure_ascii=False) + "\n")
        self.stream.flush()
        response = json.loads(self.stream.readline())
        assert response.get("ok"), {"method": method, "response": response}
        return response.get("result")

    def command(self, name, params=None):
        return self.request("engine.execute", {"command": name, "params": params or {}})

    def close(self):
        self.stream.close()
        self.socket.close()


def word_font(path):
    with zipfile.ZipFile(path) as archive:
        document = ET.fromstring(archive.read("word/document.xml"))
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    fonts = document.findall(".//w:rPr/w:rFonts", ns)
    return [font.get("{" + ns["w"] + "}eastAsia") for font in fonts]


def excel_font(path):
    with zipfile.ZipFile(path) as archive:
        ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
        sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
        style = ET.fromstring(archive.read("xl/styles.xml"))
    cell = sheet.find('.//s:c[@r="A1"]', ns)
    xf = style.find("s:cellXfs", ns)[int(cell.get("s", "0"))]
    return style.find("s:fonts", ns)[int(xf.get("fontId", "0"))].find("s:name", ns).get("val")


def ink_digest(path, crop=None):
    with Image.open(path) as opened:
        image = opened.convert("RGB")
        if crop:
            image = image.crop(crop)
        mask = ImageChops.difference(image, Image.new("RGB", image.size, "white"))
        bounds = mask.getbbox()
        assert bounds, "No rendered text"
        ink = image.crop(bounds)
        return hashlib.sha256(str(ink.size).encode() + ink.tobytes()).hexdigest()


word = Client(args.word_port, word=True)
sheet = Client(args.excel_port)
report = {"word": {}, "excel": {}, "expectedBug": args.expect_bug}
try:
    word.command("file.new", {"template": "blank"})
    word.command("document.setText", {"text": TEXT})
    word.command("select.all")
    word.command("format.size", {"size": 24})
    word.command("format.font", {"name": "Georgia", "eastAsia": "SimSun"})
    source = args.output / "导入字体检验.docx"
    word.request("app.save", {"path": str(source)})
    word.command("file.new")
    word.request("app.open", {"path": str(source)})
    for family in FAMILIES:
        word.command("select.all")
        if args.expect_bug:
            word.command("format.font", {"name": family})
        else:
            word.request("ui.click", {"x": 180, "y": 74})
            word.request("ui.key", {"key": "A", "cmd": True})
            word.request("ui.text", {"text": family})
            word.request("ui.key", {"key": "Enter"})
            time.sleep(0.3)
        state = word.command("format.state")
        wanted = state["fontEastAsia"]
        if args.expect_bug and family in ["宋体", "仿宋", "黑体"]:
            assert wanted == "SimSun", (family, state)
        if not args.expect_bug:
            # The picker uses the canonical English name of an installed localized font.
            assert wanted in STORED_NAMES[family], (family, state)
        rendered = args.output / f"word-{family}.png"
        word.command("file.exportPng", {"path": str(rendered), "page": 1, "scale": 1})
        saved = args.output / f"word-{family}.docx"
        word.request("app.save", {"path": str(saved)})
        assert wanted in word_font(saved), f"DOCX did not preserve {wanted}"
        word.command("file.new")
        word.request("app.open", {"path": str(saved)})
        word.command("select.all")
        assert word.command("format.state")["fontEastAsia"] == wanted
        report["word"][family] = {"eastAsia": wanted, "ink": ink_digest(rendered)}
    word.request("ui.screenshot", {"path": str(args.output / "word-window.png")})
    print("PASS: Word opened DOCX, changed the selected font, exported, saved and reopened all five families", flush=True)

    sheet.command("file.new")
    sheet.command("cell.set", {"cell": "A1", "input": TEXT})
    sheet.command("home.fontSize", {"range": "A1", "size": 24})
    sheet.command("home.columnWidth", {"range": "A:A", "width": 90})
    sheet.command("home.rowHeight", {"range": "1:1", "height": 72})
    source = args.output / "导入字体检验.xlsx"
    sheet.request("app.save", {"path": str(source)})
    sheet.command("file.new")
    sheet.request("app.open", {"path": str(source)})
    time.sleep(3)
    for family in FAMILIES:
        sheet.request("ui.cell.click", {"cell": "A1"})
        # The isolated QA window uses 100% interface scale: operate the actual ribbon picker,
        # not just the command API, to catch a lost dropdown/typed selection too.
        sheet.request("ui.click", {"x": 190, "y": 80})
        time.sleep(0.2)
        sheet.request("ui.text", {"text": family})
        sheet.request("ui.key", {"key": "Enter"})
        time.sleep(0.5)
        saved = args.output / f"excel-{family}.xlsx"
        sheet.request("app.save", {"path": str(saved)})
        assert excel_font(saved) == family
        shot = args.output / f"excel-{family}.png"
        sheet.request("ui.screenshot", {"path": str(shot)})
        x, y, _, _ = sheet.request("ui.inspect")["grid"]
        with Image.open(shot) as image:
            window_width = sheet.request("ui.inspect")["window"][0]
            scale = image.width / window_width
        crop = tuple(round(v * scale) for v in [x + 5, y + 5, x + 620, y + 68])
        report["excel"][family] = {"font": family, "ink": ink_digest(shot, crop)}
        sheet.command("file.new")
        sheet.request("app.open", {"path": str(saved)})
        again = args.output / f"excel-{family}-reopened.xlsx"
        sheet.request("app.save", {"path": str(again)})
        assert excel_font(again) == family
    counts = {name: len({item["ink"] for item in report[name].values()}) for name in ["word", "excel"]}
    report["distinctRenderedFamilies"] = counts
    (args.output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
    if args.expect_bug:
        assert counts["excel"] == 1, counts
        print(f"REPRODUCED: Word keeps the imported Asian font; Excel renders five names as {counts['excel']} face", flush=True)
    else:
        assert counts == {"word": 5, "excel": 5}, counts
        print("PASS: five genuinely different rendered typefaces in both editors, not just changed menu labels", flush=True)
finally:
    for client in [word, sheet]:
        try:
            client.request("app.quit")
        except (AssertionError, OSError, ValueError):
            pass
        client.close()
