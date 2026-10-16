"""Render every page and check DOC-to-DOCX round trips with MyAI's own native engine.

Inputs and page images stay in the caller-selected local QA folder. No Office engine other
than the specified MyAI executable is launched; never pass an original as an output path.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from PIL import Image, ImageChops

parser = argparse.ArgumentParser()
parser.add_argument("--writer", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("inputs", type=Path, nargs="+")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
writer = args.writer.resolve()


def run(*values):
    return subprocess.run([str(writer), *map(str, values)], check=True, capture_output=True, text=True).stdout


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


report = []
changed_pages = []
for index, original in enumerate(args.inputs, 1):
    original = original.resolve()
    baseline = digest(original)
    folder = args.output / f"document-{index}"
    folder.mkdir(parents=True, exist_ok=True)
    info = json.loads(run("info", original))
    structured = folder / "imported.json"
    run("convert", original, structured)
    document = json.loads(structured.read_text())
    saved = folder / "roundtrip.docx"
    assert saved.resolve() != original
    run("convert", original, saved)
    reopened = json.loads(run("info", saved))
    assert reopened["pages"] == info["pages"], "DOCX round trip changed the page count"
    pages = []
    differences = []
    for page in range(1, info["pages"] + 1):
        before = folder / f"page-{page}.png"
        after = folder / f"reopened-page-{page}.png"
        run("render", original, before, "--page", page, "--scale", 1.3)
        run("render", saved, after, "--page", page, "--scale", 1.3)
        with Image.open(before) as source, Image.open(after) as reopened_page:
            assert source.size == reopened_page.size, f"DOCX round trip resized page {page}"
            difference = ImageChops.difference(source.convert("RGB"), reopened_page.convert("RGB"))
            maximum = max(high for _, high in difference.getextrema())
        # Integer EMU serialization rounds image dimensions by <0.00002 pt; the
        # native rasterizer can differ by 2/255 in a channel at image edges. This
        # tolerance does not admit displaced text/borders or changed pagination.
        if maximum > 2:
            changed_pages.append((index, page, maximum))
        differences.append(maximum)
        pages.append(digest(before))
    tables = [block for block in document["body"] if block["kind"] == "table"]
    report.append({
        "document": index, "inputSHA256": baseline, "pages": info["pages"],
        "paragraphs": info["paragraphs"], "tableColumns": [len(table["grid"]) for table in tables],
        "tableRows": [len(table["rows"]) for table in tables], "pageSHA256": pages,
        "roundtripPixelsEqual": not any(differences), "roundtripMaxChannelDifferences": differences,
    })
    assert digest(original) == baseline, "An input changed during testing"
    print(f"Rendered document {index}: {info['pages']} pages; DOCX reopen maximum RGB channel differences: {differences}; input unchanged", flush=True)
(args.output / "results.json").write_text(json.dumps(report, ensure_ascii=False, indent=2))
assert not changed_pages, f"DOCX round trip changed pages (document, page, maximum channel difference): {changed_pages}"
