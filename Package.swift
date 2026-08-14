// swift-tools-version: 6.2
import PackageDescription

// Layers from coding-standards.md §1. Imports point down only, and a target's
// dependency list is the enforcement — not a reviewer's judgement.
// Gate (layer 3) does not exist yet: F1 has no egress, and
// `rg 'URLSession|http' Sources` must stay empty.
let package = Package(
    name: "PigeonEye",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "PigeonEye", targets: ["PigeonEye"]),
        // Named `ocr` because spikes/page_index.py and eval/ shell out to ./ocr.
        .executable(name: "ocr", targets: ["OCRCommand"]),
    ],
    targets: [
        .target(name: "Contracts"),                                    // 0
        .target(name: "Tools", dependencies: ["Contracts"]),           // 1
        .target(name: "Agent", dependencies: ["Contracts", "Tools"]),  // 2
        .target(name: "UI", dependencies: ["Contracts", "Agent"]),     // 4
        .executableTarget(name: "PigeonEye", dependencies: ["UI"]),
        .executableTarget(name: "OCRCommand", dependencies: ["Contracts", "Tools"], path: "Sources/ocr-cli"),
        .testTarget(name: "PigeonEyeTests", dependencies: ["Contracts", "Tools", "Agent"]),
    ]
)
