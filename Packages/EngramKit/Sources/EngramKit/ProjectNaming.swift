import Foundation

/// Rules for new project names, slugs and colors.
public enum ProjectNaming {
  /// Project palette from the design tokens.
  public static let colors = ["#B79CFF", "#F2A65A", "#3FD0B6", "#7FA8FF", "#F48FB1", "#C9E26B"]
  public static let maxNameLength = 60
  static let maxSlugLength = 48

  private static let cyrillic: [Character: String] = [
    "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh",
    "з": "z", "и": "i", "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o",
    "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "kh", "ц": "ts",
    "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu",
    "я": "ya", "і": "i", "ї": "yi", "є": "ye", "ґ": "g",
  ]

  /// Trimmed name, or an error the UI can show.
  public static func validatedName(_ raw: String) throws(EngramError) -> String {
    let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { throw .emptyProjectName }
    guard name.count <= maxNameLength else { throw .projectNameTooLong(limit: maxNameLength) }
    return name
  }

  /// URL-safe slug (`^[a-z0-9]+(-[a-z0-9]+)*$`). Cyrillic is transliterated,
  /// because most project names here are Russian; anything else unusable
  /// becomes `project`.
  public static func slugify(_ name: String) -> String {
    // Transliterate before folding: decomposing would split "й" into "и" + a mark.
    let transliterated = name.lowercased().precomposedStringWithCanonicalMapping
      .map { cyrillic[$0] ?? String($0) }
      .joined()
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)

    var slug = ""
    var pendingDash = false
    for scalar in transliterated.unicodeScalars {
      if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
        if pendingDash && !slug.isEmpty { slug.append("-") }
        pendingDash = false
        slug.unicodeScalars.append(scalar)
      } else {
        pendingDash = true
      }
    }
    if slug.count > maxSlugLength {
      slug = String(slug.prefix(maxSlugLength))
      while slug.hasSuffix("-") { slug.removeLast() }
    }
    return slug.isEmpty ? "project" : slug
  }

  /// `base`, or `base-2`, `base-3`, … if that slug is taken.
  public static func uniqueSlug(_ base: String, taken: some Sequence<String>) -> String {
    let used = Set(taken)
    guard used.contains(base) else { return base }
    var n = 2
    while used.contains("\(base)-\(n)") { n += 1 }
    return "\(base)-\(n)"
  }

  /// First palette color no project uses yet, else the least used one.
  public static func pickColor(used: some Sequence<String>) -> String {
    var counts = Dictionary(uniqueKeysWithValues: colors.map { ($0, 0) })
    for color in used {
      let key = color.uppercased()
      if let count = counts[key] { counts[key] = count + 1 }
    }
    var best = colors[0]
    for color in colors where counts[color, default: 0] < counts[best, default: 0] {
      best = color
    }
    return best
  }
}
