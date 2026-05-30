import Foundation

public enum MouseButton: Int, Codable, Sendable {
    case left = 0
    case right = 1
    case other = 2
}

public struct ClickEvent: Sendable {
    public var timestamp: Date
    public var button: MouseButton
    public var x: Double
    public var y: Double
    public var screenWidth: Double
    public var screenHeight: Double

    public var appName: String?
    public var bundleId: String?
    public var windowTitle: String?

    public var axRole: String?
    public var axSubrole: String?
    public var axTitle: String?
    public var axLabel: String?
    public var axParentChain: String?

    public var snapshotPath: String?

    public init(
        timestamp: Date,
        button: MouseButton,
        x: Double, y: Double,
        screenWidth: Double, screenHeight: Double,
        appName: String? = nil,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        axRole: String? = nil,
        axSubrole: String? = nil,
        axTitle: String? = nil,
        axLabel: String? = nil,
        axParentChain: String? = nil,
        snapshotPath: String? = nil
    ) {
        self.timestamp = timestamp
        self.button = button
        self.x = x; self.y = y
        self.screenWidth = screenWidth; self.screenHeight = screenHeight
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.axRole = axRole
        self.axSubrole = axSubrole
        self.axTitle = axTitle
        self.axLabel = axLabel
        self.axParentChain = axParentChain
        self.snapshotPath = snapshotPath
    }
}

public struct AppRank: Sendable, Identifiable {
    public let id = UUID()
    public let appName: String
    public let count: Int
}

public struct UIElementRank: Sendable, Identifiable {
    public let id = UUID()
    public let label: String
    public let role: String
    public let count: Int
}

public struct HourBucket: Sendable, Identifiable {
    public let id = UUID()
    public let hour: Int
    public let count: Int
}

public struct HeatPoint: Sendable {
    public let x: Double
    public let y: Double
    public let count: Int
}

public struct DailyReport: Sendable {
    public let date: Date
    public let totalClicks: Int
    public let leftClicks: Int
    public let rightClicks: Int
    public let topApps: [AppRank]
    public let topElements: [UIElementRank]
    public let hourly: [HourBucket]
    public let heatmap: [HeatPoint]
    public let screenWidth: Double
    public let screenHeight: Double
}
