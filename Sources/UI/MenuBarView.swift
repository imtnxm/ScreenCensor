import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            targetsSection
            Divider()
            styleSection
            Divider()
            performanceSection
            Divider()
            statusSection
            controls
        }
        .padding(16)
        .frame(width: 320)
    }

    private var header: some View {
        HStack {
            Image(systemName: "eye.slash.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("ScreenCensor")
                    .font(.headline)
                Text("On-device real-time censoring")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detection Targets")
                .font(.subheadline.weight(.semibold))

            Toggle("Face", isOn: $model.configuration.targets.face)
            Toggle("Skin (proxy)", isOn: $model.configuration.targets.skin)
            Toggle("Intimate Zones", isOn: $model.configuration.targets.intimateZones)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Censor Style")
                .font(.subheadline.weight(.semibold))

            Picker("Style", selection: $model.configuration.style) {
                ForEach(CensorStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)

            if model.configuration.style == .text {
                TextField("Censor text", text: $model.configuration.censorText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Performance")
                .font(.subheadline.weight(.semibold))

            Picker("Mode", selection: $model.configuration.performanceMode) {
                ForEach(PerformanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()

            Text("Target \(model.configuration.performanceMode.targetFrameRate) FPS · frames drop automatically under load")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(model.statusMessage, systemImage: model.isRunning ? "waveform" : "pause.circle")
                .font(.subheadline)

            HStack {
                statusChip(
                    title: model.permissionGranted ? "Permission OK" : "Permission Needed",
                    tint: model.permissionGranted ? .green : .orange
                )
                statusChip(title: "Detections \(model.activeDetectionCount)", tint: .blue)
                statusChip(title: "Frames \(model.framesProcessed)", tint: .secondary)
            }

            if let lastError = model.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }
        }
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
                Button("Permission") {
                    model.requestPermission()
                }
                .buttonStyle(.bordered)

                Button("Refresh Status") {
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
    }

    private func statusChip(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint == .secondary ? Color.secondary : tint)
    }
}
