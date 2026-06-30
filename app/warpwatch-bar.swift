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

    let attn = NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1)     // amber (waiting)
    let teal  = NSColor(red: 0.055, green: 0.592, blue: 0.651, alpha: 1)
    let slate = NSColor(white: 0.62, alpha: 1)

    var warpMark: NSImage!

    var refreshTimer: Timer?
    var pulseTimer: Timer?
    var phase: Double = 0
    var barState = "idle"
    var menuTimer: Timer?
    var menuPhase: Double = 0
    var animItems: [(item: NSMenuItem, color: NSColor, waiting: Bool, name: String, epoch: Int)] = []   // rows animated while the menu is open
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
        state == "waiting" ? attn : (state == "working" ? teal : slate)
    }

    func fillOval(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    }

    // Menu-bar icon: Warp mark on the left, status dot on the right. While
    // waiting the dot is a bright core with a breathing translucent halo.
    func barIcon(state: String, phase: Double) -> NSImage {
        let s = thick                              // compact, square footprint (like claude-status-bar)
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        // Warp mark, centred
        let mh = s * 0.58
        let mw = mh * (268.0 / 214.0)
        if let mark = warpMark {
            mark.draw(in: NSRect(x: (s - mw) / 2, y: (s - mh) / 2, width: mw, height: mh))
        }
        // small status dot, bottom-right corner badge.
        //   working -> a calm size pulse;  waiting (answer needed) -> a blink.
        let col = dotColor(state)
        let dx = s * 0.70, dy = s * 0.30
        var r = s * 0.16
        var a: CGFloat = 1.0
        if state == "waiting" {
            a = 0.30 + 0.70 * CGFloat((cos(phase * 1.7) + 1) / 2)   // blink (alpha), no expansion → no clip
        } else if state == "working" {
            r *= 0.85 + 0.22 * CGFloat((cos(phase) + 1) / 2)        // gentle size pulse
        }
        NSColor(white: 0.0, alpha: 0.5 * a).setFill()              // thin dark ring so the dot reads on the mark
        fillOval(dx, dy, r + 1.2)
        col.withAlphaComponent(a).setFill()
        fillOval(dx, dy, r)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // A dropdown row dot: a bright, high-contrast core with an optional
    // breathing halo (so it stands out on the grey menu background).
    func dotImage(_ color: NSColor, phase: Double, waiting: Bool) -> NSImage {
        let s: CGFloat = 18                                // headroom so the ring never clips the bounds
        let img = NSImage(size: NSSize(width: s, height: s))
        img.lockFocus()
        let c = s / 2
        if waiting {
            // answer needed -> a "ping": a ring emanates from the dot and fades,
            // grabbing attention. Kept inside the bounds (max 8.5 < c = 9).
            let u = CGFloat(phase.truncatingRemainder(dividingBy: 2.6) / 2.6)   // 0 → 1 ripple
            NSColor.white.withAlphaComponent((1 - u) * 0.55).setFill()
            fillOval(c, c, s * (0.30 + 0.17 * u))
            color.setFill()
            fillOval(c, c, s * 0.30)                        // steady bright core
        } else {
            // work in progress -> a calm breathing glow
            let t = CGFloat((cos(phase) + 1) / 2)
            NSColor.white.withAlphaComponent(0.12 + 0.24 * t).setFill()
            fillOval(c, c, s * (0.32 + 0.07 * t))
            color.setFill()
            fillOval(c, c, s * (0.27 + 0.02 * t))
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
        if d < 3600 { return "\(d / 60)m \(d % 60)s" }
        if d < 86400 { return "\(d / 3600)h \((d % 3600) / 60)m" }
        return "\(d / 86400)d"
    }

    func rowTitle(_ name: String, _ epoch: Int) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let s = NSMutableAttributedString(
            string: name, attributes: [.foregroundColor: NSColor.labelColor, .font: font])
        s.append(NSAttributedString(
            string: "   ·  \(relTime(epoch))",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        return s
    }

    // MARK: menu-bar refresh

    func refresh() {
        let tabs = readTabs()
        let waiting = tabs.filter { $0.status != "working" }.count
        let working = tabs.count - waiting
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeft
        button.toolTip = "warpwatch — \(waiting) waiting, \(working) working"
        button.title = waiting > 0 ? " \(waiting)" : ""
        barState = waiting > 0 ? "waiting" : (working > 0 ? "working" : "idle")
        if barState == "idle" || !pulseEnabled {
            stopPulse()
            button.image = barIcon(state: barState, phase: 0)
        } else {
            startPulse()   // animates barState (working = pulse, waiting = blink)
        }
    }

    func startPulse() {
        if pulseTimer != nil { return }
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self, let b = self.statusItem.button else { return }
            self.phase += 0.16
            b.image = self.barIcon(state: self.barState, phase: self.phase)
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
                item.attributedTitle = rowTitle(t.name, t.epoch)
                item.target = self
                item.representedObject = t.url
                let waiting = t.status != "working"
                let color = waiting ? attn : teal
                item.image = dotImage(color, phase: menuPhase, waiting: waiting)
                animItems.append((item, color, waiting, t.name, t.epoch))
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
                a.item.image = self.dotImage(a.color, phase: self.menuPhase, waiting: a.waiting)
                a.item.attributedTitle = self.rowTitle(a.name, a.epoch)   // live time (ticking seconds)
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
