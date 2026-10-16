#!/usr/bin/env python3
"""Make local visual-QA boards from actual native/offscreen ribbon captures."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
QA = ROOT / "Build/QA/rounded-icons"
REFERENCE = Path("/var/folders/sc/dqy2y37932b4ssrbbsyfd3vr0000gn/T/codex-clipboard-feba0015-e7fe-4f3e-aec4-22b61b47fe9b.png")
FONT = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 21)


def ribbon(path, height=350):
    image = Image.open(path).convert("RGB")
    return image.crop((0, 0, 2880, height)).resize((1440, height // 2), Image.Resampling.LANCZOS)


def comparison(name, before, after):
    if not (QA / before).exists() or not (QA / after).exists():
        return
    board = Image.new("RGB", (1560, 470), "#f3f4f6")
    draw = ImageDraw.Draw(board)
    for top, title, capture in [(15, "Before", before), (245, "Rounded outline", after)]:
        draw.text((15, top), title, fill="#374151", font=FONT)
        board.paste(ribbon(QA / capture), (0, top + 33))
    draw.text((1448, 20), "Ref. 5", fill="#6b7280", font=FONT)
    board.paste(Image.open(REFERENCE).convert("RGB"), (1460, 63))
    board.save(QA / f"{name}-comparison.png")


for args in [
    ("word-draw", "word-draw-before.png", "word-draw-after.png"),
    ("word-layout", "word-layout-before.png", "word-layout-after.png"),
    ("word-home", "word-home-before.png", "word-home-after.png"),
    ("excel-insert", "excel-insert-before.png", "excel-insert-after.png"),
]:
    comparison(*args)

if (QA / "word-draw-after.png").exists() and (QA / "excel-insert-after.png").exists():
    board = Image.new("RGB", (1440, 444), "#f3f4f6")
    draw = ImageDraw.Draw(board)
    draw.text((15, 9), "MyAI Word", fill="#374151", font=FONT)
    board.paste(ribbon(QA / "word-draw-after.png", 360), (0, 40))
    draw.text((15, 230), "MyAI Excel", fill="#374151", font=FONT)
    board.paste(ribbon(QA / "excel-insert-after.png", 360), (0, 263))
    board.save(QA / "ribbon-preview.png")
