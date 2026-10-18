#!/usr/bin/env python3
"""Compare page raster output from a reference editor and MyAI Office.

This deliberately compares rendered page images rather than document XML. It is
an acceptance aid for pagination, text placement, tables, and spacing; it does
not claim that two different renderers use identical anti-aliasing.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops


PAGE_NUMBER = re.compile(r"(?:^|-)page-(\d+)(?:\.[^.]+)?$", re.IGNORECASE)


def page_files(folder: Path, pattern: str) -> list[tuple[int, Path]]:
    files: list[tuple[int, Path]] = []
    for path in folder.glob(pattern):
        match = PAGE_NUMBER.search(path.name)
        if match:
            files.append((int(match.group(1)), path))
    return sorted(files)


def ink_box(image: Image.Image) -> list[int] | None:
    rgb = image.convert("RGB")
    white = Image.new("RGB", rgb.size, (255, 255, 255))
    box = ImageChops.difference(rgb, white).getbbox()
    return list(box) if box else None


def compare_images(reference: Image.Image, candidate: Image.Image) -> dict[str, object]:
    if reference.size != candidate.size:
        return {
            "size": {"reference": list(reference.size), "candidate": list(candidate.size)},
            "maxChannelDifference": None,
            "changedPixels": None,
            "pixelCount": None,
            "diffRatio": None,
            "referenceInkBox": ink_box(reference),
            "candidateInkBox": ink_box(candidate),
        }

    ref = reference.convert("RGB")
    cand = candidate.convert("RGB")
    diff = ImageChops.difference(ref, cand)
    channels = diff.split()
    mask = ImageChops.lighter(ImageChops.lighter(channels[0], channels[1]), channels[2])
    maximum = max(channel.getextrema()[1] for channel in channels)
    pixels = ref.width * ref.height
    changed = pixels - mask.histogram()[0]
    return {
        "size": list(ref.size),
        "maxChannelDifference": maximum,
        "changedPixels": changed,
        "pixelCount": pixels,
        "diffRatio": changed / pixels if pixels else 0.0,
        "referenceInkBox": ink_box(ref),
        "candidateInkBox": ink_box(cand),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", type=Path, required=True, help="Reference page-image directory")
    parser.add_argument("--candidate", type=Path, required=True, help="MyAI Office page-image directory")
    parser.add_argument("--reference-glob", default="page-*.png")
    parser.add_argument("--candidate-glob", default="page-*.png")
    parser.add_argument("--max-channel-difference", type=int, default=16)
    parser.add_argument("--max-diff-ratio", type=float, default=0.02)
    parser.add_argument("--output", type=Path, help="Write the machine-readable result here")
    args = parser.parse_args()

    refs = page_files(args.reference, args.reference_glob)
    candidates = page_files(args.candidate, args.candidate_glob)
    by_ref = dict(refs)
    by_candidate = dict(candidates)
    page_numbers = sorted(set(by_ref) | set(by_candidate))
    pages: list[dict[str, object]] = []
    ok = len(refs) == len(candidates)
    for number in page_numbers:
        ref_path = by_ref.get(number)
        candidate_path = by_candidate.get(number)
        if ref_path is None or candidate_path is None:
            pages.append({"page": number, "reference": str(ref_path) if ref_path else None, "candidate": str(candidate_path) if candidate_path else None, "status": "missing"})
            ok = False
            continue
        with Image.open(ref_path) as ref_image, Image.open(candidate_path) as candidate_image:
            metrics = compare_images(ref_image, candidate_image)
        page_ok = (
            metrics["maxChannelDifference"] is not None
            and metrics["maxChannelDifference"] <= args.max_channel_difference
            and metrics["diffRatio"] <= args.max_diff_ratio
        )
        pages.append({"page": number, "reference": str(ref_path), "candidate": str(candidate_path), "status": "ok" if page_ok else "different", **metrics})
        ok = ok and page_ok

    result = {
        "status": "ok" if ok else "different",
        "reference": str(args.reference),
        "candidate": str(args.candidate),
        "referencePageCount": len(refs),
        "candidatePageCount": len(candidates),
        "thresholds": {"maxChannelDifference": args.max_channel_difference, "maxDiffRatio": args.max_diff_ratio},
        "pages": pages,
    }
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
