/// Input problems the UI can show as-is.
public enum EngramError: Error, Equatable, Sendable {
  case emptyThought
  case thoughtTooLong(limit: Int)
  case emptyProjectName
  case projectNameTooLong(limit: Int)
  case entryNotFound
  case projectNotFound
  case itemNotFound
  case emptyText
  case textTooLong(limit: Int)
  case unknownColor
  case duplicateItem

  public var message: String {
    switch self {
    case .emptyThought: "Write something first."
    case .thoughtTooLong(let limit): "Keep it under \(limit) characters."
    case .emptyProjectName: "Name the project."
    case .projectNameTooLong(let limit): "Keep the name under \(limit) characters."
    case .entryNotFound: "This entry no longer exists."
    case .projectNotFound: "This project no longer exists."
    case .itemNotFound: "This item no longer exists."
    case .emptyText: "Write something first."
    case .textTooLong(let limit): "Keep it under \(limit) characters."
    case .unknownColor: "Pick one of the project colors."
    case .duplicateItem: "That item is already on the page."
    }
  }
}
