// warpwatch-bar — a tiny native macOS menu-bar app for warpwatch.
//
// Reads ~/.claude/warpwatch/state/tabs.tsv, shows the Warp logo in the menu
// bar (teal=working, amber=waiting), gently PULSES while a tab is waiting,
// and builds a dropdown of tabs — click one to jump to that exact Warp tab
// via its warp://session deep link. No SwiftBar, no third-party host.
//
// Build:  swiftc warpwatch-bar.swift -o warpwatch-bar
//
// Env: WARPWATCH_HOME (default ~/.claude/warpwatch), WARPWATCH_STATE,
//      WARPWATCH_PULSE=0 to disable the animation.

import Cocoa

final class WarpwatchApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let root: String
    let stateFile: String
    let iconsDir: String
    let pulseEnabled: Bool

    var icnIdle: NSImage!, icnWorking: NSImage!, icnWaiting: NSImage!
    var dotWorking: NSImage!, dotWaiting: NSImage!

    var refreshTimer: Timer?
    var pulseTimer: Timer?
    var pulsePhase: Double = 0

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

    func loadIcon(_ file: String, _ size: CGFloat, fallback: NSColor) -> NSImage {
        if let img = NSImage(contentsOfFile: "\(iconsDir)/\(file)") {
            img.size = NSSize(width: size, height: size)
            img.isTemplate = false
            return img
        }
        return circle(fallback, size)
    }

    func circle(_ color: NSColor, _ size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: size - 3, height: size - 3)).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: lifecycle

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let teal = NSColor(red: 0.055, green: 0.592, blue: 0.651, alpha: 1)
        let amber = NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1)
        let slate = NSColor(white: 0.55, alpha: 1)
        icnIdle = loadIcon("idle.svg", 18, fallback: slate)
        icnWorking = loadIcon("working.svg", 18, fallback: teal)
        icnWaiting = loadIcon("waiting.svg", 18, fallback: amber)
        dotWorking = loadIcon("row-working.svg", 11, fallback: teal)
        dotWaiting = loadIcon("row-waiting.svg", 11, fallback: amber)

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
        // waiting (non-working) first, then by most-recent
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

    // MARK: menu-bar icon

    func refresh() {
        let tabs = readTabs()
        let waiting = tabs.filter { $0.status != "working" }.count
        let working = tabs.count - waiting
        guard let button = statusItem.button else { return }
        if waiting > 0 {
            button.image = icnWaiting; button.title = " \(waiting)"
        } else if working > 0 {
            button.image = icnWorking; button.title = ""
        } else {
            button.image = icnIdle; button.title = ""
        }
        button.imagePosition = .imageLeft
        button.toolTip = "warpwatch — \(waiting) waiting, \(working) working"
        if waiting > 0 && pulseEnabled { startPulse() } else { stopPulse() }
    }

    func startPulse() {
        if pulseTimer != nil { return }
        let t = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self, let b = self.statusItem.button else { return }
            self.pulsePhase += 0.04
            // smooth breathe between 0.4 and 1.0, ~1.3s period
            b.alphaValue = 0.7 + 0.3 * cos(self.pulsePhase * 2 * Double.pi / 1.3)
        }
        RunLoop.main.add(t, forMode: .common)
        pulseTimer = t
    }

    func stopPulse() {
        pulseTimer?.invalidate(); pulseTimer = nil
        statusItem.button?.alphaValue = 1.0
    }

    // MARK: dropdown (rebuilt each time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: "Warp agents", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let tabs = readTabs()
        if tabs.isEmpty {
            let empty = NSMenuItem(title: "No active agents", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let nameFont = NSFont.menuFont(ofSize: 0)
            for t in tabs {
                let s = NSMutableAttributedString(
                    string: t.name,
                    attributes: [.foregroundColor: NSColor.labelColor, .font: nameFont])
                s.append(NSAttributedString(
                    string: "   ·  \(relTime(t.epoch))",
                    attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: nameFont]))
                let item = NSMenuItem(title: t.name, action: #selector(openTab(_:)), keyEquivalent: "")
                item.attributedTitle = s
                item.target = self
                item.representedObject = t.url
                item.image = (t.status == "working") ? dotWorking : dotWaiting
                item.toolTip = (t.status == "working") ? "Agent is working" : "Agent is waiting for your input"
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
