# ScreenCensor Pro

Real-time, on-device macOS menu-bar app that detects and censors body parts on your screen — including **covered and exposed** regions separately — with content-aware blur/pixelate, custom labels/stickers, and smooth high-refresh tracking.

**License: AGPL-3.0** (includes NudeNet-derived Core ML weights). See [`LICENSE`](LICENSE).

**Local Xcode is not required.** Build via GitHub Actions and download the **DMG** artifact.

## Why this exists

| Tool | Gap |
| --- | --- |
| NudeNix | Python overlay; limited native polish |
| SafeVision | ONNX / multi-process, not a native macOS menu-bar product |
| ScreenSeal / Cloaky | Manual masks only |

ScreenCensor Pro ships as a native SwiftUI + AppKit overlay with NudeNet-class labels, Vision pose assist, Metal/CI region effects, and per-part rules.

## Features

- **18 NudeNet body-part classes** with independent Covered / Exposed toggles
- **Vision assists**: face landmarks, hand pose, ankle/feet pose fallback
- **Per-part effects**: blur, pixelate, solid box, color wash, custom label + emoji, SF Symbol stickers
- **Animations**: pulse, shake, stamp-in, scanline
- **Tracking**: label + IoU matching, EMA smoothing, coast-on-miss
- **Performance**: 30 / 60 / 120 FPS capture modes with detection resolution scaling
- **Privacy**: zero network calls in the app; Screen Recording stays on-device

## Download (GitHub Actions)

1. Open [Actions](../../actions) → latest green **Build ScreenCensor**
2. Download **ScreenCensor-macOS-dmg**
3. Open the DMG → drag **ScreenCensor** to Applications

### First launch (ad-hoc signature)

This CI build is **ad-hoc signed**, not Apple-notarized. Gatekeeper will warn until you clear quarantine:

```bash
xattr -dr com.apple.quarantine /Applications/ScreenCensor.app
```

Then **right-click → Open** once, and grant **Screen Recording** when prompted.

Developer ID + notarization can be added later with paid Apple certificates.

## Usage

1. Click the menu bar icon → **Parts** tab → choose body parts
2. **Effects** tab → blur strength / labels / stickers / animations
3. **Motion** tab → FPS mode and smoothing
4. **Start Censoring**

## Repository layout

```text
project.yml
Scripts/convert_nudenet_coreml.py
Sources/App|UI|Overlay|Capture|ML
Resources/Assets.xcassets
Resources/Models/   # NudeNet Core ML produced in CI
.github/workflows/build.yml
LICENSE             # AGPL-3.0
```

## Build workflow

1. Checkout
2. Select Xcode 16.x
3. Convert NudeNet 320n → Core ML into `Resources/Models`
4. `xcodegen generate` + `xcodebuild`
5. Package `.app` + `.dmg` artifacts

## Attribution

- **NudeNet** — [notAI-tech/NudeNet](https://github.com/notAI-tech/NudeNet) (AGPL-3.0), YOLOv8-based 320n weights
- Apple **Vision** / **ScreenCaptureKit** / **Core ML**

## AGPL notice

This program is free software under the GNU Affero General Public License v3.0. If you modify and convey it (including offering it as a network service), you must provide corresponding source under AGPL-3.0. Bundling NudeNet weights inherits those obligations.
