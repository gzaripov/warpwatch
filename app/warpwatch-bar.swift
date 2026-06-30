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
    var barWorking = 0
    var barWaiting = 0
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

    // menu-bar composite: Warp mark + a "working" group and an "awaiting" group
    // (working first), each an animated icon + count. Empty groups are omitted.
    //   working  -> a rotating arc (in progress)
    //   awaiting -> a ping ring + dot (your turn)
    func barComposite(working: Int, waiting: Int, phase: Double) -> NSImage {
        let s = thick
        let markH = s * 0.56, markW = markH * (268.0 / 214.0)
        let icoD = s * 0.80
        let font = NSFont.systemFont(ofSize: s * 0.50, weight: .semibold)
        let countAttrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        func cw(_ n: Int) -> CGFloat { ("\(n)" as NSString).size(withAttributes: countAttrs).width }

        var groups: [(waiting: Bool, color: NSColor, count: Int)] = []
        if working > 0 { groups.append((false, teal, working)) }
        if waiting > 0 { groups.append((true, attn, waiting)) }

        let lead: CGFloat = groups.isEmpty ? 0 : s * 0.24
        let interGap = s * 0.30, icoGap = s * 0.10
        var w = markW + lead
        for (i, g) in groups.enumerated() {
            if i > 0 { w += interGap }
            w += icoD + icoGap + cw(g.count)
        }

        let img = NSImage(size: NSSize(width: w, height: s))
        img.lockFocus()
        warpMark?.draw(in: NSRect(x: 0, y: (s - markH) / 2, width: markW, height: markH))
        var x = markW + lead
        for (i, g) in groups.enumerated() {
            if i > 0 { x += interGap }
            let cx = x + icoD / 2, cy = s / 2
            if g.waiting {
                let u = CGFloat(phase.truncatingRemainder(dividingBy: 2.6) / 2.6)
                g.color.withAlphaComponent((1 - u) * 0.5).setFill()
                fillOval(cx, cy, icoD * (0.30 + 0.18 * u))
                g.color.setFill(); fillOval(cx, cy, icoD * 0.28)
            } else {
                drawArc(cx, cy, r: icoD * 0.37, width: icoD * 0.18, start: phase, sweep: .pi * 1.35, color: g.color)
            }
            x += icoD + icoGap
            let str = "\(g.count)" as NSString
            let sz = str.size(withAttributes: countAttrs)
            str.draw(at: NSPoint(x: x, y: (s - sz.height) / 2), withAttributes: countAttrs)
            x += sz.width
        }
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
            fillOval(c, c, s * (0.28 + 0.17 * u))
            color.setFill()
            fillOval(c, c, s * 0.25)                        // steady bright core (a touch smaller)
        } else {
            // work in progress -> the same rotating-arc spinner as the menu bar
            drawArc(c, c, r: s * 0.30, width: s * 0.13, start: phase, sweep: .pi * 1.35, color: color)
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
        button.title = ""                          // counts are drawn inside the composite
        button.toolTip = "warpwatch — \(working) working, \(waiting) awaiting"
        barWorking = working; barWaiting = waiting
        if (working + waiting) == 0 || !pulseEnabled {
            stopPulse()
            button.image = barComposite(working: working, waiting: waiting, phase: 0)
        } else {
            startPulse()
        }
    }

    func startPulse() {
        if pulseTimer != nil { return }
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self, let b = self.statusItem.button else { return }
            self.phase += 0.14
            b.image = self.barComposite(working: self.barWorking, waiting: self.barWaiting, phase: self.phase)
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
            self.menuPhase += 0.10
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
