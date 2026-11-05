// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "EngramKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "EngramKit", targets: ["EngramKit"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0")
  ],
  targets: [
    .target(
      name: "EngramKit",
      dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
    ),
    .testTarget(
      name: "EngramKitTests",
      dependencies: ["EngramKit"]
    ),
  ]
)
