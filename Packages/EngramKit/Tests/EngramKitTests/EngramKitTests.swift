import Testing

@testable import EngramKit

@Test func schemaVersionIsSet() {
  #expect(EngramKit.schemaVersion == "v1")
}
