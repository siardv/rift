import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// native clipboard permission and item-provider delivery, with a restrained
/// charcoal action treatment. feedback observes the system highlight state
struct PasteControl: UIViewRepresentable {
    let onPaste: @MainActor ([String]) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaste: onPaste)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .iconAndLabel
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = Theme.fieldRadius
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        configuration.baseBackgroundColor = Theme.actionUIColor.resolvedColor(with: traits)
        configuration.baseForegroundColor = Theme.actionLabelUIColor.resolvedColor(with: traits)
        let control = TallPasteControl(configuration: configuration)
        control.reduceMotion = reduceMotion
        control.target = context.coordinator
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
        (uiView as? TallPasteControl)?.reduceMotion = reduceMotion
    }

    /// the paste target: a responder that accepts plain text and forwards the
    /// first string on the main actor
    final class Coordinator: UIResponder {
        var onPaste: @MainActor ([String]) -> Void

        init(onPaste: @escaping @MainActor ([String]) -> Void) {
            self.onPaste = onPaste
            super.init()
            pasteConfiguration = UIPasteConfiguration(forAccepting: NSString.self)
        }

        override func paste(itemProviders: [NSItemProvider]) {
            guard let provider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
                return
            }
            // an accepted paste survives appearance-driven control replacement
            let deliver = onPaste
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let ns = object as? NSString else { return }
                let text = ns as String
                Task { @MainActor in
                    deliver([text])
                }
            }
        }
    }
}

/// the paste control with a 44-point minimum height (nfr-5): the whole control
/// is the system's hit-testable area, so its own size meets the target
final class TallPasteControl: UIPasteControl {
    var reduceMotion = false {
        didSet { if reduceMotion != oldValue { updateFeedback() } }
    }

    override var isHighlighted: Bool {
        didSet { updateFeedback() }
    }

    override var isEnabled: Bool {
        didSet { updateFeedback() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            layer.removeAllAnimations()
            transform = .identity
            alpha = 1
        }
    }

    private func updateFeedback() {
        let pressed = isHighlighted && isEnabled
        let presentation = {
            self.alpha = pressed ? 0.84 : 1
        }
        if reduceMotion || window == nil {
            layer.removeAllAnimations()
            presentation()
        } else {
            UIView.animate(withDuration: 0.12, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction],
                           animations: presentation)
        }
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width, height: max(size.height, 44))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitted = super.sizeThatFits(size)
        return CGSize(width: fitted.width, height: max(fitted.height, 44))
    }
}
