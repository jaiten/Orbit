import UIKit
import SwiftUI

/// Scrollable editing controls with a pinned Done button; the background stays opaque above the keyboard.
final class NoteKeyboardBar: UIView {
    init(target: AnyObject, actions: [(String, String, Selector)], done: Selector) {
        super.init(frame: CGRect(x: 0, y: 0, width: 390, height: 48))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = UIColor { traits in UIColor(DayTheme.canvas(traits.userInterfaceStyle == .dark ? .dark : .light)) }
        isOpaque = true
        let scroll = UIScrollView(); scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        let stack = UIStackView(); stack.axis = .horizontal; stack.spacing = 4
        for (name, symbol, selector) in actions {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.tintColor = .label; button.accessibilityLabel = name
            button.addTarget(target, action: selector, for: .touchUpInside)
            button.widthAnchor.constraint(equalToConstant: 44).isActive = true
            button.heightAnchor.constraint(equalToConstant: 44).isActive = true
            stack.addArrangedSubview(button)
        }
        let finish = UIButton(type: .system); finish.setTitle("Done", for: .normal)
        finish.tintColor = .label; finish.titleLabel?.font = .preferredFont(forTextStyle: .body)
        finish.addTarget(target, action: done, for: .touchUpInside)
        finish.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [scroll, stack, finish] { view.translatesAutoresizingMaskIntoConstraints = false }
        addSubview(scroll); scroll.addSubview(stack); addSubview(finish)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            scroll.trailingAnchor.constraint(equalTo: finish.leadingAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            finish.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
            finish.centerYAnchor.constraint(equalTo: centerYAnchor),
            finish.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            finish.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 48) }
}
