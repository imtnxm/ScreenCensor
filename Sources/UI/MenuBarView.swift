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
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            Group {
                switch model.selectedTab {
                case .parts:
                    PartsTab()
                case .effects:
                    EffectsTab()
                case .motion:
                    MotionTab()
                case .status:
                    StatusTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            controls
        }
        .frame(width: 380, height: 520)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(
                    LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("ScreenCensor Pro")
                    .font(.headline)
                Text(model.isRunning ? "Live · \(Int(model.measuredFPS)) FPS" : "On-device body-part censoring")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(model.isRunning ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
        }
        .padding(14)
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
                Button("Refresh") {
                    Task { await model.refreshPermissionStatus() }
                }
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
        .padding(14)
    }
}

// MARK: - Parts

private struct PartsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button("Enable All") {
                        for part in BodyPartID.allCases {
                            var r = model.configuration.rule(for: part)
                            r.enabled = true
                            model.configuration.updateRule(r)
                        }
                    }
                    Button("Defaults") {
                        model.configuration = CensorConfiguration()
                    }
                    Spacer()
                    Toggle("Pose Assist", isOn: $model.configuration.usePoseAssist)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .font(.caption)

                ForEach(BodyPartGroup.allCases) { group in
                    groupSection(group)
                }
            }
            .padding(14)
        }
    }

    private func groupSection(_ group: BodyPartGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(group.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle(
                    "",
                    isOn: Binding(
                        get: { model.configuration.isGroupFullyEnabled(group) },
                        set: { model.configuration.setGroup(group, enabled: $0) }
                    )
                )
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
            VStack(alignment: .leading, spacing: 14) {
                Text("Global Default Effect")
                    .font(.subheadline.weight(.semibold))

                effectEditor(Binding(
                    get: { model.configuration.globalEffect },
                    set: { model.configuration.globalEffect = $0 }
                ))

                Button("Apply Global Effect to All Parts") {
                    model.configuration.applyGlobalEffectToAll()
                }
                .buttonStyle(.bordered)

                Divider()

                Text("Per-Part Overrides")
                    .font(.subheadline.weight(.semibold))

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
            .padding(14)
        }
    }

    private func effectEditor(_ effect: Binding<EffectPreset>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(
                "Style",
                selection: Binding(
                    get: { effect.wrappedValue.style },
                    set: { effect.wrappedValue.style = $0 }
                )
            ) {
                ForEach(CensorStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.menu)

            if effect.wrappedValue.style == .blur {
                labeledSlider(
                    "Blur",
                    value: Binding(
                        get: { effect.wrappedValue.blurRadius },
                        set: { effect.wrappedValue.blurRadius = $0 }
                    ),
                    range: 4...48
                )
            }
            if effect.wrappedValue.style == .pixelate {
                labeledSlider(
                    "Pixel Size",
                    value: Binding(
                        get: { effect.wrappedValue.pixelScale },
                        set: { effect.wrappedValue.pixelScale = $0 }
                    ),
                    range: 4...40
                )
            }
            if effect.wrappedValue.style == .label {
                TextField(
                    "Label text",
                    text: Binding(
                        get: { effect.wrappedValue.labelText },
                        set: { effect.wrappedValue.labelText = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                TextField(
                    "Emoji",
                    text: Binding(
                        get: { effect.wrappedValue.labelEmoji },
                        set: { effect.wrappedValue.labelEmoji = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
            }
            if effect.wrappedValue.style == .sticker {
                Picker(
                    "Sticker",
                    selection: Binding(
                        get: { effect.wrappedValue.sticker },
                        set: { effect.wrappedValue.sticker = $0 }
                    )
                ) {
                    ForEach(StickerSymbol.allCases) { symbol in
                        Label(symbol.title, systemImage: symbol.rawValue).tag(symbol)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "Opacity: %.0f%%", effect.wrappedValue.fillOpacity * 100))
                    .font(.caption)
                Slider(
                    value: Binding(
                        get: { effect.wrappedValue.fillOpacity },
                        set: { effect.wrappedValue.fillOpacity = $0 }
                    ),
                    in: 0.2...1.0
                )
            }

            Picker(
                "Animation",
                selection: Binding(
                    get: { effect.wrappedValue.animation },
                    set: { effect.wrappedValue.animation = $0 }
                )
            ) {
                ForEach(OverlayAnimation.allCases) { anim in
                    Text(anim.title).tag(anim)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title): \(Int(value.wrappedValue))")
                .font(.caption)
            Slider(value: value, in: range)
        }
    }
}

// MARK: - Motion

private struct MotionTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Performance")
                .font(.subheadline.weight(.semibold))

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

            Text("Tracking")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading) {
                Text("Smoothing \(String(format: "%.2f", model.configuration.motion.smoothing))")
                    .font(.caption)
                Slider(value: $model.configuration.motion.smoothing, in: 0.05...0.8)
            }

            VStack(alignment: .leading) {
                Text("Coast \(String(format: "%.0f ms", model.configuration.motion.coastSeconds * 1000))")
                    .font(.caption)
                Slider(value: $model.configuration.motion.coastSeconds, in: 0.05...0.5)
            }

            VStack(alignment: .leading) {
                Text("Padding \(String(format: "%.0f%%", model.configuration.motion.globalPadding * 100))")
                    .font(.caption)
                Slider(value: $model.configuration.motion.globalPadding, in: 0...0.35)
            }

            Toggle("Face landmark sub-regions", isOn: $model.configuration.useFaceLandmarks)

            Spacer()
        }
        .padding(14)
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
                chip(model.permissionGranted ? "Permission OK" : "Need Permission",
                     tint: model.permissionGranted ? .green : .orange)
                chip(model.modelLoaded ? "NudeNet Loaded" : "Vision Only",
                     tint: model.modelLoaded ? .blue : .secondary)
                chip("Detections \(model.activeDetectionCount)", tint: .pink)
                chip(String(format: "%.0f FPS", model.measuredFPS), tint: .purple)
                chip("Frames \(model.framesProcessed)", tint: .secondary)
                chip("AGPL-3.0", tint: .mint)
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("NudeNet 320n · Apple Vision pose · Neural Engine when available. Capture stays on-device.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(14)
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
