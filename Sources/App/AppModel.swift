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
    @Published var lastError: String?

    private let coordinator = CensorCoordinator()
    private var cancellables = Set<AnyCancellable>()

    init() {
        bindCoordinator()
        Task {
            await refreshPermissionStatus()
        }
    }

    func refreshPermissionStatus() async {
        do {
            // Touching shareable content forces the TCC prompt when needed.
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
        statusMessage = permissionGranted ? "Ready" : "Screen Recording permission required"
    }

    func applyConfiguration() {
        coordinator.updateConfiguration(configuration)
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

        $configuration
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] config in
                self?.coordinator.updateConfiguration(config)
            }
            .store(in: &cancellables)
    }
}
