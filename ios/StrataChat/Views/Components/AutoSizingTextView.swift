import SwiftUI
import UIKit

/// UITextView only offers Paste when the clipboard holds text, so a copied screenshot, PDF or
/// document never reached the composer except through the plus menu. The paste action is
/// claimed here and forwarded to the composer, which knows how to attach media and read files.
private final class ComposerTextView: UITextView {
    var onNonTextPaste: (() -> Void)?
    
    // A copied image or file lands in the pasteboard as an image or a file URL, never as a
    // string, so the text view hands those pastes to the composer instead of eating them.
    private static func holdsAttachment(_ pasteboard: UIPasteboard) -> Bool {
        pasteboard.hasImages || (pasteboard.urls?.isEmpty == false)
    }
    
    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general
        if !pasteboard.hasStrings && ComposerTextView.holdsAttachment(pasteboard) {
            onNonTextPaste?()
            return
        }
        super.paste(sender)
    }
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let pasteboard = UIPasteboard.general
        if action == #selector(paste(_:)) && !pasteboard.hasStrings {
            return ComposerTextView.holdsAttachment(pasteboard)
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

public struct AutoSizingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var calculatedHeight: CGFloat
    var placeholder: String
    var minHeight: CGFloat = 34
    var maxHeight: CGFloat = 110
    
    public init(
        text: Binding<String>,
        calculatedHeight: Binding<CGFloat>,
        placeholder: String,
        minHeight: CGFloat = 34,
        maxHeight: CGFloat = 110
    ) {
        self._text = text
        self._calculatedHeight = calculatedHeight
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
    }
    
    public func makeUIView(context: Context) -> UITextView {
        let textView = ComposerTextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.onNonTextPaste = {
            NotificationCenter.default.post(name: NSNotification.Name("ComposerPasteRequested"), object: nil)
        }
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.textColor = .white
        textView.tintColor = UIColor(red: 0.49, green: 0.36, blue: 1.0, alpha: 1.0)
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 4, bottom: 7, right: 4)
        textView.textContainer.lineFragmentPadding = 0
        textView.keyboardAppearance = .dark
        textView.returnKeyType = .default
        
        // Critical wrapping & horizontal constraints
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        
        // Placeholder label
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = UIFont.systemFont(ofSize: 16)
        placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.35)
        placeholderLabel.tag = 999
        placeholderLabel.isUserInteractionEnabled = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        textView.addSubview(placeholderLabel)
        
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 4),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -4),
            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
        ])
        
        placeholderLabel.isHidden = !text.isEmpty
        
        return textView
    }
    
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.bounds.width
        let effectiveWidth = width > 0 ? width : (UIScreen.main.bounds.width - 120)
        if text.isEmpty {
            return CGSize(width: width, height: minHeight)
        }
        let fitting = uiView.sizeThatFits(CGSize(width: effectiveWidth, height: .greatestFiniteMagnitude))
        let targetHeight = min(max(minHeight, fitting.height), maxHeight)
        return CGSize(width: width, height: targetHeight)
    }
    
    public func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        
        if let placeholderLabel = uiView.viewWithTag(999) as? UILabel {
            placeholderLabel.text = placeholder
            placeholderLabel.isHidden = !text.isEmpty
        }
        
        DispatchQueue.main.async {
            if self.text.isEmpty {
                uiView.isScrollEnabled = false
                if self.calculatedHeight != self.minHeight {
                    self.calculatedHeight = self.minHeight
                }
            } else {
                let currentWidth = uiView.bounds.width > 0 ? uiView.bounds.width : (UIScreen.main.bounds.width - 120)
                let fittingSize = uiView.sizeThatFits(CGSize(width: currentWidth, height: .greatestFiniteMagnitude))
                let newHeight = min(max(self.minHeight, fittingSize.height), self.maxHeight)
                uiView.isScrollEnabled = fittingSize.height > self.maxHeight
                if abs(self.calculatedHeight - newHeight) > 1 {
                    self.calculatedHeight = newHeight
                }
            }
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoSizingTextView
        weak var textView: UITextView?
        
        init(_ parent: AutoSizingTextView) {
            self.parent = parent
            super.init()
            // A tap on the chat area asks every composer text view to give up the keyboard, and this
            // is the one place that can resign the real UITextView.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleComposerBlur),
                name: NSNotification.Name("ComposerDidBlur"),
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func handleComposerBlur() {
            textView?.resignFirstResponder()
        }
        
        public func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            
            if let placeholderLabel = textView.viewWithTag(999) as? UILabel {
                placeholderLabel.isHidden = !textView.text.isEmpty
            }
            
            if textView.text.isEmpty {
                textView.isScrollEnabled = false
                if parent.calculatedHeight != parent.minHeight {
                    parent.calculatedHeight = parent.minHeight
                }
            } else {
                let currentWidth = textView.bounds.width > 0 ? textView.bounds.width : (UIScreen.main.bounds.width - 120)
                let fittingSize = textView.sizeThatFits(CGSize(width: currentWidth, height: .greatestFiniteMagnitude))
                let newHeight = min(max(parent.minHeight, fittingSize.height), parent.maxHeight)
                textView.isScrollEnabled = fittingSize.height > parent.maxHeight
                if abs(parent.calculatedHeight - newHeight) > 1 {
                    parent.calculatedHeight = newHeight
                }
            }
        }
        
        public func textViewDidBeginEditing(_ textView: UITextView) {
            NotificationCenter.default.post(name: NSNotification.Name("ComposerDidFocus"), object: nil)
        }
    }
}
