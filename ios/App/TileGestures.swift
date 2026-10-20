import SwiftUI
import UIKit

// SwiftUI drag gestures on tiles inside a ScrollView keep hold of vertical drags on iOS 18 and later,
// so the page would not scroll when a finger started on a tile. These UIKit recognizers decide at the
// start of a touch instead: the swipe begins only for sideways movement, and the hold begins only once
// the finger has stayed still. Every other touch belongs to the scroll view.

/// Reveals Delete. Refuses to begin unless the finger is moving mostly sideways.
@available(iOS 18.0, *)
struct SidewaysPan: UIGestureRecognizerRepresentable {
    var changed: (CGFloat) -> Void
    var ended: (CGFloat) -> Void
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }
    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let x = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: changed(x)
        case .ended, .cancelled, .failed: ended(x)
        default: break
        }
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.4
        }
    }
}

/// Lifts a Today tile after a still hold, then follows the finger. It is one UIKit recognizer on the
/// page's scroll view rather than a gesture on each tile, so the tiles' own buttons and swipe can't
/// hold it up, and any movement before the hold completes simply scrolls the page.
/// Place it in the background of the scroll view's content.
struct TileHoldInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView { InstallerView() }
    func updateUIView(_ view: InstallerView, context: Context) {}
    static func dismantleUIView(_ view: InstallerView, coordinator: ()) { view.uninstall() }

    /// Only a hold that starts on a tile; holding anywhere else does nothing. (A separate object,
    /// because UIView has its own `gestureRecognizerShouldBegin(_:)`.)
    final class OnTile: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            HomeDrag.shared.tile(at: recognizer.location(in: nil)) != nil
        }
    }

    final class InstallerView: UIView {
        private let onTile = OnTile()
        private var hold: UILongPressGestureRecognizer?
        private weak var host: UIScrollView?
        private var start: CGPoint = .zero
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, hold == nil else { return }
            var view = superview
            while let current = view, !(current is UIScrollView) { view = current.superview }
            guard let scroll = view as? UIScrollView else { return }
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(handle(_:)))
            hold.minimumPressDuration = HomeDrag.holdDuration
            hold.allowableMovement = HomeDrag.holdTolerance
            hold.delegate = onTile
            scroll.addGestureRecognizer(hold)
            self.hold = hold; host = scroll
        }
        func uninstall() {
            if let hold { host?.removeGestureRecognizer(hold) }
            hold = nil
        }
        @objc private func handle(_ hold: UILongPressGestureRecognizer) {
            // Window coordinates, the same space as the SwiftUI `.global` frames HomeDrag keeps.
            let point = hold.location(in: nil), drag = HomeDrag.shared
            let animation: Animation? = UIAccessibility.isReduceMotionEnabled ? nil : .spring(response: 0.3, dampingFraction: 0.85)
            switch hold.state {
            case .began:
                guard let id = drag.tile(at: point) else { return }
                start = point
                drag.lift(id)
                drag.update(start: point, location: point)
            case .changed: if drag.item != nil { drag.update(start: start, location: point) }
            case .ended: withAnimation(animation) { drag.finish(at: point) }
            case .cancelled, .failed: withAnimation(animation) { drag.reset() }
            default: break
            }
        }
    }
}
