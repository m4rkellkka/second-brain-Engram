import EngramKit
import SwiftUI

extension View {
  /// A panel that floats over the content: a dark tint over a blur of
  /// whatever is behind it, with a thin cool border.
  func glassPanel(
    radius: CGFloat = Theme.cardRadius, border: Color = Theme.borderStrong.opacity(0.7),
    dashed: Bool = false
  ) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    return
      self
      .background {
        shape.fill(Theme.glass).background(.ultraThinMaterial, in: shape)
      }
      .overlay {
        shape.strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: dashed ? [4, 4] : []))
      }
  }

  /// A quiet card that sits on the background instead of floating.
  func quietCard(radius: CGFloat = Theme.cardRadius) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
    return background(shape.fill(Theme.surface)).overlay(shape.strokeBorder(Theme.border))
  }
}

/// A small uppercase label above a section.
struct SectionLabel: View {
  let text: String
  var color: Color = Theme.textSubtle

  init(_ text: String, color: Color = Theme.textSubtle) {
    self.text = text
    self.color = color
  }

  var body: some View {
    Text(text.uppercased())
      .font(.geistMono(11, .medium))
      .tracking(0.9)
      .foregroundStyle(color)
  }
}

/// The one strong button on a screen: cyan with dark text.
struct AccentButtonStyle: ButtonStyle {
  var height: CGFloat = 32

  func makeBody(configuration: Configuration) -> some View {
    AccentLabel(configuration: configuration, height: height)
  }

  private struct AccentLabel: View {
    let configuration: Configuration
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .font(.geist(13, .medium))
        .foregroundStyle(isEnabled ? Theme.onAccent : Theme.textSubtle)
        .padding(.horizontal, 14)
        .frame(height: height)
        .background(
          RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            .fill(isEnabled ? Theme.accent : Theme.surface2)
        )
        .opacity(configuration.isPressed ? 0.85 : 1)
        .contentShape(Rectangle())
    }
  }
}

/// A secondary button: outlined, on glass.
struct QuietButtonStyle: ButtonStyle {
  var height: CGFloat = 32

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.geist(13))
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 12)
      .frame(height: height)
      .background(
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
          .fill(configuration.isPressed ? Theme.surface2 : Theme.surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
          .strokeBorder(Theme.borderStrong)
      )
      .contentShape(Rectangle())
  }
}

/// A rounded filter chip; selected ones get a wash of the accent.
struct FilterChip: View {
  let title: String
  let isSelected: Bool
  var dashed = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.geist(12.5, isSelected ? .medium : .regular))
        .foregroundStyle(isSelected ? Theme.accent : Theme.textMuted)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(isSelected ? Theme.accentWash : .clear))
        .overlay(
          Capsule().strokeBorder(
            isSelected ? Theme.accent.opacity(0.45) : Theme.borderStrong.opacity(0.7),
            style: StrokeStyle(lineWidth: 1, dash: dashed && !isSelected ? [3, 3] : []))
        )
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// A compact outlined button with an SF Symbol.
struct SmallButton: View {
  let title: String
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol)
        .font(.geist(12, .medium))
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.borderStrong))
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
  }
}

/// An entry's kind in its color, e.g. "idea".
struct KindBadge: View {
  let kind: EntryKind

  var body: some View {
    let color = Theme.kindColor(kind.rawValue)
    Text(kind.rawValue)
      .font(.geistMono(11, .medium))
      .foregroundStyle(color)
      .padding(.horizontal, 8)
      .frame(height: 20)
      .background(Capsule().fill(color.opacity(0.12)))
  }
}

/// "journal · 5 Nov" in the pale text color, beside kind badges.
struct JournalBadge: View {
  let date: Date

  var body: some View {
    Text("journal · " + date.formatted(.dateTime.day().month(.abbreviated)))
      .font(.geistMono(11, .medium))
      .foregroundStyle(Theme.text)
      .padding(.horizontal, 8)
      .frame(height: 20)
      .background(Capsule().fill(Theme.text.opacity(0.1)))
  }
}

/// A project's color dot and name.
struct ProjectTag: View {
  let project: Project
  var font: Font = .geist(12.5)

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(Color(hexString: project.color)).frame(width: 7, height: 7)
      Text(project.name).font(font).foregroundStyle(Theme.textMuted).lineLimit(1)
    }
  }
}
