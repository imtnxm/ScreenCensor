# Core ML Models

## Bundled detector (CI)

GitHub Actions runs `Scripts/convert_nudenet_coreml.py` to download **NudeNet 320n** weights and export `NudeNet320n.mlpackage` into this folder before `xcodegen` / `xcodebuild`.

| Field | Value |
| --- | --- |
| Source | [notAI-tech/NudeNet](https://github.com/notAI-tech/NudeNet) v3.4 `320n.pt` |
| License | AGPL-3.0 (this app is also AGPL-3.0) |
| Bundle name | `NudeNet320n.mlpackage` or `NudeNet320n.mlmodel` / `.mlmodelc` |
| Classes | 18 NudeNet labels (covered/exposed body parts, faces, feet, …) |

## Labels expected by `DetectionEngine`

```
FACE_FEMALE, FACE_MALE,
FEMALE_BREAST_COVERED, FEMALE_BREAST_EXPOSED, MALE_BREAST_EXPOSED,
FEMALE_GENITALIA_COVERED, FEMALE_GENITALIA_EXPOSED, MALE_GENITALIA_EXPOSED,
ANUS_COVERED, ANUS_EXPOSED,
BUTTOCKS_COVERED, BUTTOCKS_EXPOSED,
BELLY_COVERED, BELLY_EXPOSED,
ARMPITS_COVERED, ARMPITS_EXPOSED,
FEET_COVERED, FEET_EXPOSED
```

If no model is present, Vision face/hand/body pose paths still run; Status will show **Vision Only**.

## Local conversion

```bash
python3 Scripts/convert_nudenet_coreml.py --work-dir /tmp/nn --out-dir Resources/Models
```
