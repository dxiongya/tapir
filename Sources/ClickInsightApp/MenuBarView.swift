import SwiftUI
import AppKit
import ClickInsightCore

struct MenuBarView: View {
    @EnvironmentObject var recorder: Recorder
    @Environment(\.openWindow) private var openWindow
    @State private var axTrusted: Bool = Permissions.isAccessibilityTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            divider
            permissionsBlock
            divider
            statusBlock
            divider
            actions
        }
        .padding(16)
        .onAppear { refreshPermissions() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cursorarrow.click.2")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tapir").font(.headline)
                Text("貘 · 看看你今天都在点什么").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var permissionsBlock: some View {
        PermissionRow(
            title: "Accessibility",
            detail: "监听点击 + 识别 UI 元素",
            granted: axTrusted
        ) {
            _ = Permissions.isAccessibilityTrusted(prompt: true)
            openSystemSettings(pane: "Privacy_Accessibility")
            refreshPermissions()
        }
    }

    private func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private var statusBlock: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日点击").font(.caption).foregroundStyle(.secondary)
                Text("\(recorder.todayCount)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(recorder.isRunning ? Color.green : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(recorder.isRunning ? "录制中" : "已停止")
                        .font(.caption)
                }
                if let err = recorder.lastError {
                    Text(err).font(.caption2).foregroundStyle(.red)
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    recorder.isRunning ? recorder.stop() : recorder.start()
                } label: {
                    HStack {
                        Image(systemName: recorder.isRunning ? "stop.fill" : "play.fill")
                        Text(recorder.isRunning ? "停止录制" : "开始录制")
                    }
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 8) {
                Button {
                    openWindow(id: "report")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("打开报告", systemImage: "chart.bar.xaxis")
                        .frame(maxWidth: .infinity)
                }
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
            }
        }
    }

    private var divider: some View {
        Divider().opacity(0.4)
    }

    private func refreshPermissions() {
        axTrusted = Permissions.isAccessibilityTrusted()
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("授予", action: action)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
    }
}
