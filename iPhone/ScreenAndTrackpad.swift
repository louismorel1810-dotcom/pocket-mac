import AudioToolbox
import AVFoundation
import SwiftUI
import UIKit

/// Sons et vibrations, selon les réglages.
enum Feedback {
    private static func flag(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func key() {
        if flag(Pref.keySounds) { AudioServicesPlaySystemSound(1104) }
        if flag(Pref.haptics) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    }

    static func click() {
        if flag(Pref.haptics) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    }
}

// MARK: - Écran du Mac

/// Affiche l'écran du Mac. Toucher = cliquer à cet endroit, appui long = clic droit,
/// pincer = zoomer, glisser (une fois zoomé) = se déplacer, double toucher à deux doigts = dézoomer.
struct ScreenView: UIViewRepresentable {
    let session: MacSession
    let screen: ScreenInfo?

    func makeUIView(context: Context) -> ScreenUIView {
        ScreenUIView(session: session)
    }

    func updateUIView(_ view: ScreenUIView, context: Context) {
        if let screen {
            view.screenSize = CGSize(width: screen.width, height: screen.height)
        }
    }
}

final class ScreenUIView: UIView, UIGestureRecognizerDelegate {
    var screenSize = CGSize(width: 16, height: 10) {
        didSet { if screenSize != oldValue { setNeedsLayout() } }
    }

    private weak var session: MacSession?
    private let content = UIView()
    private var scale: CGFloat = 1
    private var offset = CGPoint.zero
    private var pinchStartScale: CGFloat = 1
    private var panStartOffset = CGPoint.zero

    init(session: MacSession) {
        self.session = session
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(content)
        content.layer.addSublayer(session.video.layer)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        let resetZoom = UITapGestureRecognizer(target: self, action: #selector(handleResetZoom))
        resetZoom.numberOfTouchesRequired = 2
        resetZoom.numberOfTapsRequired = 2
        [pinch, pan, tap, longPress, resetZoom].forEach(addGestureRecognizer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        content.transform = .identity
        content.frame = AVMakeRect(aspectRatio: screenSize, insideRect: bounds)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        session?.video.layer.frame = content.bounds
        CATransaction.commit()
        applyTransform()
    }

    private func applyTransform() {
        let maxX = content.bounds.width * (scale - 1) / 2
        let maxY = content.bounds.height * (scale - 1) / 2
        offset.x = min(max(offset.x, -maxX), maxX)
        offset.y = min(max(offset.y, -maxY), maxY)
        content.transform = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
    }

    /// Position touchée, en proportion de l'écran du Mac (0...1).
    private func normalized(_ g: UIGestureRecognizer) -> CGPoint {
        let p = g.location(in: content)
        return CGPoint(x: p.x / max(content.bounds.width, 1), y: p.y / max(content.bounds.height, 1))
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g is UIPanGestureRecognizer { return scale > 1.01 }
        return true
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { pinchStartScale = scale }
        scale = min(max(pinchStartScale * g.scale, 1), 5)
        applyTransform()
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        if g.state == .began { panStartOffset = offset }
        let t = g.translation(in: self)
        offset = CGPoint(x: panStartOffset.x + t.x, y: panStartOffset.y + t.y)
        applyTransform()
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let p = normalized(g)
        session?.moveTo(x: p.x, y: p.y)
        session?.click(0)
        Feedback.click()
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let p = normalized(g)
        session?.moveTo(x: p.x, y: p.y)
        session?.click(1)
        Feedback.click()
    }

    @objc private func handleResetZoom() {
        UIView.animate(withDuration: 0.25) {
            self.scale = 1
            self.offset = .zero
            self.applyTransform()
        }
    }
}

// MARK: - Trackpad

/// Trackpad façon MacBook :
/// 1 doigt = déplacer, toucher = clic, toucher à 2 doigts = clic droit, 2 doigts = défiler,
/// appui long puis glisser = glisser-déposer, balayage à 3 doigts = bureaux / Mission Control.
struct TrackpadView: UIViewRepresentable {
    let session: MacSession

    func makeUIView(context: Context) -> TrackpadUIView {
        TrackpadUIView(session: session)
    }

    func updateUIView(_ view: TrackpadUIView, context: Context) {}
}

final class TrackpadUIView: UIView {
    private weak var session: MacSession?
    private var lastDragPoint = CGPoint.zero

    init(session: MacSession) {
        self.session = session
        super.init(frame: .zero)
        isMultipleTouchEnabled = true

        let move = UIPanGestureRecognizer(target: self, action: #selector(handleMove(_:)))
        move.minimumNumberOfTouches = 1
        move.maximumNumberOfTouches = 1
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.maximumNumberOfTouches = 2
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        swipe.minimumNumberOfTouches = 3
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let rightTap = UITapGestureRecognizer(target: self, action: #selector(handleRightTap))
        rightTap.numberOfTouchesRequired = 2
        let drag = UILongPressGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        drag.minimumPressDuration = 0.3
        drag.allowableMovement = 8
        [move, scroll, swipe, tap, rightTap, drag].forEach(addGestureRecognizer)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var speed: CGFloat {
        CGFloat(UserDefaults.standard.object(forKey: Pref.trackpadSpeed) as? Double ?? 2.0)
    }

    /// Plus le doigt va vite, plus le pointeur accélère, comme sur un vrai trackpad.
    private func pointerDelta(_ g: UIPanGestureRecognizer) -> CGPoint {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        let v = g.velocity(in: self)
        let acceleration = 1 + min(hypot(v.x, v.y) / 1500, 2)
        return CGPoint(x: t.x * speed * acceleration, y: t.y * speed * acceleration)
    }

    @objc private func handleMove(_ g: UIPanGestureRecognizer) {
        let d = pointerDelta(g)
        session?.moveBy(dx: d.x, dy: d.y)
    }

    @objc private func handleScroll(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        g.setTranslation(.zero, in: self)
        let invert = UserDefaults.standard.bool(forKey: Pref.invertScroll) ? -1.0 : 1.0
        session?.scroll(dx: t.x * 2 * invert, dy: t.y * 2 * invert)
    }

    @objc private func handleSwipe(_ g: UIPanGestureRecognizer) {
        guard g.state == .ended else { return }
        let t = g.translation(in: self)
        if abs(t.x) > abs(t.y), abs(t.x) > 40 {
            session?.perform(t.x < 0 ? .desktopRight : .desktopLeft)
        } else if t.y < -40 {
            session?.perform(.missionControl)
        } else if t.y > 40 {
            session?.perform(.appExpose)
        } else {
            return
        }
        Feedback.click()
    }

    @objc private func handleTap() {
        session?.click(0)
        Feedback.click()
    }

    @objc private func handleRightTap() {
        session?.click(1)
        Feedback.click()
    }

    @objc private func handleDrag(_ g: UILongPressGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began:
            lastDragPoint = p
            session?.button(0, down: true)
            Feedback.click()
        case .changed:
            session?.moveBy(dx: (p.x - lastDragPoint.x) * speed, dy: (p.y - lastDragPoint.y) * speed)
            lastDragPoint = p
        default:
            session?.button(0, down: false)
        }
    }
}
