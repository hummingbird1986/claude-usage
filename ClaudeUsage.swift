// ClaudeUsage.swift — macOS menu bar app
// Reads token usage directly from Claude Code's local JSONL logs.
// Optionally uses the Admin API (org accounts only) if a key is set in Keychain.
//
// Build: bash ~/.config/claude-usage/build.sh

import AppKit
import Foundation
import Security

// MARK: – Keychain (optional, for org-account Admin API key)

private let kService = "com.hummingbird.claude-usage"
private let kAccount = "admin_api_key"

func keychainSave(_ value: String) {
    let data = value.data(using: .utf8)!
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: kService,
                             kSecAttrAccount as String: kAccount,
                             kSecValueData as String: data]
    SecItemDelete(q as CFDictionary)
    SecItemAdd(q as CFDictionary, nil)
}

func keychainLoad() -> String? {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: kService,
                             kSecAttrAccount as String: kAccount,
                             kSecReturnData as String: true,
                             kSecMatchLimit as String: kSecMatchLimitOne]
    var ref: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess,
          let data = ref as? Data else { return nil }
    return String(data: data, encoding: .utf8)
}

func keychainDelete() {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                             kSecAttrService as String: kService,
                             kSecAttrAccount as String: kAccount]
    SecItemDelete(q as CFDictionary)
}

// MARK: – Config

struct Config {
    let dailyBudget: Double
    let refreshInterval: TimeInterval
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/claude-usage/config.json")
    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return Config(dailyBudget: 0, refreshInterval: 60) }
        return Config(dailyBudget: j["daily_budget"] as? Double ?? 0,
                      refreshInterval: j["refresh_interval"] as? Double ?? 60)
    }
}

// MARK: – Pricing

typealias Rates = (i: Double, o: Double, cr: Double, cw: Double)
let kCosts: [String: Rates] = [
    "claude-fable-5":    (10.0, 50.0, 1.0,  12.5),
    "claude-opus-4-8":   (5.0,  25.0, 0.5,  6.25),
    "claude-opus-4-7":   (5.0,  25.0, 0.5,  6.25),
    "claude-opus-4-6":   (5.0,  25.0, 0.5,  6.25),
    "claude-sonnet-4-6": (3.0,  15.0, 0.3,  3.75),
    "claude-haiku-4-5":  (1.0,  5.0,  0.1,  1.25),
]
func rates(_ m: String) -> Rates {
    if let r = kCosts[m] { return r }
    for (k, v) in kCosts where m.hasPrefix(k) { return v }
    return (5.0, 25.0, 0.5, 6.25)
}

// MARK: – Usage model

struct ModelUsage {
    var input_tokens: Int = 0
    var output_tokens: Int = 0
    var cache_read_input_tokens: Int = 0
    var cache_creation_input_tokens: Int = 0
    var requests: Int = 0
}
typealias DayUsage = [String: ModelUsage]

func calcCost(_ u: DayUsage) -> Double {
    u.reduce(0) { s, kv in
        let r = rates(kv.key); let t = kv.value
        return s + Double(t.input_tokens)/1e6*r.i + Double(t.output_tokens)/1e6*r.o
             + Double(t.cache_read_input_tokens)/1e6*r.cr
             + Double(t.cache_creation_input_tokens)/1e6*r.cw
    }
}

func fmtTok(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.2fM", Double(n)/1e6)
    case 1_000...:     return String(format: "%.1fK", Double(n)/1e3)
    default:           return "\(n)"
    }
}

// MARK: – Claude Code JSONL log parser

func parseClaudeCodeLogs() -> DayUsage {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let projectsDir = home.appendingPathComponent(".claude/projects")
    guard fm.fileExists(atPath: projectsDir.path) else { return [:] }

    let todayStart = Calendar.current.startOfDay(for: Date())
    let isoFull = ISO8601DateFormatter()
    isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoBasic = ISO8601DateFormatter()

    var result = DayUsage()
    var seenUUIDs = Set<String>()

    guard let enumerator = fm.enumerator(
        at: projectsDir,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else { return result }

    for case let fileURL as URL in enumerator {
        guard fileURL.pathExtension == "jsonl" else { continue }
        // Skip files not touched today (fast pre-filter)
        if let mod = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                                  .contentModificationDate, mod < todayStart { continue }

        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg   = obj["message"] as? [String: Any],
                  let model = msg["model"] as? String,
                  let usage = msg["usage"] as? [String: Any]
            else { continue }

            // Deduplicate: same uuid = duplicate streaming entry
            let uuid = obj["uuid"] as? String ?? line.description
            guard seenUUIDs.insert(uuid).inserted else { continue }

            // Filter by today's date
            if let tsStr = obj["timestamp"] as? String {
                let ts = isoFull.date(from: tsStr) ?? isoBasic.date(from: tsStr)
                if let ts = ts, ts < todayStart { continue }
            }

            var mu = result[model] ?? ModelUsage()
            mu.input_tokens                += usage["input_tokens"]                as? Int ?? 0
            mu.output_tokens               += usage["output_tokens"]               as? Int ?? 0
            mu.cache_read_input_tokens     += usage["cache_read_input_tokens"]     as? Int ?? 0
            mu.cache_creation_input_tokens += usage["cache_creation_input_tokens"] as? Int ?? 0
            mu.requests                    += 1
            result[model] = mu
        }
    }
    return result
}

// MARK: – Admin API (org accounts only)

struct APIResponse: Decodable {
    struct Bucket: Decodable {
        struct Entry: Decodable {
            let model: String
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation_input_tokens: Int?
        }
        let usage: [Entry]
    }
    let data: [Bucket]
}

func fetchAdminAPI(adminKey: String) async throws -> DayUsage {
    let fmt = ISO8601DateFormatter()
    let today = fmt.string(from: Calendar.current.startOfDay(for: Date()))
    let now   = fmt.string(from: Date())
    let urlStr = "https://api.anthropic.com/v1/organizations/usage_report/messages"
        + "?starting_at=\(today)&ending_at=\(now)&bucket_width=1d&group_by%5B%5D=model"
    var req = URLRequest(url: URL(string: urlStr)!, timeoutInterval: 15)
    req.setValue("2023-06-01",           forHTTPHeaderField: "anthropic-version")
    req.setValue(adminKey,               forHTTPHeaderField: "x-api-key")
    req.setValue("claude-usage-bar/1.0", forHTTPHeaderField: "User-Agent")
    let (data, resp) = try await URLSession.shared.data(for: req)
    if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
        throw NSError(domain: "API", code: http.statusCode,
                      userInfo: [NSLocalizedDescriptionKey:
                        "HTTP \(http.statusCode): \(String(data: data, encoding: .utf8)?.prefix(120) ?? "")"])
    }
    let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
    var result = DayUsage()
    for bucket in decoded.data {
        for e in bucket.usage {
            var mu = result[e.model] ?? ModelUsage()
            mu.input_tokens                += e.input_tokens ?? 0
            mu.output_tokens               += e.output_tokens ?? 0
            mu.cache_read_input_tokens     += e.cache_read_input_tokens ?? 0
            mu.cache_creation_input_tokens += e.cache_creation_input_tokens ?? 0
            result[e.model] = mu
        }
    }
    return result
}

// MARK: – Display mode

enum DisplayMode: String {
    case cost   = "cost"
    case tokens = "tokens"
    static let key = "displayMode"
    static func load() -> DisplayMode {
        DisplayMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .cost
    }
    func save() { UserDefaults.standard.set(rawValue, forKey: DisplayMode.key) }
    var toggled: DisplayMode { self == .cost ? .tokens : .cost }
    var menuLabel: String { self == .cost ? "切换为显示 Token 数" : "切换为显示等价费用 ($)" }
}

// MARK: – AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var refreshTimer: Timer?
    var lastUsage = DayUsage()
    var lastSource = "Claude Code logs"
    var lastError: String? = nil
    var lastHasKey = false

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            if let img = Bundle.main.image(forResource: "TrayIconTemplate") {
                img.isTemplate = true   // adapts to light/dark menu bar automatically
                img.size = NSSize(width: 16, height: 16)
                btn.image = img
                btn.imagePosition = .imageLeft
            }
            btn.title = " ..."
        }
        statusItem.menu = NSMenu()
        startRefresh()
        Task { await fetchAndRender() }
    }

    func startRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: Config.load().refreshInterval, repeats: true
        ) { [weak self] _ in Task { await self?.fetchAndRender() } }
    }

    @objc func onRefresh() {
        statusItem.button?.title = "☁ ..."
        Task { await fetchAndRender() }
    }

    @MainActor
    func fetchAndRender() async {
        let cfg = Config.load()
        let key = keychainLoad()?.trimmingCharacters(in: .whitespaces) ?? ""
        var usage = DayUsage(); var err: String?; var source = "Claude Code logs"

        if !key.isEmpty {
            do {
                usage = try await fetchAdminAPI(adminKey: key)
                source = "Admin API"
            } catch {
                err = error.localizedDescription
                usage = parseClaudeCodeLogs()
                source = "Claude Code logs (API error)"
            }
        } else {
            usage = parseClaudeCodeLogs()
        }
        lastUsage = usage; lastError = err; lastSource = source; lastHasKey = !key.isEmpty
        renderMenu(usage: usage, error: err, source: source, cfg: cfg, hasKey: !key.isEmpty)
    }

    @objc @MainActor func onToggleDisplay() {
        let mode = DisplayMode.load().toggled
        mode.save()
        renderMenu(usage: lastUsage, error: lastError, source: lastSource,
                   cfg: Config.load(), hasKey: lastHasKey)
    }

    // MARK: Menu

    @MainActor
    func renderMenu(usage: DayUsage, error: String?, source: String, cfg: Config, hasKey: Bool) {
        let totalCost = calcCost(usage)
        let over = cfg.dailyBudget > 0 && totalCost >= cfg.dailyBudget * 0.9
        let totalIn  = usage.values.reduce(0) { $0 + $1.input_tokens }
        let totalOut = usage.values.reduce(0) { $0 + $1.output_tokens }
        let totalCR  = usage.values.reduce(0) { $0 + $1.cache_read_input_tokens }
        let totalReq = usage.values.reduce(0) { $0 + $1.requests }

        let mode = DisplayMode.load()
        let warn = over ? "⚠ " : ""
        statusItem.button?.title = mode == .cost
            ? String(format: " \(warn)$%.2f", totalCost)
            : " \(warn)\(fmtTok(totalIn + totalOut))"

        let menu = NSMenu()
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        addLabel(menu, "Claude Code — \(dateStr)")
        menu.addItem(.separator())
        let budStr   = cfg.dailyBudget > 0 ? String(format: " / $%.2f", cfg.dailyBudget) : ""
        addLabel(menu, String(format: "等价 API 费用:  $%.4f\(budStr)", totalCost))
        addLabel(menu, "（订阅用户仅供参考）")
        addLabel(menu, "────────────────────")
        addLabel(menu, "Requests: \(totalReq)")
        addLabel(menu, "Input:    \(fmtTok(totalIn))")
        addLabel(menu, "Output:   \(fmtTok(totalOut))")
        addLabel(menu, "Cache:    \(fmtTok(totalCR)) read")

        menu.addItem(.separator())
        if usage.isEmpty {
            addLabel(menu, "No activity today")
        } else {
            for (model, t) in usage.sorted(by: { $0.key < $1.key }) {
                let c = calcCost([model: t])
                let lbl = model.replacingOccurrences(of: "claude-", with: "")
                addLabel(menu, String(format: "  %@:  $%.4f  (%@↑ %@↓)",
                                      lbl, c, fmtTok(t.input_tokens), fmtTok(t.output_tokens)))
            }
        }

        menu.addItem(.separator())
        if let err = error { addLabel(menu, "⚠ \(err.prefix(80))") }
        let tf = DateFormatter(); tf.timeStyle = .short; tf.dateStyle = .none
        addLabel(menu, "Updated \(tf.string(from: Date())) · \(source)")

        addAction(menu, "Refresh", #selector(onRefresh))
        addAction(menu, mode.menuLabel, #selector(onToggleDisplay))
        menu.addItem(.separator())
        addAction(menu, hasKey ? "更改 Admin Key…" : "设置 Admin Key (组织账户)…", #selector(onSetKey))
        if hasKey { addAction(menu, "删除 Admin Key", #selector(onRemoveKey)) }
        menu.addItem(.separator())
        let q = menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        q.target = NSApp

        statusItem.menu = menu
    }

    // MARK: Admin key management

    @objc func onSetKey() {
        let alert = NSAlert()
        alert.messageText     = "设置 Admin API Key"
        alert.informativeText = "组织账户专用。个人账户无需设置，已自动读取 Claude Code 日志。\n\n获取方式：Console → Settings → API Keys → Admin Keys"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "sk-ant-admin01-..."
        if let existing = keychainLoad() { field.stringValue = existing }
        alert.accessoryView = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let key = field.stringValue.trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { keychainSave(key) } else { keychainDelete() }
            Task { await fetchAndRender() }
        }
    }

    @objc func onRemoveKey() {
        keychainDelete()
        Task { await fetchAndRender() }
    }

    func addLabel(_ m: NSMenu, _ t: String) {
        let item = m.addItem(withTitle: t, action: nil, keyEquivalent: "")
        item.isEnabled = false
    }
    func addAction(_ m: NSMenu, _ t: String, _ s: Selector) {
        m.addItem(withTitle: t, action: s, keyEquivalent: "").target = self
    }
}

// MARK: – Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
