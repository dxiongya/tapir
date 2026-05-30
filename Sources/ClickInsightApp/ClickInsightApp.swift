import SwiftUI
import AppKit
import ClickInsightCore

@main
struct ClickInsightApp: App {
    @StateObject private var recorder = AppBoot.shared.recorder

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(recorder)
                .frame(width: 320)
        } label: {
            Image(systemName: recorder.isRunning ? "cursorarrow.click.2" : "cursorarrow")
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Tapir · 每日点击报告", id: "report") {
            ReportWindow()
                .environmentObject(recorder)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppBoot {
    static let shared = AppBoot()
    let recorder: Recorder
    private init() {
        do {
            self.recorder = try Recorder()
        } catch {
            fatalError("Recorder init failed: \(error)")
        }
    }
}
