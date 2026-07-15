# ScreenCensor

Real-time, on-device macOS screen censoring menu bar app.

**Local Xcode is not required.** The project is defined with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`) and compiled by GitHub Actions. Download the `.app` artifact from the workflow run.

## Features (scaffold)

- Menu bar controls (`MenuBarExtra`) for targets, censor style, and performance mode
- Transparent click-through `NSPanel` overlay above other apps
- `ScreenCaptureKit` capture with overlay window exclusion (flicker prevention)
- Vision face / landmark detection on a background queue
- Optional Core ML intimate-zone model (`Resources/Models/IntimateZones.mlmodelc`)
- Frame dropping when detection falls behind

## Repository layout

```text
project.yml
.github/workflows/build.yml
Sources/
  App/          # app entry, state, coordinator
  UI/           # SwiftUI menu bar panel
  Overlay/      # AppKit transparent overlay
  Capture/      # ScreenCaptureKit stream
  ML/           # Vision + optional Core ML
Resources/
  ScreenCensor.entitlements
  Models/README.md
```

## Build with GitHub Actions (recommended)

1. Push this repository to GitHub.
2. Open the **Actions** tab and wait for **Build ScreenCensor** to finish.
3. Download the **ScreenCensor-macOS** artifact (`ScreenCensor.app`).
4. Unzip the artifact and move `ScreenCensor.app` somewhere convenient (for example `~/Applications`).

### First launch (Gatekeeper + ad-hoc signing)

The CI build uses **ad-hoc signing** (`CODE_SIGN_IDENTITY="-"`), so Gatekeeper will block a normal double-click until you allow it:

```bash
xattr -dr com.apple.quarantine ~/Applications/ScreenCensor.app
codesign --force --deep --sign - ~/Applications/ScreenCensor.app
open ~/Applications/ScreenCensor.app
```

If macOS still blocks the app: **System Settings → Privacy & Security** → allow the blocked app, then reopen.

### Screen Recording permission

1. Open the ScreenCensor menu bar item.
2. Click **Permission**.
3. Enable ScreenCensor under **System Settings → Privacy & Security → Screen Recording**.
4. Click **Start Censoring**.

Capture never leaves the device. There are no network calls in this app.

## Optional: generate project from the command line

If you have command-line developer tools available, you can generate the project from Terminal:

```bash
brew install xcodegen
xcodegen generate
```

Full compilation is expected on the GitHub-hosted `macos-14` runner via `.github/workflows/build.yml`.

## Adding an intimate-zone Core ML model

Face detection works without an extra model. To enable intimate-zone detection:

1. Add `Resources/Models/IntimateZones.mlmodel` or `IntimateZones.mlmodelc`.
2. Ensure outputs are Vision-compatible recognized-object bounding boxes.
3. Rebuild via GitHub Actions.

See [`Resources/Models/README.md`](Resources/Models/README.md) for the bounding-box contract.

## Architecture

```text
MenuBarView / AppModel
        │
        ▼
 CensorCoordinator ──► OverlayWindowController (NSPanel + CALayer)
        │
        ├── ScreenCaptureManager (SCStream, excludes overlay windowID)
        │
        └── DetectionEngine (Vision / optional CoreML, background queue)
```

### Flicker prevention

`SCContentFilter` is created with the overlay's `CGWindowID` in `excludingWindows`. If the overlay were captured, the model would detect its own censor layers and oscillate.

### Threading

| Work | Thread |
| --- | --- |
| SwiftUI / overlay layer updates | MainActor |
| Screen capture callbacks | capture queue |
| Vision / Core ML | detection queue |

Image buffers are processed and released immediately. Concurrent frames are dropped when the detector is busy.

## Strict constraints honored

- No local Xcode install required
- Zero cloud / network usage in app code
- Capture + detection off the main thread
- Optional Core ML resource; app compiles without it
