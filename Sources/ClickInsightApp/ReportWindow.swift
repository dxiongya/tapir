import SwiftUI
import ClickInsightCore

struct ReportWindow: View {
    @EnvironmentObject var recorder: Recorder
    @State private var date: Date = Date()
    @State private var report: DailyReport?
    @State private var loading: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.09),
                    Color(red: 0.08, green: 0.08, blue: 0.13)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 24)
                    VStack(alignment: .leading, spacing: 24) {
                        headerBar
                        if let r = report {
                            summaryRow(r: r)
                            HeatmapCard(report: r)
                            TimelineCard(buckets: r.hourly)
                            HStack(alignment: .top, spacing: 20) {
                                AppRankingCard(items: r.topApps)
                                UIElementCard(items: r.topElements)
                            }
                        } else if loading {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                                .frame(maxWidth: .infinity, minHeight: 420)
                        } else {
                            emptyState
                        }
                    }
                    .frame(maxWidth: 1240)
                    Spacer(minLength: 24)
                }
                .padding(.vertical, 32)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: date) {
            await refresh()
        }
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Tapir")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("貘")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.leading, 2)
                }
                Text(dateString)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .colorScheme(.dark)
            Button {
                Task { await refresh() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy 年 M 月 d 日 EEEE"
        return f.string(from: date)
    }

    private func summaryRow(r: DailyReport) -> some View {
        HStack(spacing: 14) {
            SummaryTile(title: "总点击",
                        value: numberString(r.totalClicks),
                        icon: "cursorarrow.click.2",
                        tint: .cyan)
            SummaryTile(title: "左键",
                        value: numberString(r.leftClicks),
                        icon: "hand.point.up.left.fill",
                        tint: .green)
            SummaryTile(title: "右键",
                        value: numberString(r.rightClicks),
                        icon: "hand.point.up.right.fill",
                        tint: .pink)
            SummaryTile(title: "高频 App",
                        value: r.topApps.first?.appName ?? "—",
                        icon: "app.dashed",
                        tint: .orange)
            SummaryTile(title: "活跃时段",
                        value: peakHourLabel(r.hourly),
                        icon: "clock.fill",
                        tint: .purple)
        }
    }

    private func numberString(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func peakHourLabel(_ buckets: [HourBucket]) -> String {
        guard let peak = buckets.max(by: { $0.count < $1.count }), peak.count > 0 else { return "—" }
        return String(format: "%02d:00", peak.hour)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "cursorarrow.click.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.3))
            Text("当天还没有点击数据")
                .foregroundStyle(.white.opacity(0.6))
            Text("从菜单栏打开「Tapir」面板，按下「开始录制」")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        let storage = recorder.storage
        let d = date
        let snapshot = await Task.detached {
            storage.report(for: d)
        }.value
        self.report = snapshot.totalClicks > 0 ? snapshot : nil
    }
}

struct SummaryTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .monospacedDigit()
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
