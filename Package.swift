// swift-tools-version: 6.0
import PackageDescription

// The platform-neutral core: allocations, the ledger and the alert rules. It has
// no UI, no capture and no model runtime, so it builds and tests on Linux (the
// devcontainer) as well as on macOS. The Mac app lives on top of it.
// The app target uses SwiftUI, which does not exist on Linux. Guarding it with
// #if os(macOS) removes it from the manifest entirely on Linux, so the
// devcontainer's `swift build` still sees only TimeBudgetCore.
var products: [Product] = [
  .library(name: "TimeBudgetCore", targets: ["TimeBudgetCore"])
]
var targets: [Target] = [
  .target(name: "TimeBudgetCore"),
  .testTarget(name: "TimeBudgetCoreTests", dependencies: ["TimeBudgetCore"]),
]

#if os(macOS)
  products.append(.executable(name: "TimeBudgetApp", targets: ["TimeBudgetApp"]))
  targets.append(
    .executableTarget(name: "TimeBudgetApp", dependencies: ["TimeBudgetCore"]))
#endif

let package = Package(
  name: "time-budget",
  platforms: [.macOS(.v14)],
  products: products,
  targets: targets
)
