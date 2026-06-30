// warpwatch-bar — a tiny native macOS menu-bar app for warpwatch.
//
// Reads ~/.claude/warpwatch/state/tabs.tsv and shows, in the menu bar, the
// Warp logo mark followed by a status dot: grey=idle, teal=working, and an
// amber dot that PULSES (a bright core with a breathing halo) while a tab is
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

    let amber = NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1)
    let teal  = NSColor(red: 0.055, green: 0.592, blue: 0.651, alpha: 1)
    let slate = NSColor(white: 0.62, alpha: 1)

    var warpMark: NSImage!

    var refreshTimer: Timer?
    var pulseTimer: Timer?
    var phase: Double = 0
    var menuTimer: Timer?
    var menuPhase: Double = 0
    var animItems: [(item: NSMenuItem, color: NSColor, strong: Bool)] = []   // rows to pulse while the menu is open
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

    func dotColor(_ state: String) -> NSColor {
        state == "waiting" ? amber : (state == "working" ? teal : slate)
    }

    func fillOval(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    }

    // Menu-bar icon: Warp mark on the left, status dot on the right. While
    // waiting the dot is a bright core with a breathing translucent halo.
    func barIcon(state: String, halo: Bool) -> NSImage {
        let h = thick
        let markH = h * 0.60
        let markW = markH * (268.0 / 214.0)
        let gap = h * 0.18
        let dotZone = h * 0.95
        let w = markW + gap + dotZone
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        if let mark = warpMark {
            mark.draw(in: NSRect(x: 0, y: (h - markH) / 2, width: markW, height: markH))
        }
        let cx = markW + gap + dotZone / 2
        let cy = h / 2
        let col = dotColor(state)
        if halo {
            let t = CGFloat((cos(phase) + 1) / 2)          // 1 → 0 → 1
            col.withAlphaComponent(0.10 + 0.46 * t).setFill()
            fillOval(cx, cy, h * (0.30 + 0.16 * (1 - t)))   // grows as it fades
        }
        col.setFill()
        fillOval(cx, cy, h * 0.22)                          // bright core
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // A dropdown row dot: a bright, high-contrast core with an optional
    // breathing halo (so it stands out on the grey menu background).
    func dotImage(_ color: NSColor, halo: Bool, phase: Double, strong: Bool) -> NSImage {
        let s: CGFloat = 16
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        let c = s / 2
        let t = CGFloat((cos(phase) + 1) / 2)              // 0 → 1 → 0
        if halo {
            let amp: CGFloat = strong ? 1.0 : 0.55         // waiting pulses harder than working
            color.withAlphaComponent((0.22 + 0.42 * t) * amp).setFill()
            fillOval(c, c, s * (0.40 + 0.18 * t))          // breathing ring, always wider than the core
        }
        color.setFill()
        fillOval(c, c, s * (0.30 + 0.05 * t))              // bright core, slight breathe
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

    struct Tab { let uuid, status, name, url: String; let epoch: Int }

    func readTabs() -> [Tab] {
        guard let raw = try? String(contentsOfFile: stateFile, encoding: .utf8) else { return [] }
        var tabs: [Tab] = []
        for line in raw.split(separator: "\n") {
            let f = String(line).components(separatedBy: "\t")
            if f.count < 6 { continue }
            tabs.append(Tab(uuid: f[0], status: f[1], name: f[3], url: f[5], epoch: Int(f[2]) ?? 0))
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
        if d < 3600 { return "\(d / 60)m" }
        if d < 86400 { return "\(d / 3600)h" }
        return "\(d / 86400)d"
    }

    // MARK: menu-bar refresh

    func refresh() {
        let tabs = readTabs()
        let waiting = tabs.filter { $0.status != "working" }.count
        let working = tabs.count - waiting
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeft
        button.toolTip = "warpwatch — \(waiting) waiting, \(working) working"
        if waiting > 0 {
            button.title = " \(waiting)"
            if pulseEnabled { startPulse() }
            else { stopPulse(); button.image = barIcon(state: "waiting", halo: false) }
        } else {
            stopPulse()
            button.title = ""
            button.image = barIcon(state: working > 0 ? "working" : "idle", halo: false)
        }
    }

    func startPulse() {
        if pulseTimer != nil { return }
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self, let b = self.statusItem.button else { return }
            self.phase += 0.16
            b.image = self.barIcon(state: "waiting", halo: true)
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
            let font = NSFont.menuFont(ofSize: 0)
            for t in tabs {
                let s = NSMutableAttributedString(
                    string: t.name,
                    attributes: [.foregroundColor: NSColor.labelColor, .font: font])
                s.append(NSAttributedString(
                    string: "   ·  \(relTime(t.epoch))",
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
                let item = NSMenuItem(title: t.name, action: #selector(openTab(_:)), keyEquivalent: "")
                item.attributedTitle = s
                item.target = self
                item.representedObject = t.url
                let waiting = t.status != "working"
                let color = waiting ? amber : teal
                item.image = dotImage(color, halo: true, phase: menuPhase, strong: waiting)
                item.toolTip = waiting ? "Agent is waiting for your input" : "Agent is working"
                animItems.append((item, color, waiting))
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
            self.menuPhase += 0.18
            for a in self.animItems {
                a.item.image = self.dotImage(a.color, halo: true, phase: self.menuPhase, strong: a.strong)
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
app.run()
