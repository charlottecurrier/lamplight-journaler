// swift-tools-version:5.9
import PackageDescription

// This package exists so the app's non-UI logic (storage, streaks, "on this day",
// templates) can be built and tested without Xcode, including on Linux.
// The iOS app target compiles the same files directly (see project.yml).
let package = Package(
    name: "JournalCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "JournalCore", targets: ["JournalCore"]),
    ],
    targets: [
        .target(name: "JournalCore", path: "Sources/JournalCore"),
        .testTarget(name: "JournalCoreTests", dependencies: ["JournalCore"], path: "Tests/JournalCoreTests"),
    ]
)
