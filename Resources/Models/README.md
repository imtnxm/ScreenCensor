# Core ML Models

Place compiled Core ML resources here so XcodeGen can copy them into the app bundle.

## Expected resource

| Field | Value |
| --- | --- |
| File name | `IntimateZones.mlmodelc` **or** `IntimateZones.mlmodel` |
| Bundle lookup | `Bundle.main.url(forResource: "IntimateZones", withExtension: "mlmodelc")` falls back to `.mlmodel` |
| Output contract | object-detection style bounding boxes consumed by `VNCoreMLRequest` / `VNRecognizedObjectObservation` |

## Bounding-box contract

Intimate-zone detections must be produced as Vision-normalized rectangles in the bottom-left origin space that Vision already uses:

- `x`, `y`, `width`, `height` ∈ `[0, 1]`
- origin at the **bottom-left** of the image
- labels are free-form strings; the app treats every recognized object as an intimate-zone candidate when the Intimate Zones toggle is enabled

`DetectionEngine` maps those normalized boxes into AppKit screen coordinates before the overlay renders.

## Notes

- Face detection works without this model via built-in Vision requests.
- If no model resource is present, intimate-zone inference is skipped and the app still compiles and runs.
- Keep models on-device only. Do not add network download code.
