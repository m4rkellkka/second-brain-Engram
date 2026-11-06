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

  /// One line with Save beside it, for the top of the Inbox.
  var compact = false

  var body: some View {
    if compact {
      HStack(spacing: 10) {
        editor(placeholder: justSaved ? "Saved to Inbox ✓" : "Jot a thought…  ⌘N")
          .frame(height: 22)
        if let error {
          Text(error).font(.geist(12)).foregroundStyle(Theme.danger).lineLimit(1)
        }
        Button("Save", action: save)
          .buttonStyle(AccentButtonStyle(height: 30))
          .disabled(isEmpty)
      }
      .padding(.leading, 16)
      .padding(.trailing, 8)
      .padding(.vertical, 8)
      .glassPanel(radius: 14)
      .onChange(of: text) {
        if !text.isEmpty { error = nil }
      }
    } else {
      full
    }
  }

  private func editor(placeholder: String) -> some View {
    ZStack(alignment: .topLeading) {
      if text.isEmpty {
        Text(placeholder)
          .font(.geist(compact ? 14 : 15))
          .foregroundStyle(Theme.textSubtle)
          .padding(.top, compact ? 1 : 2)
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
  }

  private var full: some View {
    VStack(alignment: .leading, spacing: 10) {
      editor(placeholder: "What's on your mind?")
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
