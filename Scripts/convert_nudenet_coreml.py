#!/usr/bin/env python3
"""Download NudeNet 320n and convert to Core ML for ScreenCensor bundling."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.request import Request, urlopen


WEIGHTS_API_URL = "https://api.github.com/repos/notAI-tech/NudeNet/releases/assets/176832011"
WEIGHTS_BROWSER_URL = "https://github.com/notAI-tech/NudeNet/releases/download/v3.4-weights/320n.pt"
EXPECTED_MIN_BYTES = 5_000_000
EXPECTED_BYTES = 6_219_609

LABELS = [
    "FEMALE_GENITALIA_COVERED",
    "FACE_FEMALE",
    "BUTTOCKS_EXPOSED",
    "FEMALE_BREAST_EXPOSED",
    "FEMALE_GENITALIA_EXPOSED",
    "MALE_BREAST_EXPOSED",
    "ANUS_EXPOSED",
    "FEET_EXPOSED",
    "BELLY_COVERED",
    "FEET_COVERED",
    "ARMPITS_COVERED",
    "ARMPITS_EXPOSED",
    "FACE_MALE",
    "BELLY_EXPOSED",
    "MALE_GENITALIA_EXPOSED",
    "ANUS_COVERED",
    "FEMALE_BREAST_COVERED",
    "BUTTOCKS_COVERED",
]


def ensure_deps() -> None:
    try:
        import ultralytics  # noqa: F401
        import coremltools  # noqa: F401
    except ImportError:
        subprocess.check_call(
            [
                sys.executable,
                "-m",
                "pip",
                "install",
                "--quiet",
                "ultralytics",
                "coremltools",
                "torch",
                "onnx",
            ]
        )


def download(dest: Path) -> None:
    import os

    if dest.exists() and dest.stat().st_size >= EXPECTED_MIN_BYTES:
        print(f"Using cached weights: {dest} ({dest.stat().st_size} bytes)")
        return

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN") or ""
    headers = {"User-Agent": "ScreenCensor-CI/1.0"}
    # Prefer GitHub API + token: browser release URLs often redirect to a login HTML page.
    if token:
        url = WEIGHTS_API_URL
        headers["Authorization"] = f"Bearer {token}"
        headers["Accept"] = "application/octet-stream"
    else:
        url = WEIGHTS_BROWSER_URL

    print(f"Downloading {url}")
    req = Request(url, headers=headers)
    with urlopen(req, timeout=180) as response, open(dest, "wb") as out:
        shutil.copyfileobj(response, out)

    size = dest.stat().st_size
    print(f"Downloaded {size} bytes (expected ~{EXPECTED_BYTES})")
    if size < EXPECTED_MIN_BYTES:
        head = dest.read_bytes()[:200]
        dest.unlink(missing_ok=True)
        raise RuntimeError(f"Download too small ({size} bytes); got: {head!r}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()

    args.work_dir.mkdir(parents=True, exist_ok=True)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    ensure_deps()

    from ultralytics import YOLO

    weights = args.work_dir / "320n.pt"
    download(weights)

    model = YOLO(str(weights))
    if hasattr(model, "model") and hasattr(model.model, "names"):
        names = model.model.names
        if isinstance(names, dict) and len(names) == len(LABELS):
            model.model.names = {i: LABELS[i] for i in range(len(LABELS))}

    print("Exporting Core ML package (imgsz=320)...")
    export_path = Path(model.export(format="coreml", imgsz=320, nms=True))

    # Remove previous model artifacts
    for pattern in ("NudeNet320n.mlpackage", "NudeNet320n.mlmodel", "NudeNet320n.mlmodelc"):
        old = args.out_dir / pattern
        if old.is_dir():
            shutil.rmtree(old)
        elif old.exists():
            old.unlink()

    if export_path.is_dir():
        target = args.out_dir / "NudeNet320n.mlpackage"
        shutil.copytree(export_path, target)
    elif export_path.suffix == ".mlmodel":
        target = args.out_dir / "NudeNet320n.mlmodel"
        shutil.copy2(export_path, target)
    else:
        target = args.out_dir / export_path.name
        shutil.copy2(export_path, target)

    print(f"Wrote model to {target}")
    for p in sorted(args.out_dir.iterdir()):
        print(" ", p.name, p.stat().st_size if p.is_file() else "(dir)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
