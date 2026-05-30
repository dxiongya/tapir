import SwiftUI
import Charts
import ClickInsightCore

// MARK: - Shared chrome

struct ReportCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let trailing: AnyView?
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        trailing: AnyView? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    if let s = subtitle {
                        Text(s)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Heatmap

struct HeatmapCard: View {
    let report: DailyReport
    @State private var image: NSImage?
    @State private var rendering: Bool = false
    @State private var toast: String?

    var body: some View {
        ReportCard(
            title: "屏幕点击热力图",
            subtitle: subtitle,
            trailing: AnyView(headerControls)
        ) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                gridLines
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .padding(1)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if rendering {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Text("暂无数据").foregroundStyle(.white.opacity(0.3))
                }
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                cornerLabels
            }
            .aspectRatio(safeAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if let toast {
                    Text(toast)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.7)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .task(id: taskID) {
            await renderHeatmap()
        }
    }

    private var headerControls: some View {
        HStack(spacing: 12) {
            legend
            shareMenu
        }
    }

    private var shareMenu: some View {
        Menu {
            Button {
                shareCopy()
            } label: {
                Label("复制图片到剪贴板", systemImage: "doc.on.doc")
            }
            Button {
                shareSave()
            } label: {
                Label("保存为 PNG…", systemImage: "square.and.arrow.down")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10, weight: .semibold))
                Text("分享")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(image == nil)
        .opacity(image == nil ? 0.4 : 1)
    }

    private func shareCopy() {
        guard let image,
              let composed = HeatmapSharing.makeShareImage(report: report, heatmap: image) else {
            showToast("生成图片失败"); return
        }
        if HeatmapSharing.copyToClipboard(composed) {
            showToast("已复制到剪贴板")
        } else {
            showToast("复制失败")
        }
    }

    private func shareSave() {
        guard let image,
              let composed = HeatmapSharing.makeShareImage(report: report, heatmap: image) else {
            showToast("生成图片失败"); return
        }
        let suggested = HeatmapSharing.suggestedFileName(for: report.date)
        HeatmapSharing.saveAsPNG(composed, suggested: suggested) { url in
            if url != nil { showToast("已保存") }
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.easeInOut(duration: 0.2)) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { toast = nil }
        }
    }

    private var safeAspect: CGFloat {
        let a = report.screenWidth / max(report.screenHeight, 1)
        return CGFloat(max(0.5, min(3.5, a)))
    }

    private var taskID: String {
        "\(Int(report.date.timeIntervalSince1970))-\(report.heatmap.count)-\(Int(report.screenWidth))x\(Int(report.screenHeight))"
    }

    private var subtitle: String {
        "屏幕 \(Int(report.screenWidth)) × \(Int(report.screenHeight)) · \(report.heatmap.count) 个聚合点"
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("少")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
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
            .frame(width: 130, height: 6)
            .clipShape(Capsule())
            Text("多")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var gridLines: some View {
        GeometryReader { proxy in
            Path { path in
                let cols = 8, rows = 5
                let w = proxy.size.width, h = proxy.size.height
                for i in 1..<cols {
                    let x = w * Double(i) / Double(cols)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                }
                for j in 1..<rows {
                    let y = h * Double(j) / Double(rows)
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Color.white.opacity(0.05), style: .init(lineWidth: 1, dash: [3, 5]))
        }
    }

    private var cornerLabels: some View {
        ZStack {
            VStack {
                HStack {
                    coordTag("0, 0")
                    Spacer()
                    coordTag("\(Int(report.screenWidth)), 0")
                }
                Spacer()
                HStack {
                    coordTag("0, \(Int(report.screenHeight))")
                    Spacer()
                    coordTag("\(Int(report.screenWidth)), \(Int(report.screenHeight))")
                }
            }
            .padding(8)
        }
    }

    private func coordTag(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.32))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(.black.opacity(0.35)))
    }

    private func renderHeatmap() async {
        rendering = true
        defer { rendering = false }
        let result = await HeatmapRenderer.render(
            points: report.heatmap,
            screenWidth: report.screenWidth,
            screenHeight: report.screenHeight
        )
        if let result {
            image = NSImage(
                cgImage: result.cgImage,
                size: NSSize(width: result.width, height: result.height)
            )
        } else {
            image = nil
        }
    }
}

// MARK: - App Ranking (leaderboard style)

struct AppRankingCard: View {
    let items: [AppRank]

    private var displayed: [AppRank] { Array(items.prefix(10)) }
    private var maxCount: Int { displayed.first?.count ?? 1 }
    private var total: Int { items.reduce(0) { $0 + $1.count } }

    var body: some View {
        ReportCard(
            title: "高频应用",
            subtitle: items.isEmpty ? nil : "Top \(displayed.count) · 共 \(total) 次"
        ) {
            if items.isEmpty {
                emptyHint
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(displayed.enumerated()), id: \.offset) { idx, item in
                        rankRow(rank: idx + 1, label: item.appName, count: item.count, tint: appTint(idx))
                    }
                }
            }
        }
    }

    private func rankRow(rank: Int, label: String, count: Int, tint: Color) -> some View {
        let frac = Double(count) / Double(max(maxCount, 1))
        let pct = Double(count) * 100.0 / Double(max(total, 1))
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 18, alignment: .trailing)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 130, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.95), tint.opacity(0.55)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, proxy.size.width * frac))
                }
            }
            .frame(height: 8)
            Text("\(count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .trailing)
                .monospacedDigit()
            Text(String(format: "%.0f%%", pct))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 38, alignment: .trailing)
                .monospacedDigit()
        }
        .frame(height: 22)
    }

    private func appTint(_ idx: Int) -> Color {
        let palette: [Color] = [.cyan, .blue, .mint, .teal, .indigo,
                                .purple, .pink, .orange, .yellow, .green]
        return palette[idx % palette.count]
    }

    private var emptyHint: some View {
        Text("暂无数据")
            .foregroundStyle(.white.opacity(0.3))
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - UI Element Ranking

struct UIElementCard: View {
    let items: [UIElementRank]

    private var displayed: [UIElementRank] { Array(items.prefix(10)) }
    private var maxCount: Int { displayed.first?.count ?? 1 }
    private var total: Int { items.reduce(0) { $0 + $1.count } }

    var body: some View {
        ReportCard(
            title: "高频 UI 元素",
            subtitle: items.isEmpty ? nil : "Top \(displayed.count) · 共 \(total) 次"
        ) {
            if items.isEmpty {
                Text("暂无 AX 数据 (部分 App 不暴露 Accessibility)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.vertical, 36)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(displayed.enumerated()), id: \.offset) { idx, item in
                        elementRow(rank: idx + 1, item: item)
                    }
                }
            }
        }
    }

    private func elementRow(rank: Int, item: UIElementRank) -> some View {
        let frac = Double(item.count) / Double(max(maxCount, 1))
        let pct = Double(item.count) * 100.0 / Double(max(total, 1))
        let tint = roleTint(item.role)
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 18, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(rolePretty(item.role))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(tint.opacity(0.85))
            }
            .frame(width: 130, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.95), tint.opacity(0.45)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(2, proxy.size.width * frac))
                }
            }
            .frame(height: 8)
            Text("\(item.count)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 44, alignment: .trailing)
                .monospacedDigit()
            Text(String(format: "%.0f%%", pct))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 38, alignment: .trailing)
                .monospacedDigit()
        }
        .frame(height: 28)
    }

    private func roleTint(_ role: String) -> Color {
        switch role {
        case "AXButton": return .pink
        case "AXTextField", "AXTextArea": return .cyan
        case "AXMenuItem", "AXMenu", "AXMenuBarItem": return .orange
        case "AXLink": return .blue
        case "AXImage": return .purple
        case "AXRow", "AXCell", "AXOutline": return .mint
        case "AXStaticText": return .teal
        default: return .indigo
        }
    }

    private func rolePretty(_ role: String) -> String {
        let trimmed = role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
        return trimmed.isEmpty ? role : trimmed
    }
}

// MARK: - Timeline

struct TimelineCard: View {
    let buckets: [HourBucket]

    private var peak: HourBucket? {
        buckets.max(by: { $0.count < $1.count }).flatMap { $0.count > 0 ? $0 : nil }
    }

    var body: some View {
        ReportCard(title: "全天节奏", subtitle: "每小时点击量分布") {
            Chart {
                ForEach(buckets) { b in
                    AreaMark(
                        x: .value("小时", b.hour),
                        y: .value("点击", b.count)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.55), Color.purple.opacity(0.0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("小时", b.hour),
                        y: .value("点击", b.count)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.purple, Color.pink],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }
                if let peak {
                    PointMark(
                        x: .value("小时", peak.hour),
                        y: .value("点击", peak.count)
                    )
                    .symbolSize(110)
                    .foregroundStyle(.pink)
                    .annotation(position: .top, spacing: 6) {
                        Text("\(peak.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.pink.opacity(0.35)))
                            .overlay(Capsule().stroke(Color.pink.opacity(0.6), lineWidth: 0.5))
                    }
                }
            }
            .chartXScale(domain: 0...23)
            .chartXAxis {
                AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21, 23]) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(.white.opacity(0.2))
                    AxisValueLabel {
                        if let h = value.as(Int.self) {
                            Text(String(format: "%02d", h))
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel()
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .chartPlotStyle { plot in
                plot.padding(.top, 24)
            }
            .frame(height: 220)
        }
    }
}
