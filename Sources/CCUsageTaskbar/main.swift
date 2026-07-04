import AppKit
import Foundation

enum UsageProvider: String, CaseIterable {
    case claude
    case codex

    var menuTitle: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

enum UsagePeriod: String, CaseIterable {
    case today
    case past24Hours = "past24Hours"
    case past7Days = "past7Days"
    case monthToDate = "monthToDate"
    case past30Days = "past30Days"
    case yearToDate = "yearToDate"

    var menuTitle: String {
        switch self {
        case .today: "Today"
        case .past24Hours: "Past 24 hours"
        case .past7Days: "Past 7 days"
        case .monthToDate: "Month to date"
        case .past30Days: "Past 30 days"
        case .yearToDate: "Year to date"
        }
    }

}

enum DisplayMode: String, CaseIterable {
    case cost
    case totalTokens
    case outputTokens

    var menuTitle: String {
        switch self {
        case .cost: "Cost"
        case .totalTokens: "Total tokens"
        case .outputTokens: "Output tokens"
        }
    }
}

enum RefreshInterval: TimeInterval, CaseIterable {
    case thirtySeconds = 30
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case sixtyMinutes = 3600

    var menuTitle: String {
        switch self {
        case .thirtySeconds: "Every 30 seconds"
        case .oneMinute: "Every 1 minute"
        case .fiveMinutes: "Every 5 minutes"
        case .tenMinutes: "Every 10 minutes"
        case .sixtyMinutes: "Every 60 minutes"
        }
    }
}

struct UsageTotals: Decodable, Sendable {
    let totalCost: Double
    let totalTokens: Int64
    let outputTokens: Int64

    init(totalCost: Double, totalTokens: Int64, outputTokens: Int64) {
        self.totalCost = totalCost
        self.totalTokens = totalTokens
        self.outputTokens = outputTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCost = try container.decodeIfPresent(Double.self, forKey: .totalCost)
            ?? container.decodeIfPresent(Double.self, forKey: .costUSD)
            ?? 0
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case totalCost
        case costUSD
        case totalTokens
        case outputTokens
    }
}

struct CCUsageResponse: Decodable {
    let totals: UsageTotals
}

struct CCUsageSessionResponse: Decodable {
    let sessions: [UsageSession]
}

struct UsageSession: Decodable {
    let totalCost: Double
    let totalTokens: Int64
    let outputTokens: Int64
    let lastActivity: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalCost = try container.decodeIfPresent(Double.self, forKey: .totalCost)
            ?? container.decodeIfPresent(Double.self, forKey: .costUSD)
            ?? 0
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0

        if let value = try container.decodeIfPresent(String.self, forKey: .lastActivity) {
            lastActivity = Self.parseDate(value)
        } else {
            lastActivity = nil
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private enum CodingKeys: String, CodingKey {
        case totalCost
        case costUSD
        case totalTokens
        case outputTokens
        case lastActivity
    }
}

enum UsageError: Error, LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            message.isEmpty ? "ccusage failed." : message
        }
    }
}

enum FetchOutcome: Sendable {
    case success(UsageTotals)
    case failure(String)
}

enum UsageFetcher {
    static func fetch(executable: String, provider: UsageProvider, period: UsagePeriod) throws -> UsageTotals {
        let command: String

        switch period {
        case .today:
            command = "\(shellQuote(executable)) \(provider.rawValue) --since \(dateString(Date())) --json"
            return try decodeDailyTotals(command: command)
        case .past24Hours:
            return try fetchRollingSessionTotals(executable: executable, provider: provider, days: 1)
        case .past7Days:
            return try fetchDailyTotals(executable: executable, provider: provider, since: Date().addingTimeInterval(-7 * 24 * 60 * 60))
        case .monthToDate:
            return try fetchDailyTotals(executable: executable, provider: provider, since: startOfCurrentMonth())
        case .past30Days:
            return try fetchDailyTotals(executable: executable, provider: provider, since: Date().addingTimeInterval(-30 * 24 * 60 * 60))
        case .yearToDate:
            return try fetchDailyTotals(executable: executable, provider: provider, since: startOfCurrentYear())
        }
    }

    private static func fetchDailyTotals(executable: String, provider: UsageProvider, since: Date) throws -> UsageTotals {
        let command = "\(shellQuote(executable)) \(provider.rawValue) --since \(dateString(since)) --json"
        return try decodeDailyTotals(command: command)
    }

    private static func fetchRollingSessionTotals(executable: String, provider: UsageProvider, days: Int) throws -> UsageTotals {
        let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
        let command = "\(shellQuote(executable)) \(provider.rawValue) session --since \(dateString(cutoff)) --json"
        return try decodeSessionTotals(command: command, cutoff: cutoff)
    }

    private static func startOfCurrentMonth() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        return calendar.date(from: components) ?? Date()
    }

    private static func startOfCurrentYear() -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: Date())
        return calendar.date(from: components) ?? Date()
    }

    private static func decodeDailyTotals(command: String) throws -> UsageTotals {
        let output = try run(command: command)
        return try JSONDecoder().decode(CCUsageResponse.self, from: output).totals
    }

    private static func decodeSessionTotals(command: String, cutoff: Date) throws -> UsageTotals {
        let output = try run(command: command)
        let response = try JSONDecoder().decode(CCUsageSessionResponse.self, from: output)
        let sessions = response.sessions.filter { session in
            guard let lastActivity = session.lastActivity else {
                return false
            }
            return lastActivity >= cutoff
        }

        return UsageTotals(
            totalCost: sessions.reduce(0) { $0 + $1.totalCost },
            totalTokens: sessions.reduce(0) { $0 + $1.totalTokens },
            outputTokens: sessions.reduce(0) { $0 + $1.outputTokens }
        )
    }

    private static func run(command: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8) ?? ""
            throw UsageError.commandFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var latestTotals: UsageTotals?
    private var latestError: String?

    private let defaults = UserDefaults.standard
    private let modeKey = "displayMode"
    private let providerKey = "provider"
    private let periodKey = "period"
    private let executableKey = "executable"
    private let refreshIntervalKey = "refreshInterval"
    private let defaultExecutable = "ccusage"
    private let launchAgentID = "io.github.wangtian24.ccusage-taskbar"

    private var displayMode: DisplayMode {
        get {
            DisplayMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .cost
        }
        set {
            defaults.set(newValue.rawValue, forKey: modeKey)
            updateTitle()
            rebuildMenu()
        }
    }

    private var provider: UsageProvider {
        get {
            UsageProvider(rawValue: defaults.string(forKey: providerKey) ?? "") ?? .claude
        }
        set {
            defaults.set(newValue.rawValue, forKey: providerKey)
            refresh()
            rebuildMenu()
        }
    }

    private var period: UsagePeriod {
        get {
            UsagePeriod(rawValue: defaults.string(forKey: periodKey) ?? "") ?? .today
        }
        set {
            defaults.set(newValue.rawValue, forKey: periodKey)
            refresh()
            rebuildMenu()
        }
    }

    private var executable: String {
        get {
            let value = defaults.string(forKey: executableKey) ?? ""
            return value.isEmpty ? defaultExecutable : value
        }
        set {
            defaults.set(newValue, forKey: executableKey)
        }
    }

    private var refreshInterval: RefreshInterval {
        get {
            RefreshInterval(rawValue: defaults.double(forKey: refreshIntervalKey)) ?? .oneMinute
        }
        set {
            defaults.set(newValue.rawValue, forKey: refreshIntervalKey)
            scheduleTimer()
            rebuildMenu()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem.button?.title = "cc..."
        rebuildMenu()
        refresh()
        scheduleTimer()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    @objc private func refresh() {
        statusItem.button?.title = "..."
        let executable = executable
        let provider = provider
        let period = period

        Task.detached {
            let result: FetchOutcome
            do {
                result = .success(try UsageFetcher.fetch(executable: executable, provider: provider, period: period))
            } catch {
                result = .failure(error.localizedDescription)
            }

            await MainActor.run {
                switch result {
                case .success(let totals):
                    self.latestTotals = totals
                    self.latestError = nil
                    self.updateTitle()
                case .failure(let message):
                    self.latestError = message
                    self.statusItem.button?.title = "cc!"
                }
                self.rebuildMenu()
            }
        }
    }

    private func updateTitle() {
        guard let totals = latestTotals else {
            statusItem.button?.title = latestError == nil ? "cc..." : "cc!"
            return
        }

        switch displayMode {
        case .cost:
            statusItem.button?.title = formatCost(totals.totalCost)
        case .totalTokens:
            statusItem.button?.title = formatTokens(totals.totalTokens)
        case .outputTokens:
            statusItem.button?.title = formatTokens(totals.outputTokens)
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        if let latestTotals {
            menu.addItem(disabledItem("\(provider.menuTitle) - \(period.menuTitle)"))
            menu.addItem(disabledItem("Cost: \(formatCost(latestTotals.totalCost))"))
            menu.addItem(disabledItem("Total: \(formatTokens(latestTotals.totalTokens))"))
            menu.addItem(disabledItem("Output: \(formatTokens(latestTotals.outputTokens))"))
        }

        if let latestError {
            menu.addItem(disabledItem("Error: \(latestError)"))
        }

        if latestTotals != nil || latestError != nil {
            menu.addItem(.separator())
        }

        for mode in DisplayMode.allCases {
            let item = NSMenuItem(title: "Show \(mode.menuTitle)", action: #selector(selectDisplayMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == displayMode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        for provider in UsageProvider.allCases {
            let item = NSMenuItem(title: provider.menuTitle, action: #selector(selectProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.state = provider == self.provider ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("Time Range"))
        for period in UsagePeriod.allCases {
            let item = NSMenuItem(title: period.menuTitle, action: #selector(selectPeriod(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = period.rawValue
            item.state = period == self.period ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("Refresh Interval"))
        for interval in RefreshInterval.allCases {
            let item = NSMenuItem(title: interval.menuTitle, action: #selector(selectRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval.rawValue
            item.state = interval == refreshInterval ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r").targeting(self))
        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = isLaunchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLogin)
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",").targeting(self))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit CCUsage Taskbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = DisplayMode(rawValue: rawValue) else {
            return
        }
        displayMode = mode
    }

    @objc private func selectProvider(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selectedProvider = UsageProvider(rawValue: rawValue) else {
            return
        }
        provider = selectedProvider
    }

    @objc private func selectPeriod(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selectedPeriod = UsagePeriod(rawValue: rawValue) else {
            return
        }
        period = selectedPeriod
    }

    @objc private func selectRefreshInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? TimeInterval,
              let interval = RefreshInterval(rawValue: rawValue) else {
            return
        }
        refreshInterval = interval
    }

    @objc private func openPreferences() {
        let alert = NSAlert()
        alert.messageText = "CCUsage Executable"
        alert.informativeText = "Set this to ccusage or an absolute executable path."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        input.stringValue = executable
        alert.accessoryView = input

        if alert.runModal() == .alertFirstButtonReturn {
            executable = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            refresh()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if isLaunchAtLoginEnabled() {
                try removeLaunchAgent()
            } else {
                try installLaunchAgent()
            }
        } catch {
            latestError = error.localizedDescription
        }
        rebuildMenu()
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval.rawValue, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func formatTokens(_ value: Int64) -> String {
        let absolute = Double(abs(value))
        let sign = value < 0 ? "-" : ""
        let units: [(Double, String)] = [
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "K")
        ]

        for (threshold, suffix) in units where absolute >= threshold {
            let scaled = absolute / threshold
            let digits = scaled >= 100 ? 0 : scaled >= 10 ? 1 : 2
            return "\(sign)\(formatNumber(scaled, digits: digits))\(suffix)"
        }

        return "\(value)"
    }

    private func formatCost(_ value: Double) -> String {
        let absolute = abs(value)
        let digits: Int

        if absolute >= 100 {
            digits = 0
        } else if absolute >= 10 {
            digits = 1
        } else {
            digits = 2
        }

        return "$\(formatNumber(value, digits: digits))"
    }

    private func formatNumber(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = digits
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath.path)
    }

    private func installLaunchAgent() throws {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else {
            throw UsageError.commandFailed("Launch at Login only works from the built .app.")
        }

        let directory = launchAgentPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(launchAgentID)</string>
          <key>ProgramArguments</key>
          <array>
            <string>/usr/bin/open</string>
            <string>\(xmlEscaped(bundlePath))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
        </dict>
        </plist>
        """

        try plist.write(to: launchAgentPath, atomically: true, encoding: .utf8)
    }

    private func removeLaunchAgent() throws {
        guard isLaunchAtLoginEnabled() else {
            return
        }
        try FileManager.default.removeItem(at: launchAgentPath)
    }

    private var launchAgentPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentID).plist")
    }

    private func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private extension NSMenuItem {
    func targeting(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
