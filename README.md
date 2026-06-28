# warpwatch

**Know when a Claude Code agent finishes in [Warp](https://www.warp.dev/) — and jump straight to the exact tab it ran in.**

warpwatch is a tiny [Claude Code](https://docs.claude.com/en/docs/claude-code) plugin for macOS. When an agent finishes a turn or pauses to ask you something, it:

1. **plays a sound** (via `afplay`, so it works even with Do Not Disturb on);
2. **records the finish** to a small state file;
3. shows it in a **macOS menu-bar item** (via [SwiftBar](https://github.com/swiftbar/SwiftBar)) — click an entry to **focus the exact Warp tab** the agent is in, not "the last tab".

It also offers optional corner-notification, centre-screen-dialog, and auto-focus modes.

---

## Why

Running several agents across several Warp tabs, you step away to read something. An agent finishes — but a normal notification, when clicked, drops you on whatever tab happens to be active. warpwatch fixes that: every Warp tab exports a per-session deep link in `$WARP_FOCUS_URL` (`warp://session/<uuid>`). The hook runs *inside* the agent's tab, inherits that link, and records it — so clicking the menu-bar entry runs `open warp://session/<uuid>` and lands you on the **right** tab.

The menu-bar path is also **immune to Do Not Disturb, Focus, and per-app Alert-Style settings** — the things that quietly swallow normal banners.

> Requires **macOS** and **Warp**. Focusing falls back to plain "activate Warp" if `$WARP_FOCUS_URL` isn't present.

---

## Install

```bash
git clone https://github.com/gzaripov/warpwatch.git ~/.claude/warpwatch
~/.claude/warpwatch/install.sh
```

`install.sh` makes the scripts executable, creates the state dir, and prints the two steps below.

### 1. Hooks

Merge into `~/.claude/settings.json` (keep any existing `hooks`):

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/.claude/warpwatch/scripts/notify.sh\" done", "timeout": 10 } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command", "command": "\"$HOME/.claude/warpwatch/scripts/notify.sh\" input", "timeout": 10 } ] }
    ]
  }
}
```

`Stop` = the agent finished. `Notification` = it needs your input / a permission.

The folder is also a valid Claude Code plugin (`.claude-plugin/plugin.json` + `hooks/hooks.json`), so you can instead wire it through `/plugin` — but the settings.json route is the simplest for personal use.

### 2. Menu-bar item (SwiftBar)

```bash
brew install --cask swiftbar
defaults write com.ameba.SwiftBar PluginDirectory "$HOME/.claude/warpwatch/swiftbar"
open -a SwiftBar
```

A terminal glyph appears in the menu bar. Its dropdown lists recent finishes (newest first); click one to jump to that tab. The badge shows how many are pending; **Очистить список** clears them.

### 3. (optional) Clickable corner notifications

```bash
brew install terminal-notifier
```

With `WARPWATCH_MODE=notification`, the corner banner's click then opens the exact agent tab. Without terminal-notifier the banner still shows but its click can't target a tab (macOS gives no handler).

---

## Modes

Set `WARPWATCH_MODE` (e.g. in the `env` block of `settings.json`):

| Mode | What happens on finish |
|------|------------------------|
| `menubar` *(default)* | sound + record; the menu-bar item is the UI |
| `notification` | sound + corner banner (tab-aware click with terminal-notifier) |
| `dialog` | sound + persistent centre-screen overlay (immune to DND) with an "Open Warp" button |
| `focus` | sound + jump straight to the agent's tab |
| `both` | dialog + focus |
| `silent` | record only — no sound, no popup |

The menu-bar list is populated in **every** mode, so you always have the tab-aware jump list.

## Environment variables

| Var | Default | Meaning |
|-----|---------|---------|
| `WARPWATCH_MODE` | `menubar` | see table above |
| `WARPWATCH_ALWAYS` | `0` | `1` = act even when Warp is already frontmost |
| `WARPWATCH_SOUND_DONE` | `…/Hero.aiff` | sound for "finished" |
| `WARPWATCH_SOUND_INPUT` | `…/Glass.aiff` | sound for "needs input" |
| `WARPWATCH_DIALOG_GIVEUP` | `86400` | auto-dismiss the dialog after N seconds |
| `WARPWATCH_APP` | `Warp` | app to focus when no per-tab URL is available |
| `WARPWATCH_STATE` | `~/.claude/warpwatch/state` | where finishes are recorded |

By default warpwatch stays quiet while you're already looking at Warp (it compares the frontmost app's **bundle id** against Warp's — Warp Stable's *process* name is `stable`, so a name check would never match). Set `WARPWATCH_ALWAYS=1` to always fire.

---

## How it works

```
Claude Code (Stop / Notification hook)
        │  runs inside the agent's Warp tab
        ▼
scripts/notify.sh
   ├─ append: epoch ⇥ kind ⇥ $WARP_FOCUS_URL ⇥ cwd   →  state/finishes.tsv
   ├─ afplay <sound>            (bypasses Do Not Disturb)
   └─ optional: notification / dialog / focus
        ▼
swiftbar/warpwatch.5s.sh  reads finishes.tsv
   └─ menu-bar dropdown → click → open warp://session/<uuid>  → exact tab
```

## Files

```
warpwatch/
├── .claude-plugin/plugin.json   plugin manifest
├── hooks/hooks.json             plugin-style hooks (${CLAUDE_PLUGIN_ROOT})
├── scripts/
│   ├── notify.sh                the hook: record + sound + optional popup
│   ├── dialog.applescript       persistent, tab-aware centre dialog
│   └── menubar-clear.sh         clears the menu-bar inbox
├── swiftbar/warpwatch.5s.sh     SwiftBar menu-bar plugin
├── install.sh                   one-shot setup helper
└── README.md
```

## License

MIT © Grigory Zaripov
