// swift-tools-version: 6.2
import PackageDescription

// Layers from coding-standards.md §1. Imports point down only, and a target's
// dependency list is the enforcement — not a reviewer's judgement.
//
// Gate (layer 3) now exists: F4.2 sends the transcript to an OpenAI-compatible
// endpoint, so the trust claim stopped being "there is no egress API" and became
// "there is exactly one, and it is 150 lines you can read". Note Agent does NOT
// depend on Gate and must not — an agent that opens a socket is a bug against
// I1, not a style issue (coding-standards.md §1). UI is the only layer that sees
// both, which is why the additive-only fallback lives there.
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
        .target(name: "Gate", dependencies: ["Contracts", "Tools"]),   // 3
        .target(name: "UI", dependencies: ["Contracts", "Agent", "Gate"]),  // 4
        .executableTarget(name: "PigeonEye", dependencies: ["UI"]),
        .executableTarget(name: "OCRCommand", dependencies: ["Contracts", "Tools"], path: "Sources/ocr-cli"),
        // UI is a test dependency because ReaderModel owns real logic — request
        // invalidation and the zoom step — and a review found bugs in both.
        // Fixtures/ is excluded, not declared as a resource: tests resolve it
        // through #filePath like every other fixture, so a bundle copy would be
        // a second home for the same file (§1.1).
        .testTarget(name: "PigeonEyeTests",
                    dependencies: ["Contracts", "Tools", "Agent", "Gate", "UI"],
                    exclude: ["Fixtures"]),
    ]
)
