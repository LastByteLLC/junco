// swift-tools-version: 6.2
import PackageDescription
let package = Package(
  name: "Calc",
  targets: [
    .executableTarget(name: "Calc", path: "Sources"),
    .testTarget(name: "CalcTests", dependencies: ["Calc"], path: "Tests"),
  ]
)
