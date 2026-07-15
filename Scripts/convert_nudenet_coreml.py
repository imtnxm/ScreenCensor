#!/usr/bin/env python3
"""Download NudeNet 320n and convert to Core ML for ScreenCensor bundling."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.request import urlretrieve


WEIGHTS_URL = "https://github.com/notAI-tech/NudeNet/releases/download/v3.4-weights/320n.pt"
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
            [sys.executable, "-m", "pip", "install", "--quiet", "ultralytics", "coremltools", "torch", "onnx"]
        )


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
    if not weights.exists():
        print(f"Downloading {WEIGHTS_URL}")
        urlretrieve(WEIGHTS_URL, weights)

    model = YOLO(str(weights))
    # Ensure class names match NudeNet labels when present
    if hasattr(model, "model") and hasattr(model.model, "names"):
        names = model.model.names
        if isinstance(names, dict) and len(names) == len(LABELS):
            model.model.names = {i: LABELS[i] for i in range(len(LABELS))}

    print("Exporting Core ML package (imgsz=320)...")
    export_path = model.export(format="coreml", imgsz=320, nms=True)
    export_path = Path(export_path)

    target = args.out_dir / "NudeNet320n.mlpackage"
    if target.exists():
        shutil.rmtree(target)
    if export_path.is_dir():
        shutil.copytree(export_path, target)
    else:
        # Some exporters write .mlmodel
        if export_path.suffix == ".mlmodel":
            target = args.out_dir / "NudeNet320n.mlmodel"
            shutil.copy2(export_path, target)
        else:
            shutil.copy2(export_path, args.out_dir / export_path.name)

    print(f"Wrote model to {args.out_dir}")
    for p in sorted(args.out_dir.iterdir()):
        print(" ", p.name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
