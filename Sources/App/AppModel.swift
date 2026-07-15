import AppKit
import Combine
import Foundation
import ScreenCaptureKit

@MainActor
final class AppModel: ObservableObject {
    @Published var configuration = CensorConfiguration()
    @Published var isRunning = false
    @Published var statusMessage = "Idle"
    @Published var permissionGranted = false
    @Published var framesProcessed: UInt64 = 0
    @Published var activeDetectionCount = 0
    @Published var measuredFPS: Double = 0
    @Published var modelLoaded = false
    @Published var lastError: String?
    @Published var selectedTab: SettingsTab = .parts

    private let coordinator = CensorCoordinator()
    private var cancellables = Set<AnyCancellable>()

    enum SettingsTab: String, CaseIterable, Identifiable {
        case parts, effects, motion, status
        var id: String { rawValue }
        var title: String {
            switch self {
            case .parts: return "Parts"
            case .effects: return "Effects"
            case .motion: return "Motion"
            case .status: return "Status"
            }
        }
    }

    init() {
        bindCoordinator()
        modelLoaded = coordinator.modelLoaded
        Task {
            await refreshPermissionStatus()
        }
    }

    func refreshPermissionStatus() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            permissionGranted = CGPreflightScreenCaptureAccess()
            if permissionGranted {
                statusMessage = isRunning ? "Censoring" : "Ready"
            } else {
                statusMessage = "Screen Recording permission required"
            }
        } catch {
            permissionGranted = false
            statusMessage = "Screen Recording permission required"
            lastError = error.localizedDescription
        }
    }

    func requestPermission() {
        let granted = CGRequestScreenCaptureAccess()
        permissionGranted = granted || CGPreflightScreenCaptureAccess()
        statusMessage = permissionGranted ? "Ready" : "Open System Settings → Privacy & Security → Screen Recording"
        if !permissionGranted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func toggleRunning() {
        Task {
            if isRunning {
                await stop()
            } else {
                await start()
            }
        }
    }

    func start() async {
        lastError = nil
        await refreshPermissionStatus()
        guard permissionGranted else {
            statusMessage = "Screen Recording permission required"
            return
        }

        do {
            try await coordinator.start(configuration: configuration)
            isRunning = true
            statusMessage = "Censoring"
            modelLoaded = coordinator.modelLoaded
        } catch {
            isRunning = false
            lastError = error.localizedDescription
            statusMessage = "Failed to start"
        }
    }

    func stop() async {
        await coordinator.stop()
        isRunning = false
        activeDetectionCount = 0
        measuredFPS = 0
        statusMessage = permissionGranted ? "Ready" : "Screen Recording permission required"
    }

    func binding(for part: BodyPartID) -> Binding<BodyPartRule> {
        Binding(
            get: { self.configuration.rule(for: part) },
            set: { self.configuration.updateRule($0) }
        )
    }

    private func bindCoordinator() {
        coordinator.$framesProcessed
            .receive(on: RunLoop.main)
            .assign(to: &$framesProcessed)

        coordinator.$activeDetectionCount
            .receive(on: RunLoop.main)
            .assign(to: &$activeDetectionCount)

        coordinator.$lastError
            .receive(on: RunLoop.main)
            .assign(to: &$lastError)

        coordinator.$modelLoaded
            .receive(on: RunLoop.main)
            .assign(to: &$modelLoaded)

        coordinator.$measuredFPS
            .receive(on: RunLoop.main)
            .assign(to: &$measuredFPS)

        $configuration
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] config in
                self?.coordinator.updateConfiguration(config)
            }
            .store(in: &cancellables)
    }
}
