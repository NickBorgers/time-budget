// swift-tools-version: 6.0
import PackageDescription

// The platform-neutral core: allocations, the ledger, the alert rules and the
// classification steps. It has no UI, no capture and no model runtime, so it
// builds and tests on Linux (the devcontainer) as well as on macOS. The Mac app
// lives on top of it.
// The app target uses SwiftUI, and the model runtime uses MLX. Neither exists on
// Linux. Guarding them with #if os(macOS) removes them from the manifest
// entirely on Linux, so the devcontainer's `swift build` still sees only
// TimeBudgetCore and fetches no dependency.
var products: [Product] = [
  .library(name: "TimeBudgetCore", targets: ["TimeBudgetCore"])
]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
  .target(name: "TimeBudgetCore"),
  .testTarget(name: "TimeBudgetCoreTests", dependencies: ["TimeBudgetCore"]),
]

#if os(macOS)
  // mlx-swift-lm needs Swift 6.2 or later. These packages run the model on the
  // Mac. None of them makes a network request unless asked to download, and
  // the app never asks.
  dependencies += [
    .package(url: "https://github.com/ml-explore/mlx-swift", .upToNextMinor(from: "0.32.3")),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "3.32.3")),
    .package(
      url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.3.4")),
  ]
  products += [
    .executable(name: "TimeBudgetApp", targets: ["TimeBudgetApp"]),
    .executable(name: "model-check", targets: ["ModelCheck"]),
  ]
  targets += [
    // The OpenJev classifier on MLX. Platform glue only: the prompt, the math
    // and every decision are in TimeBudgetCore.
    .target(
      name: "TimeBudgetModel",
      dependencies: [
        "TimeBudgetCore",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "Tokenizers", package: "swift-transformers"),
      ]),
    .executableTarget(
      name: "TimeBudgetApp", dependencies: ["TimeBudgetCore", "TimeBudgetModel"]),
    // Milestone 1: run the model on a fixed set of slices, and write the
    // results for scripts/openjev_reference.py to compare.
    .executableTarget(name: "ModelCheck", dependencies: ["TimeBudgetCore", "TimeBudgetModel"]),
  ]
#endif

let package = Package(
  name: "time-budget",
  platforms: [.macOS(.v14)],
  products: products,
  dependencies: dependencies,
  targets: targets
)
