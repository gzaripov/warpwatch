// warpwatch-bar — a tiny native macOS menu-bar app for warpwatch.
//
// Reads ~/.claude/warpwatch/state/tabs.tsv and shows, in the menu bar, the
// Warp logo mark followed by a status dot: grey=idle, teal=working, and an
// attn dot that PULSES (a bright core with a breathing halo) while a tab is
// waiting, to get your attention. The dropdown lists each tab with a haloed
// status dot — click one to jump to that exact Warp tab via its warp://session
// deep link. No SwiftBar, no third-party host.
//
// Build:  swiftc -O warpwatch-bar.swift -o warpwatch-bar
// Env: WARPWATCH_HOME (default ~/.claude/warpwatch), WARPWATCH_STATE,
//      WARPWATCH_PULSE=0 to disable the animation.

import Cocoa

final class WarpwatchApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let root: String
    let stateFile: String
    let iconsDir: String
    let pulseEnabled: Bool

    let attn   = NSColor(red: 1.0,  green: 0.62, blue: 0.04, alpha: 1)   // amber  — needs your input
    let teal   = NSColor(red: 0.06, green: 0.69, blue: 0.71, alpha: 1)   // teal   — working
    let purple = NSColor(red: 0.49, green: 0.36, blue: 0.96, alpha: 1)   // purple — awaiting review
    let danger = NSColor(red: 1.0,  green: 0.27, blue: 0.23, alpha: 1)   // red    — error
    let slate  = NSColor(white: 0.62, alpha: 1)

    enum St { case idle, attention, working, error }
    func statusKind(_ s: String) -> St {
        switch s {
        case "working": return .working
        case "error":   return .error
        default:        return .attention   // input / review / waiting — your turn
        }
    }

    var warpMark: NSImage!
    var agentImages: [String: NSImage] = [:]   // cached per-agent SVG marks

    var refreshTimer: Timer?
    var pulseTimer: Timer?
    var phase: Double = 0
    var barAttention = 0
    var barWorking = 0
    var barError = 0
    var menuTimer: Timer?
    var menuPhase: Double = 0
    var animItems: [(item: NSMenuItem, kind: St, name: String, epoch: Int, agent: String)] = []   // rows animated while the menu is open
    let thick = NSStatusBar.system.thickness   // menu-bar height (~22–24pt)

    override init() {
        let home = NSHomeDirectory()
        let env = ProcessInfo.processInfo.environment
        root = env["WARPWATCH_HOME"] ?? "\(home)/.claude/warpwatch"
        stateFile = env["WARPWATCH_STATE"] ?? "\(root)/state/tabs.tsv"
        iconsDir = "\(root)/icons"
        pulseEnabled = (env["WARPWATCH_PULSE"] ?? "1") != "0"
        super.init()
    }

    // MARK: icons

    func loadImage(_ file: String, size: NSSize) -> NSImage? {
        guard let img = NSImage(contentsOfFile: "\(iconsDir)/\(file)") else { return nil }
        img.size = size
        img.isTemplate = false
        return img
    }

    func stColor(_ k: St) -> NSColor {
        switch k {
        case .attention: return attn
        case .working:   return teal
        case .error:     return danger
        case .idle:      return slate
        }
    }

    // one status glyph, shared by the menu bar and the dropdown rows
    func statusIcon(_ kind: St, phase: Double, box s: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: s, height: s)); img.lockFocus()
        let c = s / 2
        switch kind {
        case .idle:
            let mh = s * 0.82, mw = mh * (268.0 / 214.0)
            warpMark?.draw(in: NSRect(x: (s - mw) / 2, y: (s - mh) / 2, width: mw, height: mh))
        case .attention:
            // amber dot with a breathing halo glow — your turn
            let t = CGFloat((cos(phase) + 1) / 2)                 // 0 → 1
            attn.withAlphaComponent(0.14 + 0.30 * t).setFill()
            fillOval(c, c, s * (0.32 + 0.16 * t))                 // halo breathes 0.32 → 0.48
            attn.setFill()
            fillOval(c, c, s * 0.30)                              // solid core
        case .working:
            drawArc(c, c, r: s * 0.40, width: s * 0.17, start: phase, sweep: .pi * 1.5, color: teal)
        case .error:
            danger.setFill(); fillOval(c, c, s * 0.46)                       // red disc + white "!"
            NSColor.white.setStroke()
            let v = NSBezierPath()
            v.move(to: NSPoint(x: c, y: s * 0.70)); v.line(to: NSPoint(x: c, y: s * 0.40))
            v.lineWidth = s * 0.13; v.lineCapStyle = .round; v.stroke()
            NSColor.white.setFill(); fillOval(c, s * 0.30, s * 0.07)
        }
        img.unlockFocus(); img.isTemplate = false; return img
    }

    func fillOval(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    }

    // Menu-bar icon: Warp mark on the left, status dot on the right. While
    // waiting the dot is a bright core with a breathing translucent halo.
    // a stroked arc — used for the "working" spinner
    func drawArc(_ cx: CGFloat, _ cy: CGFloat, r: CGFloat, width: CGFloat, start: Double, sweep: Double, color: NSColor) {
        let p = NSBezierPath()
        p.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: r,
                    startAngle: CGFloat(start * 180 / .pi),
                    endAngle: CGFloat((start + sweep) * 180 / .pi))
        p.lineWidth = width
        p.lineCapStyle = .round
        color.setStroke()
        p.stroke()
    }

    // menu bar: Warp mark + a big status glyph & count per active state.
    // Order = urgency (error, attention, working). Idle = just the Warp mark.
    func barComposite(phase: Double) -> NSImage {
        let s = thick
        let markH = s * 0.60, markW = markH * (268.0 / 214.0)
        let icoD = s * 0.76                                        // big status glyphs (a touch smaller)
        let font = NSFont.systemFont(ofSize: s * 0.54, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        func cw(_ n: Int) -> CGFloat { ("\(n)" as NSString).size(withAttributes: attrs).width }

        var groups: [(St, Int)] = []
        if barError     > 0 { groups.append((.error,     barError)) }
        if barAttention > 0 { groups.append((.attention, barAttention)) }
        if barWorking   > 0 { groups.append((.working,   barWorking)) }

        let lead: CGFloat = groups.isEmpty ? 0 : s * 0.16
        let interGap = s * 0.18, icoGap = s * 0.02
        var w = markW + lead
        for (i, g) in groups.enumerated() {
            if i > 0 { w += interGap }
            w += icoD + icoGap + cw(g.1)
        }

        let img = NSImage(size: NSSize(width: w, height: s))
        img.lockFocus()
        warpMark?.draw(in: NSRect(x: 0, y: (s - markH) / 2, width: markW, height: markH))
        var x = markW + lead
        for (i, g) in groups.enumerated() {
            if i > 0 { x += interGap }
            statusIcon(g.0, phase: phase, box: icoD).draw(in: NSRect(x: x, y: (s - icoD) / 2, width: icoD, height: icoD))
            x += icoD + icoGap
            let str = "\(g.1)" as NSString
            let sz = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: x, y: (s - sz.height) / 2), withAttributes: attrs)
            x += sz.width
        }
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        warpMark = loadImage("mark.svg", size: NSSize(width: 60, height: 48))

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refresh()
        let t = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        refreshTimer = t
    }

    // MARK: state

    struct Tab { let uuid, status, name, url, agent: String; let epoch: Int }

    func pidAlive(_ pid: Int) -> Bool {
        if kill(pid_t(pid), 0) == 0 { return true }
        return errno == EPERM   // exists but not ours (won't happen here) = still alive
    }

    func readTabs() -> [Tab] {
        guard let raw = try? String(contentsOfFile: stateFile, encoding: .utf8) else { return [] }
        var tabs: [Tab] = []
        for line in raw.split(separator: "\n") {
            let f = String(line).components(separatedBy: "\t")
            if f.count < 6 { continue }
            // col 8 = the agent's session pid (codex only); drop the row if gone.
            if f.count > 7, let pid = Int(f[7]), pid > 0, !pidAlive(pid) { continue }
            tabs.append(Tab(uuid: f[0], status: f[1], name: f[3], url: f[5],
                            agent: f.count > 6 ? f[6] : "claude", epoch: Int(f[2]) ?? 0))
        }
        tabs.sort { a, b in
            let ra = a.status == "working" ? 1 : 0
            let rb = b.status == "working" ? 1 : 0
            return ra != rb ? ra < rb : a.epoch > b.epoch
        }
        return tabs
    }

    func relTime(_ epoch: Int) -> String {
        let d = max(0, Int(Date().timeIntervalSince1970) - epoch)
        if d < 60 { return "\(d)s" }
        if d < 3600 { return "\(d / 60)m \(d % 60)s" }
        if d < 86400 { return "\(d / 3600)h \((d % 3600) / 60)m" }
        return "\(d / 86400)d"
    }

    // small per-agent mark (own simple glyphs): a spark for Claude, code-brackets for Codex
    // official per-agent mark (SVG): Codex tile / Claude spark, loaded + cached
    func agentGlyph(_ agent: String) -> NSImage {
        let file = (agent == "codex") ? "agent-codex.svg" : "agent-claude.svg"
        if let img = agentImages[file] { return img }
        let img = loadImage(file, size: NSSize(width: 28, height: 28))
            ?? NSImage(size: NSSize(width: 13, height: 13))
        agentImages[file] = img
        return img
    }

    func rowTitle(_ name: String, _ epoch: Int, _ agent: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let s = NSMutableAttributedString(
            string: name, attributes: [.foregroundColor: NSColor.labelColor, .font: font])
        s.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        let att = NSTextAttachment()
        att.image = agentGlyph(agent)
        att.bounds = NSRect(x: 0, y: font.descender, width: 13, height: 13)
        s.append(NSAttributedString(attachment: att))   // agent mark after the title
        s.append(NSAttributedString(
            string: "  ·  \(relTime(epoch))",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        return s
    }

    // MARK: menu-bar refresh

    func refresh() {
        let tabs = readTabs()
        barWorking   = tabs.filter { statusKind($0.status) == .working }.count
        barAttention = tabs.filter { statusKind($0.status) == .attention }.count
        barError     = tabs.filter { statusKind($0.status) == .error }.count
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeft
        button.title = ""                          // counts are drawn into the image
        button.toolTip = "warpwatch — \(barWorking) working, \(barAttention) your turn"
        // ALWAYS draw a frame here so the icon is never blank between timer ticks
        // (a missing image makes the status item look like it "disappeared").
        button.image = barComposite(phase: phase)
        if (barWorking + barAttention + barError) == 0 || !pulseEnabled {
            stopPulse()
        } else {
            startPulse()
        }
    }

    func startPulse() {
        if pulseTimer != nil { return }
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self, let b = self.statusItem.button else { return }
            self.phase += 0.14
            b.image = self.barComposite(phase: self.phase)
        }
        RunLoop.main.add(t, forMode: .common)
        pulseTimer = t
    }

    func stopPulse() { pulseTimer?.invalidate(); pulseTimer = nil }

    // MARK: dropdown

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        animItems.removeAll()
        let header = NSMenuItem(title: "Warp agents", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let tabs = readTabs()
        if tabs.isEmpty {
            let empty = NSMenuItem(title: "No active agents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for t in tabs {
                let item = NSMenuItem(title: t.name, action: #selector(openTab(_:)), keyEquivalent: "")
                item.attributedTitle = rowTitle(t.name, t.epoch, t.agent)
                item.target = self
                item.representedObject = t.url
                let kind = statusKind(t.status)
                item.image = statusIcon(kind, phase: menuPhase, box: 16)
                animItems.append((item, kind, t.name, t.epoch, t.agent))
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Warp", action: #selector(openWarp), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let quit = NSMenuItem(title: "Quit warpwatch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // Pulse the waiting-row dots while the menu is open. The timer runs in
    // .common mode so it keeps firing during menu tracking.
    func menuWillOpen(_ menu: NSMenu) {
        guard !animItems.isEmpty else { return }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.menuPhase += 0.10
            for a in self.animItems {
                a.item.image = self.statusIcon(a.kind, phase: self.menuPhase, box: 16)
                a.item.attributedTitle = self.rowTitle(a.name, a.epoch, a.agent)   // live time (ticking seconds)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        menuTimer = t
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTimer?.invalidate(); menuTimer = nil
        animItems.removeAll()
    }

    // MARK: actions

    @objc func openTab(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String, let url = URL(string: s) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openWarp() {
        let ws = NSWorkspace.shared
        if let u = ws.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Stable") {
            ws.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
        } else {
            let p = Process(); p.launchPath = "/usr/bin/open"; p.arguments = ["-a", "Warp"]
            try? p.run()
        }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = WarpwatchApp()
app.delegate = delegate

// Headless self-test: exercise the menu-render path for every row + agent.
if ProcessInfo.processInfo.environment["WARPWATCH_SELFTEST"] != nil {
    func say(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
    delegate.warpMark = delegate.loadImage("mark.svg", size: NSSize(width: 60, height: 48))
    let tabs = delegate.readTabs()
    say("selftest: \(tabs.count) tabs")
    for a in ["claude", "codex", "weird", ""] {
        _ = delegate.agentGlyph(a).tiffRepresentation
        say("  agentGlyph(\(a)) ok")
    }
    for t in tabs {
        _ = delegate.statusIcon(delegate.statusKind(t.status), phase: 1.3, box: 16).tiffRepresentation
        _ = delegate.rowTitle(t.name, t.epoch, t.agent).length
        say("  row [\(t.agent)] \(t.status) \(t.name) ok")
    }
    for k in [delegate.statusKind("working"), delegate.statusKind("input"), delegate.statusKind("review"), delegate.statusKind("error")] {
        _ = delegate.statusIcon(k, phase: 1.3, box: 18).tiffRepresentation
    }
    delegate.barAttention = 2; delegate.barWorking = 2; delegate.barError = 1
    _ = delegate.barComposite(phase: 1.3).tiffRepresentation
    say("selftest: OK")
    exit(0)
}

app.run()
