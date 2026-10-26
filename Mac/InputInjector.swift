import AppKit
import ApplicationServices
import CoreGraphics

/// Rejoue sur le Mac les frappes, mouvements et clics envoyés par l'iPhone.
/// Nécessite l'autorisation « Accessibilité » dans Réglages Système.
final class InputInjector {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var pressedButtons: Set<UInt8> = []
    private var lastClickTime = Date.distantPast
    private var lastClickButton: UInt8 = 0
    private var clickCount = 0

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private var cursor: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    // MARK: - Souris

    func moveBy(dx: CGFloat, dy: CGFloat, display: CGDirectDisplayID) {
        var p = cursor
        p.x += dx
        p.y += dy
        postMove(to: clamp(p, display: display))
    }

    func moveTo(x: CGFloat, y: CGFloat, display: CGDirectDisplayID) {
        let b = CGDisplayBounds(display)
        postMove(to: clamp(CGPoint(x: b.minX + x * b.width, y: b.minY + y * b.height), display: display))
    }

    func button(_ button: UInt8, down: Bool) {
        let left = button == 0
        let type: CGEventType = left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        if down {
            let now = Date()
            if button == lastClickButton, now.timeIntervalSince(lastClickTime) < NSEvent.doubleClickInterval {
                clickCount += 1
            } else {
                clickCount = 1
            }
            lastClickTime = now
            lastClickButton = button
            pressedButtons.insert(button)
        } else {
            pressedButtons.remove(button)
        }
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: cursor,
                            mouseButton: left ? .left : .right)
        event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        event?.post(tap: .cghidEventTap)
    }

    func scroll(dx: CGFloat, dy: CGFloat) {
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                            wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    private func postMove(to point: CGPoint) {
        let type: CGEventType
        let button: CGMouseButton
        if pressedButtons.contains(0) {
            type = .leftMouseDragged
            button = .left
        } else if pressedButtons.contains(1) {
            type = .rightMouseDragged
            button = .right
        } else {
            type = .mouseMoved
            button = .left
        }
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)?
            .post(tap: .cghidEventTap)
    }

    private func clamp(_ p: CGPoint, display: CGDirectDisplayID) -> CGPoint {
        let b = CGDisplayBounds(display)
        return CGPoint(x: min(max(p.x, b.minX), b.maxX - 1), y: min(max(p.y, b.minY), b.maxY - 1))
    }

    // MARK: - Clavier

    func key(_ code: UInt16, down: Bool, flags: UInt64) {
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
        var f = CGEventFlags(rawValue: flags)
        if Self.arrowKeys.contains(code) {
            f.insert([.maskNumericPad, .maskSecondaryFn])
        }
        event?.flags = f
        event?.post(tap: .cghidEventTap)
    }

    private static let arrowKeys: Set<UInt16> = [123, 124, 125, 126]

    /// Touche avec Contrôle maintenu, comme le ferait un vrai clavier
    /// (nécessaire pour Mission Control et le changement de bureau).
    private func controlShortcut(_ code: UInt16) {
        let ctrl: CGKeyCode = 59
        if let down = CGEvent(keyboardEventSource: source, virtualKey: ctrl, keyDown: true) {
            down.flags = .maskControl
            down.post(tap: .cghidEventTap)
        }
        key(code, down: true, flags: CGEventFlags.maskControl.rawValue)
        key(code, down: false, flags: CGEventFlags.maskControl.rawValue)
        CGEvent(keyboardEventSource: source, virtualKey: ctrl, keyDown: false)?.post(tap: .cghidEventTap)
    }

    // MARK: - Actions

    func perform(_ action: MacAction) {
        switch action {
        case .missionControl: controlShortcut(126)
        case .appExpose: controlShortcut(125)
        case .desktopLeft: controlShortcut(123)
        case .desktopRight: controlShortcut(124)
        case .showDesktop:
            key(103, down: true, flags: 0)   // F11
            key(103, down: false, flags: 0)
        case .launchpad:
            let candidates = ["/System/Applications/Launchpad.app", "/System/Applications/Apps.app"]
            if let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        case .volumeUp: mediaKey(0)
        case .volumeDown: mediaKey(1)
        case .brightnessUp: mediaKey(2)
        case .brightnessDown: mediaKey(3)
        case .mute: mediaKey(7)
        case .playPause: mediaKey(16)
        case .nextTrack: mediaKey(17)
        case .previousTrack: mediaKey(18)
        }
    }

    /// Touches spéciales (son, luminosité, lecture) : codes NX_KEYTYPE_*.
    private func mediaKey(_ key: Int) {
        for down in [true, false] {
            let data1 = (key << 16) | ((down ? 0xA : 0xB) << 8)
            let event = NSEvent.otherEvent(with: .systemDefined,
                                           location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                                           timestamp: 0,
                                           windowNumber: 0,
                                           context: nil,
                                           subtype: 8,
                                           data1: data1,
                                           data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
