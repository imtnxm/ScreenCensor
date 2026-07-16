import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("", selection: $model.selectedTab) {
                ForEach(AppModel.SettingsTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            Group {
                switch model.selectedTab {
                case .parts: PartsTab()
                case .effects: EffectsTab()
                case .displays: DisplaysTab()
                case .motion: MotionTab()
                case .status: StatusTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            controls
        }
        .frame(width: 420, height: 560)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 2) {
                Text("ScreenCensor Pro")
                    .font(.headline)
                Text(model.isRunning
                     ? String(format: "Live · cap %.0f · infer %.0f · draw %.0f", model.captureFPS, model.inferenceFPS, model.renderFPS)
                     : "Multi-monitor · NudeNet · metal blur")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
        }
        .padding(12)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                model.toggleRunning()
            } label: {
                Text(model.isRunning ? "Stop Censoring" : "Start Censoring")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isRunning ? .red : .accentColor)
            .controlSize(.large)

            HStack {
                Button("Permission") { model.requestPermission() }
                    .buttonStyle(.bordered)
                Button("Refresh") { Task { await model.refreshPermissionStatus() } }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Quit") {
                    Task {
                        await model.stop()
                        NSApplication.shared.terminate(nil)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(12)
    }
}

// MARK: - Parts

private struct PartsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button("Enable All") {
                        for part in BodyPartID.allCases {
                            var r = model.configuration.rule(for: part)
                            r.enabled = true
                            model.configuration.updateRule(r)
                        }
                    }
                    Button("Defaults") { model.configuration = CensorConfiguration() }
                    Spacer()
                    Toggle("Pose Assist", isOn: $model.configuration.usePoseAssist)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .font(.caption)

                ForEach(BodyPartGroup.allCases) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(group.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { model.configuration.isGroupFullyEnabled(group) },
                                set: { model.configuration.setGroup(group, enabled: $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        ForEach(group.parts) { part in
                            partRow(part)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
        }
    }

    private func partRow(_ part: BodyPartID) -> some View {
        let ruleBinding = model.ruleBinding(for: part)
        return VStack(alignment: .leading, spacing: 4) {
            Toggle(part.title, isOn: Binding(
                get: { ruleBinding.wrappedValue.enabled },
                set: {
                    var r = ruleBinding.wrappedValue
                    r.enabled = $0
                    ruleBinding.wrappedValue = r
                }
            ))
            if ruleBinding.wrappedValue.enabled {
                HStack {
                    Text("Confidence \(Int(ruleBinding.wrappedValue.confidenceThreshold * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: Binding(
                            get: { Double(ruleBinding.wrappedValue.confidenceThreshold) },
                            set: {
                                var r = ruleBinding.wrappedValue
                                r.confidenceThreshold = Float($0)
                                ruleBinding.wrappedValue = r
                            }
                        ),
                        in: 0.1...0.9
                    )
                }
            }
        }
    }
}

// MARK: - Effects

private struct EffectsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Presets").font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(EffectPreset.catalog) { preset in
                        Button {
                            model.configuration.globalEffect = preset
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.style.title).font(.caption.weight(.semibold))
                                Text(preset.id).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                model.configuration.globalEffect.id == preset.id
                                ? Color.accentColor.opacity(0.2)
                                : Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Global Effect").font(.subheadline.weight(.semibold))
                effectEditor(Binding(
                    get: { model.configuration.globalEffect },
                    set: { model.configuration.globalEffect = $0 }
                ))

                Button("Apply Global Effect to All Parts") {
                    model.configuration.applyGlobalEffectToAll()
                }
                .buttonStyle(.bordered)

                Text("Per-Part Overrides").font(.subheadline.weight(.semibold))
                ForEach(BodyPartID.allCases.filter { model.configuration.rule(for: $0).enabled }) { part in
                    DisclosureGroup(part.title) {
                        effectEditor(Binding(
                            get: { model.configuration.rule(for: part).effect },
                            set: {
                                var r = model.configuration.rule(for: part)
                                r.effect = $0
                                model.configuration.updateRule(r)
                            }
                        ))
                    }
                }
            }
            .padding(12)
        }
    }

    private func effectEditor(_ effect: Binding<EffectPreset>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Style", selection: Binding(
                get: { effect.wrappedValue.style },
                set: { effect.wrappedValue.style = $0 }
            )) {
                ForEach(CensorStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)

            if [.blur, .softBlur, .frosted].contains(effect.wrappedValue.style) {
                labeledSlider("Blur", value: Binding(
                    get: { effect.wrappedValue.blurRadius },
                    set: { effect.wrappedValue.blurRadius = $0 }
                ), range: 4...48)
            }
            if [.pixelate, .chunkyPixel].contains(effect.wrappedValue.style) {
                labeledSlider("Pixel Size", value: Binding(
                    get: { effect.wrappedValue.pixelScale },
                    set: { effect.wrappedValue.pixelScale = $0 }
                ), range: 4...40)
            }
            if effect.wrappedValue.style == .label || effect.wrappedValue.style == .warningTape {
                TextField("Label", text: Binding(
                    get: { effect.wrappedValue.labelText },
                    set: { effect.wrappedValue.labelText = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                TextField("Emoji", text: Binding(
                    get: { effect.wrappedValue.labelEmoji },
                    set: { effect.wrappedValue.labelEmoji = $0 }
                ))
                .textFieldStyle(.roundedBorder)
            }
            if effect.wrappedValue.style == .sticker {
                Picker("Sticker", selection: Binding(
                    get: { effect.wrappedValue.sticker },
                    set: { effect.wrappedValue.sticker = $0 }
                )) {
                    ForEach(StickerSymbol.allCases) { symbol in
                        Label(symbol.title, systemImage: symbol.rawValue).tag(symbol)
                    }
                }
            }

            labeledSlider("Opacity", value: Binding(
                get: { effect.wrappedValue.fillOpacity },
                set: { effect.wrappedValue.fillOpacity = $0 }
            ), range: 0.2...1.0, asPercent: true)

            labeledSlider("Corner", value: Binding(
                get: { effect.wrappedValue.cornerRadius },
                set: { effect.wrappedValue.cornerRadius = $0 }
            ), range: 0...20)

            labeledSlider("Feather", value: Binding(
                get: { effect.wrappedValue.feather },
                set: { effect.wrappedValue.feather = $0 }
            ), range: 0...12)

            Picker("Animation", selection: Binding(
                get: { effect.wrappedValue.animation },
                set: { effect.wrappedValue.animation = $0 }
            )) {
                ForEach(OverlayAnimation.allCases) { anim in
                    Text(anim.title).tag(anim)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func labeledSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        asPercent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asPercent
                  ? String(format: "%@: %.0f%%", title, value.wrappedValue * 100)
                  : String(format: "%@: %.0f", title, value.wrappedValue))
                .font(.caption)
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Displays

private struct DisplaysTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Displays").font(.subheadline.weight(.semibold))
            if model.availableDisplays.isEmpty {
                Text("No displays detected yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.availableDisplays) { display in
                Toggle(isOn: Binding(
                    get: {
                        model.configuration.displays.isEnabled(
                            display.id,
                            available: model.availableDisplays.map(\.id)
                        )
                    },
                    set: {
                        model.configuration.displays.setEnabled(
                            display.id,
                            enabled: $0,
                            available: model.availableDisplays.map(\.id)
                        )
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display.name + (display.isMain ? " (Main)" : ""))
                        Text("\(Int(display.pointFrame.width))×\(Int(display.pointFrame.height)) @\(String(format: "%.0f", display.backingScaleFactor))x")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
        }
        .padding(12)
    }
}

// MARK: - Motion

private struct MotionTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance").font(.subheadline.weight(.semibold))
            Picker("Mode", selection: $model.configuration.performanceMode) {
                ForEach(PerformanceMode.allCases) { mode in
                    Text("\(mode.title) (\(mode.targetFrameRate) FPS)").tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Text("Detection scale \(String(format: "%.0f%%", model.configuration.performanceMode.detectionScale * 100))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()
            Text("Tracking").font(.subheadline.weight(.semibold))

            slider("Smoothing", value: $model.configuration.motion.smoothing, range: 0.05...0.8)
            slider("Coast (s)", value: $model.configuration.motion.coastSeconds, range: 0.05...0.5)
            slider("Padding", value: $model.configuration.motion.globalPadding, range: 0...0.35)

            Toggle("Face landmark sub-regions", isOn: $model.configuration.useFaceLandmarks)
            Spacer()
        }
        .padding(12)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(String(format: "%@: %.2f", title, value.wrappedValue)).font(.caption)
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Status

private struct StatusTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.statusMessage, systemImage: model.isRunning ? "waveform" : "pause.circle")
                .font(.subheadline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                chip(model.permissionGranted ? "Permission OK" : "Need Permission", tint: model.permissionGranted ? .green : .orange)
                chip(model.modelLoaded ? "NudeNet Loaded" : "Vision Only", tint: model.modelLoaded ? .blue : .secondary)
                chip("Detections \(model.activeDetectionCount)", tint: .pink)
                chip(String(format: "Cap %.0f", model.captureFPS), tint: .purple)
                chip(String(format: "Infer %.0f", model.inferenceFPS), tint: .indigo)
                chip(String(format: "Draw %.0f", model.renderFPS), tint: .teal)
                chip("Dropped \(model.framesDropped)", tint: .orange)
                chip(model.usingGPUFallback ? "CPU Fallback" : "Metal GPU", tint: model.usingGPUFallback ? .orange : .green)
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Multi-monitor · content-aware blur/pixelate · predictive tracking · on-device only.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
    }

    private func chip(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
    }
}
