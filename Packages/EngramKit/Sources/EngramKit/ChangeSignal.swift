import CoreFoundation
import Foundation

/// A system-wide "the database changed" ping between processes.
///
/// GRDB observations only see writes made in the same process. The
/// connector runs in its own process, so after each write it posts a
/// Darwin notification and the open app re-reads what it shows.
public enum ChangeSignal {
  static let name = "io.github.m4rkellkka.Engram.databaseChanged"
  /// Posted on `NotificationCenter.default` in the receiving process.
  public static let notification = Notification.Name("EngramDatabaseChangedElsewhere")

  public static func post() {
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name as CFString), nil, nil,
      true)
  }

  /// Starts forwarding the Darwin notification to `notification`.
  public static func startListening() {
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(), nil,
      { _, _, _, _, _ in
        NotificationCenter.default.post(name: ChangeSignal.notification, object: nil)
      },
      name as CFString, nil, .deliverImmediately)
  }
}
