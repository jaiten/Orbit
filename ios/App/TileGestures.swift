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

/// Lifts a tile after a still hold, then follows the finger. Points are in window coordinates,
/// the same space as SwiftUI's `.global` frames used for the drop areas.
@available(iOS 18.0, *)
struct HoldToDrag: UIGestureRecognizerRepresentable {
    var began: () -> Void
    var moved: (_ start: CGPoint, _ location: CGPoint) -> Void
    /// The drop point, or nil when the hold was cancelled.
    var ended: (CGPoint?) -> Void
    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let hold = UILongPressGestureRecognizer()
        hold.minimumPressDuration = HomeDrag.holdDuration
        hold.allowableMovement = HomeDrag.holdTolerance
        return hold
    }
    func handleUIGestureRecognizerAction(_ hold: UILongPressGestureRecognizer, context: Context) {
        let point = hold.location(in: nil)
        switch hold.state {
        case .began:
            context.coordinator.start = point
            began()
            moved(point, point)
        case .changed: moved(context.coordinator.start, point)
        case .ended: ended(point)
        case .cancelled, .failed: ended(nil)
        default: break
        }
    }
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    final class Coordinator { var start: CGPoint = .zero }
}
