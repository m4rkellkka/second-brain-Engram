import AppKit
import SwiftUI

/// Multi-line text field where Return submits and Shift+Return adds a line.
///
/// A thin wrapper around `NSTextView`: SwiftUI's `TextEditor` offers no
/// reliable way to tell Return from Shift+Return, while the text view's
/// delegate sees every editing command (`insertNewline:`) before it runs.
struct ThoughtEditor: NSViewRepresentable {
  @Binding var text: String
  /// Change it to move keyboard focus into the editor.
  var focusToken: Int
  /// Also take focus whenever the window becomes key (the menu-bar panel).
  var focusWhenWindowActivates = false
  var onSubmit: () -> Void
  /// Esc; when nil, Esc does what the text view normally does.
  var onCancel: (() -> Void)? = nil
  var fontSize: CGFloat = 15
  /// Take focus as soon as the editor appears. Off for fields further down
  /// a page, where taking focus would scroll the page to them.
  var focusOnAppear = true

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = FocusingTextView(frame: .zero)
    textView.focusWhenWindowActivates = focusWhenWindowActivates
    textView.focusOnAppear = focusOnAppear
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.font =
      NSFont(name: "Geist-Regular", size: fontSize) ?? .systemFont(ofSize: fontSize)
    textView.textColor = NSColor(Theme.text)
    textView.insertionPointColor = NSColor(Theme.accent)
    textView.textContainerInset = NSSize(width: 0, height: 2)
    textView.textContainer?.lineFragmentPadding = 0
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainer?.widthTracksTextView = true
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.string = text

    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = scrollView.documentView as? NSTextView else { return }
    if textView.string != text { textView.string = text }
    if context.coordinator.focusToken != focusToken {
      context.coordinator.focusToken = focusToken
      DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: ThoughtEditor
    var focusToken: Int

    init(parent: ThoughtEditor) {
      self.parent = parent
      self.focusToken = parent.focusToken
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      if selector == #selector(NSResponder.cancelOperation(_:)), let onCancel = parent.onCancel {
        onCancel()
        return true
      }
      guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
      if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
        textView.insertNewlineIgnoringFieldEditor(nil)
      } else {
        parent.onSubmit()
      }
      return true
    }
  }
}

/// Takes focus when it lands in a window, and optionally each time that
/// window becomes key.
final class FocusingTextView: NSTextView {
  var focusWhenWindowActivates = false
  var focusOnAppear = true
  private var keyObserver: (any NSObjectProtocol)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
    keyObserver = nil
    guard let window else { return }
    if focusOnAppear { window.makeFirstResponder(self) }
    guard focusWhenWindowActivates else { return }
    keyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.window?.makeFirstResponder(self)
      }
    }
  }
}
