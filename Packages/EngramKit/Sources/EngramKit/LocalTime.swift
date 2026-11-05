import Foundation

/// Dates as Claude should read them: in the user's local time, never UTC.
/// A UTC timestamp like `2026-11-05T21:00:00Z` for "Friday" in Istanbul
/// reads as "Thursday 21:00", so tool results use local offsets instead.
public enum LocalTime {
  /// `2026-11-07T18:00:00+03:00`.
  public static func timestamp(_ date: Date, in zone: TimeZone = .current) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = zone
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }

  /// A due date: just `2026-11-07` when it is midnight local time (a
  /// date-only deadline), otherwise a local timestamp.
  public static func due(_ date: Date, in zone: TimeZone = .current) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    guard calendar.startOfDay(for: date) == date else { return timestamp(date, in: zone) }
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }
}
