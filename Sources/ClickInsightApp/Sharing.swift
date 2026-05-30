import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClickInsightCore

@MainActor
enum HeatmapSharing {
    static func makeShareImage(report: DailyReport, heatmap: NSImage) -> NSImage? {
        let renderer = ImageRenderer(
            content: ShareableHeatmap(report: report, heatmap: heatmap)
        )
        renderer.scale = 2.0
        renderer.proposedSize = .init(width: 1200, height: nil)
        renderer.isOpaque = true
        return renderer.nsImage
    }

    static func copyToClipboard(_ image: NSImage) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.writeObjects([image])
    }

    /// Cheap: just show the save panel and return the chosen URL. Use this first,
    /// then render the image — that way the user can cancel without paying the
    /// ImageRenderer cost and there's no main-thread freeze before the panel appears.
    @MainActor
    static func askSaveURL(suggested: String, title: String = "保存热力图") -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.title = title
        panel.isExtensionHidden = false

        // LSUIElement apps don't own focus — without an explicit activate the
        // save panel opens behind the report window and looks like a freeze.
        NSApp.activate(ignoringOtherApps: true)
        panel.level = .modalPanel

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    /// Write an already-rendered NSImage to disk as PNG.
    static func writePNG(_ image: NSImage, to url: URL) -> Bool {
        guard let data = pngData(from: image) else { return false }
        do {
            try data.write(to: url)
            return true
        } catch {
            return false
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    static func suggestedFileName(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "Tapir-\(f.string(from: date)).png"
    }
}

// MARK: - Composed shareable view

struct ShareableHeatmap: View {
    let report: DailyReport
    let heatmap: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            heatmapBlock
            statsRow
            footer
        }
        .padding(36)
        .frame(width: 1200)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.09),
                    Color(red: 0.09, green: 0.09, blue: 0.14)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    Text("Tapir")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("貘")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.leading, 2)
                }
                Text(dateString)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(report.totalClicks)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("总点击")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var heatmapBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.5))
                Image(nsImage: heatmap)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .aspectRatio(safeAspect, contentMode: .fit)
            HStack(spacing: 8) {
                Text("少").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                LinearGradient(
                    stops: [
                        .init(color: HeatmapRenderer.heatColor(0.05), location: 0.0),
                        .init(color: HeatmapRenderer.heatColor(0.30), location: 0.30),
                        .init(color: HeatmapRenderer.heatColor(0.55), location: 0.55),
                        .init(color: HeatmapRenderer.heatColor(0.80), location: 0.80),
                        .init(color: HeatmapRenderer.heatColor(1.00), location: 1.00)
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 6)
                .clipShape(Capsule())
                Text("多").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 14) {
            statTile(value: "\(report.leftClicks)", label: "左键", tint: .green)
            statTile(value: "\(report.rightClicks)", label: "右键", tint: .pink)
            statTile(value: report.topApps.first?.appName ?? "—", label: "高频 App", tint: .orange)
            statTile(value: peakHour, label: "活跃时段", tint: .purple)
            statTile(value: "\(report.screenWidth.formatted(.number.precision(.fractionLength(0)))) × \(report.screenHeight.formatted(.number.precision(.fractionLength(0))))",
                     label: "屏幕", tint: .cyan)
        }
    }

    private func statTile(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var footer: some View {
        HStack {
            Text("clickinsight · 仅本地数据")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
            Spacer()
        }
    }

    private var safeAspect: CGFloat {
        let a = report.screenWidth / max(report.screenHeight, 1)
        return CGFloat(max(0.5, min(3.5, a)))
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        return f.string(from: report.date)
    }

    private var peakHour: String {
        guard let peak = report.hourly.max(by: { $0.count < $1.count }), peak.count > 0 else { return "—" }
        return String(format: "%02d:00", peak.hour)
    }
}
