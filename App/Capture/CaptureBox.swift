import SwiftUI

/// The capture field with its Save button, used in the window and the menu bar.
struct CaptureBox: View {
  @Environment(AppModel.self) private var model
  var editorHeight: CGFloat = 64
  var focusWhenWindowActivates = false
  /// On Today the field is the main thing on the page, so it gets an
  /// accent border.
  var prominent = false

  @State private var text = ""
  @State private var error: String?
  @State private var justSaved = false

  private var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack(alignment: .topLeading) {
        if text.isEmpty {
          Text("What's on your mind?")
            .font(.geist(15))
            .foregroundStyle(Theme.textSubtle)
            .padding(.top, 2)
            .allowsHitTesting(false)
        }
        ThoughtEditor(
          text: $text,
          focusToken: model.captureFocusToken,
          focusWhenWindowActivates: focusWhenWindowActivates,
          onSubmit: save
        )
        .accessibilityLabel("New thought")
      }
      .frame(height: editorHeight)

      HStack(spacing: 10) {
        if let error {
          Text(error).font(.geist(12)).foregroundStyle(Theme.danger)
        } else if justSaved {
          Label("Saved to Inbox", systemImage: "checkmark")
            .font(.geist(12))
            .foregroundStyle(Theme.textMuted)
        } else {
          Text("↵ save   ⇧↵ new line")
            .font(.geistMono(11))
            .foregroundStyle(Theme.textSubtle)
        }
        Spacer()
        Button("Save", action: save)
          .buttonStyle(AccentButtonStyle(height: 30))
          .disabled(isEmpty)
      }
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .glassPanel(border: prominent ? Theme.accent.opacity(0.28) : Theme.borderStrong.opacity(0.7))
    .onChange(of: text) {
      if !text.isEmpty { error = nil }
    }
  }

  private func save() {
    guard !isEmpty else { return }
    if let message = model.saveThought(text) {
      error = message
      return
    }
    text = ""
    error = nil
    justSaved = true
    Task {
      try? await Task.sleep(for: .seconds(2))
      justSaved = false
    }
  }
}

#Preview("Capture field") {
  CaptureBox()
    .environment(AppModel.preview(withSamples: false))
    .padding(24)
    .frame(width: 640)
    .background(Theme.background)
    .preferredColorScheme(.dark)
}
