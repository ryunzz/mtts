import AppKit
import ApplicationServices
import os

/// What a head turn does. Each sends a keystroke to whatever app is in front.
enum GestureAction: String, CaseIterable, Identifiable, Sendable {
    case tabs = "Switch Tabs"
    case desktops = "Switch Desktops"
    case arrows = "Arrow Keys"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .tabs: "⌃⇥ / ⌃⇧⇥: next and previous tab in Safari, Chrome, Finder, VS Code…"
        case .desktops: "⌃→ / ⌃←: next and previous desktop (Space)"
        case .arrows: "→ / ←: next and previous slide in Keynote, PowerPoint, Preview…"
        }
    }

    func keystroke(for turn: HeadTurn) -> (key: CGKeyCode, flags: CGEventFlags) {
        let right = turn == .right
        switch self {
        case .tabs: return (48, right ? .maskControl : [.maskControl, .maskShift])  // Tab
        case .desktops: return (right ? 124 : 123, [.maskControl, .maskSecondaryFn])
        case .arrows: return (right ? 124 : 123, [.maskSecondaryFn])
        }
    }
}

/// Posts synthetic keystrokes and clicks. macOS only delivers them to other apps once mtts has
/// Accessibility access (System Settings › Privacy & Security › Accessibility).
enum ShortcutSender {
    private static let log = Logger(subsystem: AppInfo.subsystem, category: "gestures")

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to the Accessibility setting.
    static func requestAccess() {
        let key = "AXTrustedCheckOptionPrompt"  // kAXTrustedCheckOptionPrompt
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func send(_ action: GestureAction, for turn: HeadTurn) {
        let (key, flags) = action.keystroke(for: turn)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        log.info("Head turn \(turn.rawValue, privacy: .public) → \(action.rawValue, privacy: .public)")
    }

    /// A left click wherever the cursor is now.
    static func click() {
        let point = CGEvent(source: nil)?.location ?? .zero
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        log.info("Gesture click")
    }
}
