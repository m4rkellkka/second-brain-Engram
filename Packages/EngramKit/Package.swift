// swift-tools-version: 6.1
import PackageDescription

let package = Package(
  name: "EngramKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "EngramKit", targets: ["EngramKit"]),
    .library(name: "EngramMCP", targets: ["EngramMCP"]),
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
  ],
  targets: [
    .target(
      name: "EngramKit",
      dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
    ),
    .target(
      name: "EngramMCP",
      dependencies: ["EngramKit", .product(name: "MCP", package: "swift-sdk")]
    ),
    .testTarget(
      name: "EngramKitTests",
      dependencies: ["EngramKit"]
    ),
    .testTarget(
      name: "EngramMCPTests",
      dependencies: ["EngramMCP", .product(name: "MCP", package: "swift-sdk")]
    ),
  ]
)
