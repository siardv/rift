import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// the system paste control (fr-1) presented as a plain text action (m3.2):
/// `UIPasteControl` with the field surface as its background and the ink as
/// label color, so it merges with the field and sits level with the
/// neighbouring text actions. on device the SwiftUI `PasteButton` could not
/// be styled this way (it drew a grey block with a white label whatever its
/// tint), and a `.clear` background here renders as solid black, hence the
/// opaque field color. pasteboard access stays the system's: the control hands
/// item providers to its target, and nothing here reads UIPasteboard. the
/// label font and internal insets are the control's own, which is why the
/// row's text actions use `.body`; sizing is done on the uikit side
/// (TallPasteControl), not through SwiftUI's representable sizing api
struct PasteControl: UIViewRepresentable {
    let onPaste: @MainActor ([String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPaste: onPaste)
    }

    func makeUIView(context: Context) -> UIPasteControl {
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = .labelOnly
        configuration.cornerStyle = .fixed
        configuration.cornerRadius = Theme.fieldRadius
        configuration.baseBackgroundColor = Theme.fieldUIColor
        configuration.baseForegroundColor = Theme.inkUIColor
        let control = TallPasteControl(configuration: configuration)
        control.target = context.coordinator
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return control
    }

    func updateUIView(_ uiView: UIPasteControl, context: Context) {
        context.coordinator.onPaste = onPaste
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
            _ = provider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
                guard let ns = object as? NSString else { return }
                let text = ns as String
                Task { @MainActor in
                    self?.onPaste([text])
                }
            }
        }
    }
}

/// the paste control with a 44-point minimum height (nfr-5): the whole control
/// is the system's hit-testable area, so its own size meets the target
final class TallPasteControl: UIPasteControl {
    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width, height: max(size.height, 44))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let fitted = super.sizeThatFits(size)
        return CGSize(width: fitted.width, height: max(fitted.height, 44))
    }
}
