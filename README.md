# ScreenCensor Pro

Real-time, on-device macOS menu-bar censoring with **multi-monitor** capture, **NudeNet** body-part detection, **predictive tracking**, and **content-aware** blur / pixelate / frosted / crystallize overlays.

**License: AGPL-3.0** — see [`LICENSE`](LICENSE). Includes NudeNet-derived Core ML weights.

## What improved in 0.3

Inspired by products like [Beta Blocker Mac](https://isla2d.itch.io/beta-blocker-mac) (multi-monitor, per-part effects, performance presets), without cloning proprietary assets:

- One capture + overlay session **per display** (secondary monitors included)
- Shared `FrameGeometry` so Vision boxes, AppKit overlays, and Core Image crops stay aligned (Retina + negative-origin displays)
- Single-pass GPU composition (blur/pixelate all regions from the same filtered frame)
- Predictive `RegionTracker` with IoU association, velocity coasting, and expand-first safety smoothing
- Latest-frame mailbox so UI does not spawn unbounded tasks per capture callback
- Effect presets: strong/soft/frosted blur, mosaic, chunky pixel, crystallize, solid, warning tape, labels, stickers
- Displays / Effects / Motion tabs, persisted settings, capture/infer/draw FPS meters

Deferred (not in this release): reverse censoring, popup storms, photo/video export, OBS virtual camera, achievements, Discord status.

## Download

1. Open [Actions](../../actions) → latest green **Build ScreenCensor**
2. Download **ScreenCensor-macOS-dmg**
3. Drag to Applications, then:

```bash
xattr -dr com.apple.quarantine /Applications/ScreenCensor.app
```

Right-click → Open once. Grant **Screen Recording**. Ad-hoc signature is not notarized.

## Usage

1. **Parts** — enable covered/exposed body parts separately  
2. **Effects** — pick preset, tune blur/pixel/opacity/feather  
3. **Displays** — enable/disable monitors  
4. **Motion** — FPS mode, smoothing, coast time  
5. **Start Censoring**

## Build (CI)

1. Xcode 16.x  
2. Convert NudeNet 320n → Core ML (`Scripts/convert_nudenet_coreml.py`, authenticated GitHub asset download)  
3. `xcodegen generate`  
4. `xcodebuild test`  
5. Release `.app` + `.dmg` artifacts  

## Attribution

- NudeNet — [notAI-tech/NudeNet](https://github.com/notAI-tech/NudeNet) (AGPL-3.0)  
- Sticker PNGs — original project graphics (CC0); see [`Resources/ThirdParty/ATTRIBUTION.md`](Resources/ThirdParty/ATTRIBUTION.md)  
- Adjacent CC0 icon inspiration — [pixelart-icons](https://github.com/tstamborski/pixelart-icons)

## Privacy

No network calls in the app. Capture, detection, and rendering stay on-device.
