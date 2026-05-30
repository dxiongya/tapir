import Foundation
import AppKit
import CoreGraphics

@MainActor
public final class Recorder: ObservableObject {
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var todayCount: Int = 0
    @Published public private(set) var lastError: String?

    public let storage: Storage
    private var tap: EventTap?
    private var refreshTimer: Timer?

    public init() throws {
        self.storage = try Storage()
        self.todayCount = storage.totalClicksToday()
    }

    public func start() {
        guard !isRunning else { return }
        guard Permissions.isAccessibilityTrusted() else {
            lastError = "Accessibility 权限未授予"
            return
        }
        let tap = EventTap { [weak self] type, point, _ in
            self?.handle(type: type, point: point)
        }
        if tap.start() {
            self.tap = tap
            isRunning = true
            lastError = nil
            startRefreshTimer()
        } else {
            lastError = "事件 Tap 启动失败，请确认 Accessibility 权限"
        }
    }

    public func stop() {
        tap?.stop()
        tap = nil
        isRunning = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.todayCount = self.storage.totalClicksToday()
            }
        }
    }

    private func handle(type: CGEventType, point: CGPoint) {
        let button: MouseButton
        switch type {
        case .leftMouseDown: button = .left
        case .rightMouseDown: button = .right
        default: button = .other
        }

        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let ctx = ContextResolver.resolve(at: point)

        let event = ClickEvent(
            timestamp: Date(),
            button: button,
            x: Double(point.x), y: Double(point.y),
            screenWidth: Double(screen.width), screenHeight: Double(screen.height),
            appName: ctx.appName,
            bundleId: ctx.bundleId,
            windowTitle: ctx.windowTitle,
            axRole: ctx.axRole,
            axSubrole: ctx.axSubrole,
            axTitle: ctx.axTitle,
            axLabel: ctx.axLabel,
            axParentChain: ctx.axParentChain
        )
        storage.insert(event)
    }
}
