import Foundation
import SQLite3

public final class Storage: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "ClickInsight.Storage")

    public let dbURL: URL
    public let snapshotsDir: URL

    public init() throws {
        let fm = FileManager.default
        let appSupport = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("ClickInsight", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.dbURL = dir.appendingPathComponent("events.db")
        self.snapshotsDir = dir.appendingPathComponent("snapshots", isDirectory: true)
        try fm.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)

        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            throw NSError(domain: "ClickInsight.Storage", code: 1, userInfo: [NSLocalizedDescriptionKey: "open failed"])
        }
        try migrate()
    }

    deinit { if let db { sqlite3_close(db) } }

    private func migrate() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS clicks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts REAL NOT NULL,
            button INTEGER NOT NULL,
            x REAL NOT NULL,
            y REAL NOT NULL,
            screen_w REAL,
            screen_h REAL,
            app_name TEXT,
            bundle_id TEXT,
            window_title TEXT,
            ax_role TEXT,
            ax_subrole TEXT,
            ax_title TEXT,
            ax_label TEXT,
            ax_parent_chain TEXT,
            snapshot_path TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_clicks_ts ON clicks(ts);
        CREATE INDEX IF NOT EXISTS idx_clicks_app ON clicks(app_name);
        """
        try exec(sql)
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw NSError(domain: "ClickInsight.Storage", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    public func insert(_ e: ClickEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            let sql = """
            INSERT INTO clicks (ts, button, x, y, screen_w, screen_h, app_name, bundle_id, window_title,
                                ax_role, ax_subrole, ax_title, ax_label, ax_parent_chain, snapshot_path)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, e.timestamp.timeIntervalSince1970)
            sqlite3_bind_int(stmt, 2, Int32(e.button.rawValue))
            sqlite3_bind_double(stmt, 3, e.x)
            sqlite3_bind_double(stmt, 4, e.y)
            sqlite3_bind_double(stmt, 5, e.screenWidth)
            sqlite3_bind_double(stmt, 6, e.screenHeight)
            self.bindText(stmt, 7, e.appName)
            self.bindText(stmt, 8, e.bundleId)
            self.bindText(stmt, 9, e.windowTitle)
            self.bindText(stmt, 10, e.axRole)
            self.bindText(stmt, 11, e.axSubrole)
            self.bindText(stmt, 12, e.axTitle)
            self.bindText(stmt, 13, e.axLabel)
            self.bindText(stmt, 14, e.axParentChain)
            self.bindText(stmt, 15, e.snapshotPath)
            sqlite3_step(stmt)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ v: String?) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        if let v {
            sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, idx)
        }
    }

    // MARK: - Queries

    public func updateSnapshotPath(id: Int64, path: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let sql = "UPDATE clicks SET snapshot_path = ? WHERE id = ?;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            self.bindText(stmt, 1, path)
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
        }
    }

    public func totalClicksToday() -> Int {
        let (start, end) = Self.dayRange(Date())
        return queue.sync { countClicks(from: start, to: end) }
    }

    public func report(for date: Date) -> DailyReport {
        let (start, end) = Self.dayRange(date)
        return queue.sync { buildReport(date: date, from: start, to: end) }
    }

    private static func dayRange(_ d: Date) -> (Double, Double) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: d)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return (start.timeIntervalSince1970, end.timeIntervalSince1970)
    }

    private func countClicks(from: Double, to: Double) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT COUNT(*) FROM clicks WHERE ts >= ? AND ts < ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_double(stmt, 1, from)
        sqlite3_bind_double(stmt, 2, to)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func buildReport(date: Date, from: Double, to: Double) -> DailyReport {
        let total = countClicks(from: from, to: to)
        let left = countByButton(from: from, to: to, button: 0)
        let right = countByButton(from: from, to: to, button: 1)
        let apps = topApps(from: from, to: to, limit: 12)
        let elements = topElements(from: from, to: to, limit: 12)
        let hourly = hourlyBuckets(from: from, to: to)
        let heat = heatmapPoints(from: from, to: to)
        let (sw, sh) = screenDimensions(from: from, to: to)
        return DailyReport(
            date: date,
            totalClicks: total,
            leftClicks: left,
            rightClicks: right,
            topApps: apps,
            topElements: elements,
            hourly: hourly,
            heatmap: heat,
            screenWidth: sw,
            screenHeight: sh
        )
    }

    private func countByButton(from: Double, to: Double, button: Int) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT COUNT(*) FROM clicks WHERE ts >= ? AND ts < ? AND button = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        sqlite3_bind_double(stmt, 1, from)
        sqlite3_bind_double(stmt, 2, to)
        sqlite3_bind_int(stmt, 3, Int32(button))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func topApps(from: Double, to: Double, limit: Int) -> [AppRank] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        SELECT COALESCE(app_name, 'Unknown') AS name, COUNT(*) AS c
        FROM clicks WHERE ts >= ? AND ts < ?
        GROUP BY name ORDER BY c DESC LIMIT ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_double(stmt, 1, from)
        sqlite3_bind_double(stmt, 2, to)
        sqlite3_bind_int(stmt, 3, Int32(limit))
        var out: [AppRank] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 0))
            let c = Int(sqlite3_column_int64(stmt, 1))
            out.append(AppRank(appName: name, count: c))
        }
        return out
    }

    private func topElements(from: Double, to: Double, limit: Int) -> [UIElementRank] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        SELECT COALESCE(NULLIF(ax_title, ''), NULLIF(ax_label, ''), ax_role, 'Unknown') AS label,
               COALESCE(ax_role, '?') AS role,
               COUNT(*) AS c
        FROM clicks WHERE ts >= ? AND ts < ?
        GROUP BY label, role ORDER BY c DESC LIMIT ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_double(stmt, 1, from)
        sqlite3_bind_double(stmt, 2, to)
        sqlite3_bind_int(stmt, 3, Int32(limit))
        var out: [UIElementRank] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let label = String(cString: sqlite3_column_text(stmt, 0))
            let role = String(cString: sqlite3_column_text(stmt, 1))
            let c = Int(sqlite3_column_int64(stmt, 2))
            out.append(UIElementRank(label: label, role: role, count: c))
        }
        return out
    }

    private func hourlyBuckets(from: Double, to: Double) -> [HourBucket] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        SELECT CAST(strftime('%H', ts, 'unixepoch', 'localtime') AS INTEGER) AS hour, COUNT(*)
        FROM clicks WHERE ts >= ? AND ts < ?
        GROUP BY hour ORDER BY hour;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_double(stmt, 1, from)
        sqlite3_bind_double(stmt, 2, to)
        var dict: [Int: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let h = Int(sqlite3_column_int(stmt, 0))
            let c = Int(sqlite3_column_int64(stmt, 1))
            dict[h] = c
        }
        return (0..<24).map { HourBucket(hour: $0, count: dict[$0] ?? 0) }
    }

    private func heatmapPoints(from: Double, to: Double) -> [HeatPoint] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        SELECT ROUND(x / 4.0) * 4.0 AS bx, ROUND(y / 4.0) * 4.0 AS by, COUNT(*) AS c
        FROM clicks WHERE ts >= ? AND ts < ?
        GROUP BY bx, by;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_double(stmt, 1, from)
        sqlite3_bind_double(stmt, 2, to)
        var out: [HeatPoint] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bx = sqlite3_column_double(stmt, 0)
            let by = sqlite3_column_double(stmt, 1)
            let c = Int(sqlite3_column_int64(stmt, 2))
            out.append(HeatPoint(x: bx, y: by, count: c))
        }
        return out
    }

    private func screenDimensions(from: Double, to: Double) -> (Double, Double) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        SELECT MAX(screen_w), MAX(screen_h) FROM clicks WHERE ts >= ? AND ts < ?;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (1920, 1080) }
        sqlite3_bind_double(stmt, 1, from)
        sqlite3_bind_double(stmt, 2, to)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (1920, 1080) }
        let w = sqlite3_column_double(stmt, 0)
        let h = sqlite3_column_double(stmt, 1)
        return (w > 0 ? w : 1920, h > 0 ? h : 1080)
    }
}
