/// Input problems the UI can show as-is.
public enum EngramError: Error, Equatable, Sendable {
  case emptyThought
  case thoughtTooLong(limit: Int)
  case emptyProjectName
  case projectNameTooLong(limit: Int)
  case entryNotFound
  case projectNotFound

  public var message: String {
    switch self {
    case .emptyThought: "Write something first."
    case .thoughtTooLong(let limit): "Keep it under \(limit) characters."
    case .emptyProjectName: "Name the project."
    case .projectNameTooLong(let limit): "Keep the name under \(limit) characters."
    case .entryNotFound: "This entry no longer exists."
    case .projectNotFound: "This project no longer exists."
    }
  }
}
