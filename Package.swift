// swift-tools-version: 6.0
import PackageDescription

// The platform-neutral core: allocations, the ledger and the alert rules. It has
// no UI, no capture and no model runtime, so it builds and tests on Linux (the
// devcontainer) as well as on macOS. The Mac app lives on top of it.
let package = Package(
  name: "time-budget",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TimeBudgetCore", targets: ["TimeBudgetCore"])
  ],
  targets: [
    .target(name: "TimeBudgetCore"),
    .testTarget(name: "TimeBudgetCoreTests", dependencies: ["TimeBudgetCore"]),
  ]
)
